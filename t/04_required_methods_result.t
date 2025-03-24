#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More tests => 11;

use PVE::Storage::Custom::StorPoolPlugin;

my $ver = \%{PVE::Storage::Custom::StorPoolPlugin::};


sub get_ver {
    PVE::Storage::Custom::StorPoolPlugin::api();
}

sub set_apiver { # Increments on pve-storage API changes. Current version is 10
    no warnings qw/redefine misc/;
    my $ver = shift;
    *PVE::Storage::APIVER = defined $ver ? sub { $ver } : undef
}

sub set_apiage { # Backward compatible number of versions
    no warnings qw/redefine misc/;
    my $ver = shift;
    *PVE::Storage::APIAGE = defined $ver ? sub { $ver } : undef
}

# api()

set_apiver();
set_apiage();
is( get_ver(), 3, 'Min API version' ); # Returns min version when the APIVER() is missing

set_apiver(10);
set_apiage(1);
is( get_ver(), 10, 'Max API verion' );

set_apiver(4);
set_apiage(1);
is( get_ver(), 4, 'Version match' );

set_apiver(11);
set_apiage(1);
is( get_ver(), 10, 'Current API version' );

set_apiver(11);
set_apiage(0);
is( get_ver(), 3, 'API version not compatible, age 0' );

set_apiver(12);
set_apiage(1);
is( get_ver(), 3, 'API version not compatible, age 1' );

set_apiver(500);
set_apiage(499);
is( get_ver(), 10, 'API version high AGE high' );

set_apiver(500);
set_apiage(1);
is( get_ver(), 3, 'API version high AGE low' );

# type()
is( PVE::Storage::Custom::StorPoolPlugin::type, 'storpool', 'Plugin type storpool' );

# plugindata()

my $plugin_data = {
	content => [ { images => 1, rootdir => 1, iso => 1, backup => 1, none => 1 },
             { images => 1,  rootdir => 1 }
	],
    format => [ { raw => 1 } , 'raw' ],
};

is_deeply( PVE::Storage::Custom::StorPoolPlugin::plugindata(), $plugin_data, 'plugindata correct data' );

# options()

my $options = {
    nodes        => { optional => 1 },
    shared       => { optional => 1 },
    disable      => { optional => 1 },
    maxfiles     => { optional => 1 },
    content      => { optional => 1 },
    format       => { optional => 1 },
    'extra-tags' => { optional => 1 },
    template     => { optional => 1 },
};

is_deeply( PVE::Storage::Custom::StorPoolPlugin::options(), $options, 'options correct data' );

#done_testing();
