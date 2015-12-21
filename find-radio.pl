#!/usr/bin/env perl

use 5.014;
use warnings;
use autodie;

my @possibilities = glob('/dev/cu.SLAB_USB*');
my $device;

for my $dev (@possibilities) {
  if ( system("rigctl -r $dev -m 370 f 2>&1 > /dev/null") == 0 ) {
    $device = $dev;
    say "Found it at $device";
    last;
  }
  say "It's not $dev";
}

die "Didn't find the radio :<\n" unless $device;

my $current_target = readlink '/dev/rig';
if ($current_target eq $device) {
  say "/dev/rig symlink is already correct";
  exit 0;
}

if($< == 0) {
  system 'ln', '-fs', $device, '/dev/rig';
}
else {
  say "ln -fs $device /dev/rig";
}
