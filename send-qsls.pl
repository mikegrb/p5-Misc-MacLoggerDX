#!/usr/bin/env perl

=head1 WAT

This script uploads QSL entries with empty QSL Sent columns to eQSL and QRZ.com.
Entries can easily be sent to LoTW from the QRZ site after they are imported there.

=cut

use strict;
use warnings;
use 5.014;

use autodie;
use DBI;
use Data::Printer;
use POSIX 'strftime';
use Mojo::UserAgent;
use YAML::Tiny;

my $config          = YAML::Tiny->read('config.yml')->[0];
my $QRZ_LOGBOOK_KEY = $config->{QRZ_LOGBOOK_KEY};
my $EQSL_USER       = $config->{EQSL_USER};
my $EQSL_PWD        = $config->{EQSL_PWD};
my $lotw_file       = 'log/temp_lotw.adi';

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

my %send_to = (
  eqsl => \&log_to_eqsl,
  qrz  => \&log_to_qrz,
);

my $dbh = DBI->connect("dbi:SQLite:dbname=$config->{DB}");
my $ua = Mojo::UserAgent->new;

my $sth = $dbh->prepare(q{
  SELECT * FROM qso_table_v007
  WHERE (qsl_sent IS NULL OR qsl_sent = '' or LENGTH(qsl_sent) < 13)
    AND comments NOT LIKE '%NO AUTO%'
});
$sth->execute;

my $filename = strftime( 'log/%Y-%m-%d.adi', gmtime );
open( my $lotw_fh, '>',  $lotw_file );
open( my $fh,      '>>', $filename );

my ( $count, %results, %counts );
while ( my $row = $sth->fetchrow_hashref ) {
  say $row->{call};
  $row->{comments} =~ s/(?:, )?Uploaded to Club Log \d{4}-\d{2}-\d{2} \d{2}:\d{2}$//;
  $row->{qso_date} = strftime( "%Y%m%d", gmtime( $row->{qso_start} ) );
  $row->{time_on}  = strftime( "%H%M", gmtime( $row->{qso_start} ) );
  say $fh my $record = generate_record($row);
  if ( !check_sent( $row, 'lotw' ) ) {
    say $lotw_fh $record;
    $counts{lotw}++;
  }

  for my $site ( 'eqsl', 'qrz' ) {
    if(check_sent( $row, $site )) {
      $results{ $row->{pk} }{$site} = 1;
      next;
    }
    $results{ $row->{pk} }{$site} = $send_to{$site}->($record);
    $count++;
    $counts{$site}++;
  }
}
close ($lotw_fh);

log_to_lotw() if -s $lotw_file;

exit unless $count;
say join(', ', map { "$_: $counts{$_}" } keys %counts);
update_sent();
reload_maclogger_view();
system './export-json.pl' if $config->{auto_json};

sub check_sent {
  my ($row, $where) = @_;
  return unless $row->{qsl_sent};
  return $row->{qsl_sent} =~ m/\Q$where\E/;
}

sub update_sent {
  my $mark_exported = $dbh->prepare(q{
    UPDATE qso_table_v007 SET qsl_sent = ? WHERE pk = ?
  });

  for my $pk (keys %results) {
    my $exported_text = join( ',', grep { $results{$pk}{$_} } keys( $results{$pk} ) );
    $mark_exported->execute( $exported_text, $pk );
  }

}

sub generate_record {
  my $record = shift;
  my $entry = join ' ', map { generate_field( $_, $record->{ $FIELDS{$_} } ) } @FIELDS;
  return $entry . " <eor>";
}

sub generate_field {
  my ($field, $data) = @_;
  return '' unless $data;
  my $data_length = length($data);
  return "<$field:$data_length>$data";
}

sub log_to_eqsl {
  my $record = shift;
  my $tx = $ua->get( 'http://www.eqsl.cc/qslcard/importADIF.cfm' => form =>
      { EQSL_USER => $EQSL_USER, EQSL_PSWD => $EQSL_PWD, ADIFData => $record } );
  if (! $tx->success ) {
    my $err = $tx->error;
    warn "$err->{code} reponse from eQSL post.\n";
    return;
  }
  else {
    say " eQSL: " . $tx->success->dom->at('body')->text;
    return 1;
  }
}

sub log_to_qrz {
  my $record = shift;
  my $tx = $ua->post( 'http://logbook.qrz.com/api' => form =>
      { KEY => $QRZ_LOGBOOK_KEY, ACTION => 'INSERT', ADIF => $record } );
    my $response = $tx->success;
  if (! $response ) {
    my $err = $tx->error;
    warn "$err->{code} reponse from QRZ post.\n";
    return;
  }
  else {
    say " QRZ:  " . $response->body;
    return 1;
  }
}

sub log_to_lotw {
  my @args = (
    $config->{lotw_path}, '-d', '-q', '-u', '-c', $config->{lotw_call}, '-a', 'compliant', '-l',
    $config->{lotw_site}, '-x', $lotw_file,
    '2>log/lotw_out.log'
  );
  ( system join( ' ', @args ) ) == 0 or do {
    printf "Problem uploading to lotw, tqsl exited with exit code %d\n", $? >> 8;
    return;
  };

  if (-s 'log/lotw_out.log') {
    open my $lotw_log_fh, '<', 'log/lotw_out.log';
    my $log = join('', <$lotw_log_fh>);
    close $lotw_log_fh;
    if ($log =~ m/\([09]\)$/m) {
      for my $pk ( keys %results ) {
        $results{$pk}{lotw} = 1;
      }
      $count += $counts{lotw};
    }
    else {
      say "LoTW error:\n$log";
    }
  }
  else {
    say "LoTW Unknown error.";
  }
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
