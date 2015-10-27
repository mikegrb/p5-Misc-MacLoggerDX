#!/usr/bin/env perl

=head1 WAT

This script uploads QSL entries with empty QSL Sent columns to eQSL and QRZ.com.
Entries can easily be sent to LoTW from the QRZ site after they are imported there.
After running, reload your DB by selecting File -> Recent -> Your Current Log in
MacLoggerDX,

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

my $ua = Mojo::UserAgent->new;

my $sent_time = strftime("exported %Y-%M-%d %H:%M", localtime);
my $mark_exported = $dbh->prepare(q{
  UPDATE qso_table_v007 SET qsl_sent = ? WHERE pk = ?
});

my $sth = $dbh->prepare(q{SELECT * FROM qso_table_v007 WHERE (qsl_sent IS NULL OR qsl_sent = '') AND comments NOT LIKE '%NO AUTO%'});
$sth->execute;

my $filename = strftime( 'log/%Y-%m-%d.adi', gmtime );
open( my $fh, '>>', $filename );
while ( my $row = $sth->fetchrow_hashref ) {
  say $row->{call};
  $row->{qso_date} = strftime( "%Y%m%d", gmtime( $row->{qso_start} ) );
  $row->{time_on}  = strftime( "%H%M", gmtime( $row->{qso_start} ) );
  say $fh my $record = generate_record($row);
  log_to_eqsl($record);
  log_to_qrz($record);
  $mark_exported->execute( $sent_time, $row->{pk} );
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
  }
  else {
    say " eQSL: " . $tx->success->dom->at('body')->text;
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
  }
  else {
    say " QRZ:  " . $response->body;
  }
}
}
