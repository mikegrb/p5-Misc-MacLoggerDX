#!/usr/bin/env perl

=head1 WAT

This script tallies points for the Feld Hell club Gridloc Hell award.

See https://sites.google.com/site/feldhellclub/Home/oldfiles/awards/gridloc-hell

=cut

use strict;
use warnings;
use 5.014;

use autodie;
use DBI;
use Data::Printer;
use POSIX 'strftime';
use YAML::Tiny;

my $config = YAML::Tiny->read('config.yml')->[0];
my $dbh    = DBI->connect("dbi:SQLite:dbname=$config->{DB}");
my $fhdb   = DBI->connect("dbi:CSV:");
my $get_fhn
  = $fhdb->prepare(q{SELECT FHC_ FROM fh-members.csv WHERE CALLSIGN = ?});

my $sth = $dbh->prepare(q{
  SELECT COALESCE(NULLIF(SUBSTR(grid, 3,2), '00' ), 100) AS 'fh_points', *
  FROM qso_table_v007
  WHERE qso_start >= 1272672000 AND mode like '%ELL'
  ORDER BY qso_done ASC
});
$sth->execute;

say join( "\t", "When\t\t", 'Call', 'FH#', 'Band', 'Grid', 'Points', 'Score' );
my ( %got, $score );

while ( my $row = $sth->fetchrow_hashref ) {
  next if exists $got{ $row->{call} }{ uc $row->{band_rx} };
  $got{ $row->{call} }{ uc $row->{band_rx} } = 1;
  $score += $row->{fh_points};
  my $date_time = strftime( '%Y-%m-%d %H:%M', gmtime( $row->{qso_done} ) );
  say join( "\t",
    $date_time, $row->{call}, fh_member( $row->{call} ),
    uc($row->{band_rx}), $row->{grid}, $row->{fh_points}, $score );
}

sub fh_member {
  my $call = shift;
  my ($fh) = $fhdb->selectrow_array( $get_fhn, undef, $call );
  return $fh || "n/a";
}
