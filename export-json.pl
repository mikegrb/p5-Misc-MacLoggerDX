#!/usr/bin/env perl

use strict;
use warnings;

use 5.014;

use autodie;
use DBI;
use Data::Printer;
use YAML::Tiny;
use JSON;
use Locale::Country;


my %overrides = (
  England            => 'GB',
  Scotland           => 'GB',
  Wales              => 'GB',
  'Northern Ireland' => 'GB',
  'Canary Islands'   => 'ES',
);

my $config          = YAML::Tiny->read('config.yml')->[0];
my $dbh = DBI->connect("dbi:SQLite:dbname=$config->{DB}");


my $sth = $dbh->prepare(q{SELECT * FROM qso_table_v007});
$sth->execute;

my ( %qso_for, %lotw_for, %eqsl_for );
while ( my $row = $sth->fetchrow_hashref ) {
  my ( $lotw, $eqsl ) = is_confirmed($row);

  my $code
    = exists( $overrides{ $row->{postal_country} } )
    ? $overrides{ $row->{postal_country} }
    : country2code( $row->{postal_country} );
  unless ($code) {
    warn "Didn't get country for $row->{postal_country}, $row->{call}\n";
    next;
  }
  $code = uc $code;
  $qso_for{$code}++;
  $lotw_for{$code}++ if $lotw;
  $eqsl_for{$code}++ if $eqsl;

  if ($row->{postal_country} eq 'United States') {
    $qso_for{ 'US-' . $row->{state} }++;
    $lotw_for{ 'US-' . $row->{state} }++ if $lotw;
    $eqsl_for{ 'US-' . $row->{state} }++ if $eqsl;
  }
}

exit unless keys %qso_for;

open my $fh, '>', 'map/qso.json';
say $fh to_json(
  { qso  => \%qso_for,
    lotw => \%lotw_for,
    eqsl => \%eqsl_for
  } );
close($fh);

sub is_confirmed {
  my $raw = shift->{qsl_received};
  return ( 0, 0 ) unless $raw;

  my $eqsl = ( $raw =~ m/eQSL\.cc:Y/ ) ? 1 : 0;
  my $lotw = ( $raw =~ m/LoTW:/ )      ? 1 : 0;

  return ( $lotw, $eqsl );
}
