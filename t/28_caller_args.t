#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More tests => 6;
use PVE::Storage::Custom::StorPoolPlugin;

sub x { a(@_, 0) }
sub a { b(@_, 1) }
sub b { c(@_, 2) }
sub c { args(1) }
sub args { PVE::Storage::Custom::StorPoolPlugin::_get_caller_args(shift) }


is( args(1), undef, "Caller main");
is( args(0), 1, "Caller main 0 lvl");

is_deeply( [ x({test=>666}) ], [{test=>666},0,1,2], "Caller 3 lvl deep" );
is_deeply( [ a({test=>666}) ], [{test=>666},1,2],   "Caller 2 lvl deep" );
is_deeply( [ b({test=>666}) ], [{test=>666},2],     "Caller 1 lvl deep" );
is_deeply( [ c({test=>666}) ], [{test=>666}],       "Caller 0 lvl deep" );


