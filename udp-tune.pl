#!/usr/bin/env perl

use 5.014;
use strict;
use autodie;

use Cache::LRU;
use IO::Socket::INET;
use RPC::XML::Client;
use Data::Printer;

my $OFFSET     = 1500;
my $MLDX_NAME  = "Michael’s MacBook Pro";
my $FREQ_CACHE = 2000;

my %MODE_MAP = (
  PSK31 => 'BPSK31',
);

my $fldigi = RPC::XML::Client->new('http://127.0.0.1:7362/');
my $sock = IO::Socket::INET->new(
  LocalPort => 9932,
  Proto     => 'udp'
) or die;
my $cache = Cache::LRU->new( size => $FREQ_CACHE );

my $buffer;
while ( $sock->recv( $buffer = '', 9000 ) ) {
  if ( $buffer =~ m/^\d+ \Q$MLDX_NAME\E \[(.*)\]$/ ) {

    my ( $type, $content ) = split /:/, $1, 2;

    my %data;
    for my $data ( split /, /, $content ) {
      my ( $key, $value ) = split /:/, $data;
      $data{$key} = $value;
    }

    if ( $type eq 'SpotTune' ) {
      my $call = $cache->get( $data{RxMHz} ) || '';
      say "Tune request for $call $data{Mode} on $data{Band} at $data{RxMHz}";
      tune_fldigi( $data{RxMHz}, $data{Mode}, $call );
    }

    elsif ( $type eq 'Spot Report' ) {
      $cache->set( $data{RxMHz}, $data{Call} );
    }

    elsif ( $type eq 'Lookup Report' ) {
    }

    else {
      say "Received $type packet:";
      p %data;
    }
  }
  else {
    say "Unrecognized Packet: $buffer";
  }
}

sub tune_fldigi {
  my ( $freq_mhz, $mode, $call ) = @_;

  $mode = $MODE_MAP{$mode} if exists $MODE_MAP{$mode};

  my $target_hz = ( $freq_mhz * 1000 * 1000 ) - $OFFSET;

  my %r;
  $r{prev_freq} = $fldigi->send_request( 'main.set_frequency', $target_hz . '.0' );
  $r{prev_mode} = $fldigi->send_request( 'modem.set_by_name', $mode );
  $r{offset}    = $fldigi->send_request( 'modem.set_carrier', $OFFSET );
  $r{clear}     = $fldigi->send_request( 'log.clear' );
  $r{call}  = $fldigi->send_request( 'log.set_call', $call ) if $call;

  for my $key ( keys %r ) {
    next unless $r{$key};
    if (! ref $r{$key}) {
      say "Error for $key: $r{$key}";
    }
    elsif ( $r{$key} =~ m/ / ) {
      say "Fldigi Error for $key: $r{$key}->value";
    }
  }
}
