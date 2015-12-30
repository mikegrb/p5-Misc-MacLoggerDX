#!/usr/bin/env perl

use 5.014;
use strict;
use autodie;

use RPC::XML::Client;
use Data::Dumper;

my ($method, $arg) = @ARGV;
die "Usage: $0 method_name <method_arg>\n\tTry fldigi.list for method_name\n" unless $method;

my $fldigi = RPC::XML::Client->new('http://127.0.0.1:7362/');
my $result = $fldigi->send_request( $method, ( $arg ? $arg : () ) );
my $response = decode_response($result);
my $response = decode_response($result);

say Data::Dumper->Dump( [$response], ['response'] );

sub decode_response {
  my $resp = shift;

  return $resp unless ref($resp) =~ m/RPC::XML::(\w+)$/;
  my $type = $1;

  if ($type eq 'string' or $type eq 'i4') {
    my $string = $$resp;
    return $string;
  }

  if ($type eq 'struct' or $type eq 'fault') {
    my %hash = %$resp;
    for my $key (%hash) {
      $hash{$key} = decode_response( $hash{$key} );
    }
    %hash = map { $hash{$_} ? ( $_ => $hash{$_} ) : () } keys %hash;
    return \%hash;
  }

  if ($type eq 'array') {
    my @array = @$resp;
    @array = map { decode_response($_) } @array;
    return \@array;
  }

  warn "Unknown type: $type";
}
