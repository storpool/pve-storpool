#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;
use version;

use PVE::Storage::Custom::StorPoolPlugin;

my $ver = $PVE::Storage::Custom::StorPoolPlugin::VERSION;

is( defined $ver, 1 );
is( version->parse($ver)->is_qv, 1 );

done_testing();
