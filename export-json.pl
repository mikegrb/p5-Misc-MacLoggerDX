#!/usr/bin/env perl

use strict;
use warnings;

use 5.014;

use autodie;
use DBI;
use JSON;
use Template;
use YAML::Tiny;
use Locale::Country;
use POSIX 'strftime';

my $GRID_MAX = shift || 0;

# Mostly Autonomious Regions
my %overrides = (
  England            => 'GB',
  Scotland           => 'GB',
  Wales              => 'GB',
  'Northern Ireland' => 'GB',
  'Canary Islands'   => 'ES',
  Kosovo             => 'XK',
  Kaliningrad        => 'RU',
  Corsica            => 'FR',
  Bonaire            => 'NL',
  'European Russia'  => 'RU',
  'Asiatic Russia'   => 'RU',
  Hawaii             => 'US',
  Alaska             => 'US',
  'Madeira Island'   => 'PT',
  'Slovak Republic'  => 'SK',
  'Sardinia'         => 'IT',
  'St. Barthelemy'   => 'BL',
  'Guantanamo Bay'   => 'CU',
  'Azores'           => 'PT',
  'Balearic Islands' => 'ES',
  'Cape Verde'       => 'CV',
  'San Andres and Providencia'  => 'CO',
  'St Kitts and Nevis'          => 'KN',
  'Turks and  Caicos Islands'   => 'TC',
  'Federal Republic of Germany' => 'DE',
);

my $DESCRIPTION = q{<h3>[% call %]</h3><div style="line-height: 1.2em">Worked: [% qso_date %]<br>[% mode %] on [% tx_frequency %] MHz<br>LoTW: [% lotw %] eQSL: [% eqsl %]<br>DXCC: [% dxcc_country %]<br>Name: [% first_name %]</div>};

my $config = YAML::Tiny->read('config.yml')->[0];
my $dbh    = DBI->connect("dbi:SQLite:dbname=$config->{DB}");
my $tt     = Template->new;

my $sth = $dbh->prepare(q{
  SELECT * FROM qso_table_v007
  WHERE (comments NOT LIKE '%NO AUTO%' OR comments IS NULL)
  ORDER BY qso_done DESC
});
$sth->execute;

my ( %qso_for, %lotw_for, %grid_count, %eqsl_for, @points );
while ( my $row = $sth->fetchrow_hashref ) {
  my ( $lotw, $eqsl ) = is_confirmed($row);

  my $code
    = exists( $overrides{ $row->{postal_country} } )
    ? $overrides{ $row->{postal_country} }
    : country2code( $row->{postal_country} );

  if ($code) {
    $code = uc $code;
    $code = 'PR' if $code eq 'US' && $row->{state} && $row->{state} eq 'PR';

    $qso_for{$code}++;
    $lotw_for{$code}++ if $lotw;
    $eqsl_for{$code}++ if $eqsl;

    if ($row->{postal_country} eq 'United States' && $row->{state} ) {
      $qso_for{ 'US-' . $row->{state} }++;
      $lotw_for{ 'US-' . $row->{state} }++ if $lotw;
      $eqsl_for{ 'US-' . $row->{state} }++ if $eqsl;
    }
  }
  else {
    warn "Didn't get country for $row->{postal_country}, $row->{call}\n";
  }

  # geojson
  if ($GRID_MAX) {
    next if $grid_count{ substr $row->{grid}, 0, 4 }++ > $GRID_MAX;
  }

  $row->{lotw} = $lotw ? 'Y' : 'N';
  $row->{eqsl} = $eqsl ? 'Y' : 'N';
  $row->{tx_frequency} = sprintf( '%.5f', $row->{tx_frequency});
  $row->{first_name} ||= $row->{last_name} || ' ';
  $row->{qso_date} = strftime( '%F', gmtime( $row->{qso_done} ) );
  my $description;
  $tt->process(\$DESCRIPTION, $row, \$description) or die $tt->error;

  push @points, {
    type => 'Feature',
    geometry => {
      type => 'Point',
      coordinates => [ $row->{longitude}, $row->{latitude} ],
    },
    properties => {
      name => $row->{call},
      description => $description,
    }
  };
}

exit unless keys %qso_for;

open my $fh, '>', 'map/qso.json';
say $fh to_json(
  { qso  => \%qso_for,
    lotw => \%lotw_for,
    eqsl => \%eqsl_for
  } );
close($fh);

open( $fh, '>', 'map/qsogeo.json' );
say $fh to_json { type => 'FeatureCollection', features => \@points };
close $fh;


sub is_confirmed {
  my $raw = shift->{qsl_received};
  return ( 0, 0 ) unless $raw;

  my $eqsl = ( $raw =~ m/eQSL\.cc:Y/ ) ? 1 : 0;
  my $lotw = ( $raw =~ m/LoTW:/ )      ? 1 : 0;

  return ( $lotw, $eqsl );
}
