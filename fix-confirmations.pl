#!/usr/bin/env perl

=head1 WAT

If you use DQSL manager to import eQSL & LoTW confirmations into MacLoggerDX you
can somtetimes end up with duplicates in the QSL Received column of the log such as
C<eQSL.cc:Y, LoTW:20150917, LoTW:20150919>.  This script keeps just the first
confirmation entry for each type.

=cut

use strict;
use warnings;
use 5.014;

use autodie;
use DBI;
use YAML::Tiny;

my $config          = YAML::Tiny->read('config.yml')->[0];
my $QRZ_LOGBOOK_KEY = $config->{QRZ_LOGBOOK_KEY};
my $EQSL_USER       = $config->{EQSL_USER};
my $EQSL_PWD        = $config->{EQSL_PWD};

my @FIELDS = (qw(call gridsquare mode rst_sent rst_rcvd qso_date time_on band freq station_callsign my_gridsquare tx_pwr comment));
my %FIELDS = (
  call             => 'call',
  gridsquare       => 'grid',
  mode             => 'mode',
  rst_sent         => 'rst_sent',
  rst_rcvd         => 'rst_received',
  qso_date         => 'qso_date',
  time_on          => 'time_on',
  band             => 'band_rx',
  freq             => 'rx_frequency',
  station_callsign => 'my_call',
  my_gridsquare    => 'my_grid',
  tx_pwr           => 'power',
  comment          => 'comments',
);

my $dbh = DBI->connect("dbi:SQLite:dbname=$config->{DB}");

my $fix_it = $dbh->prepare(q{ UPDATE qso_table_v007 SET qsl_received = ? WHERE pk = ? });

my $sth = $dbh->prepare(q{ SELECT * FROM qso_table_v007 WHERE LENGTH(qsl_received) > 24 });
$sth->execute;

my $fixed = 0;
while(my $row = $sth->fetchrow_hashref) {
  # eQSL.cc:Y, LoTW:20150917, LoTW:20150919
  my @records = split /,/, $row->{qsl_received};

  my %confirmations;
  for my $record (@records) {
    my ($where, $data) = map { trim($_) } split /:/, $record;
    next if $where eq 'Y';
    $confirmations{$where} ||= $data; # just keep the first one we see
  }
  my $fixed_shit = join ', ', sort map { "$_:$confirmations{$_}" } keys %confirmations;

  say "$row->{call} $row->{qsl_received} -> $fixed_shit";
  $fix_it->execute( $fixed_shit, $row->{pk} );
  $fixed++;
}
reload_maclogger_view() if $fixed;

sub trim {
  my $text = shift;
  return unless $text;
  $text =~ s/^\s+//;
  $text =~ s/\s+$//;
  return $text;
}

sub osascript($) {
    open( my $fh, '-|', 'osascript',
        map { ( '-e', $_ ) } split( /\n/, $_[0] ) );
    my $output = join '', <$fh>;
    close $fh;
    return $output;
}

sub reload_maclogger_view {
  osascript <<'  END';
    tell application "System Events"
      tell process "MacLoggerDX"
        activate
        delay 1
        click menu item 1 of menu of menu item "Open Recent" of menu 1 of menu bar item "File" of menu bar 1
      end tell
    end tell
  END
}
