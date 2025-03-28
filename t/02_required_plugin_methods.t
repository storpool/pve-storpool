#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More tests => 8;

use PVE::Storage::Custom::StorPoolPlugin;

my $ver = \%{PVE::Storage::Custom::StorPoolPlugin::};


ok( $ver->{api},        'sub api exists' );
ok( $ver->{type},       'sub type exists' );
ok( $ver->{plugindata}, 'sub plugindata exists' );
ok( $ver->{options},    'sub options exists' );

is( ref \$ver->{api},        'GLOB', 'sub api' );
is( ref \$ver->{type},       'GLOB', 'sub type' );
is( ref \$ver->{plugindata}, 'GLOB', 'sub plugindata' );
is( ref \$ver->{options},    'GLOB', 'sub options' );

