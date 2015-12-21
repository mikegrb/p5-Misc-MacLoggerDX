#!/usr/bin/env perl

use 5.014;
use strict;
use autodie;

use IO::Socket::INET;
use RPC::XML::Client;
use Data::Printer;

my $OFFSET    = 1500;
my $MLDX_NAME = "Michael’s MacBook Pro";

my $fldigi = RPC::XML::Client->new('http://127.0.0.1:7362/');
my $sock = IO::Socket::INET->new(
  LocalPort => 9932,
  Proto     => 'udp'
) or die;

my $buffer;
while($sock->recv($buffer = '', 9000)) {
  # 000107 Michael’s MacBook Pro [SpotTune:RxMHz:3.56200, TxMHz:3.56200, Band:80M, Mode:CW]
  if ($buffer =~ m/^\d+ \Q$MLDX_NAME\E \[SpotTune:RxMHz:([^,]+), TxMHz:([^,]+), Band:(\d+)M, Mode:([^\]]+)\]$/) {
    my ($rx, $tx, $band, $mode) = ($1, $2, $3, $4);
    say "Tune request for $mode on $band at $rx";
    tune_fldigi( $rx, $mode );
  }
  elsif ($buffer =~ m/Spot Report/) {
    # too many of these to print them all
    next
  }
  else {
    say $buffer;
  }
}

sub tune_fldigi {
  my ( $freq_mhz, $mode ) = @_;
  my $target_hz = ( $freq_mhz * 1000 * 1000 ) - $OFFSET;
  my $prev_freq = $fldigi->send_request( 'main.set_frequency', $target_hz . '.0' );
  my $prev_mode = $fldigi->send_request( 'modem.set_by_name', $mode );
  my $offset    = $fldigi->send_request( 'modem.set_carrier', $OFFSET );
  for ( $prev_freq, $prev_mode, $offset ) {
    die "Error $_\n" unless ref $_;
    p $_;
    $_ = $_->value;
  }
}
