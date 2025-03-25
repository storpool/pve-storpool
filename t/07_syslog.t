#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;

use PVE::Storage::Custom::StorPoolPlugin;

my $ver = \%{PVE::Storage::Custom::StorPoolPlugin::};

SKIP: {
    skip 'WIP'
}

done_testing();
