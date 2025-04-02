#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More tests => 3;

use PVE::Storage::Custom::StorPoolPlugin;

# log_info calls syslog

my $status = { type => '', name => '', msg => '' };
{
    no warnings qw/redefine prototype/;
    *PVE::Storage::Custom::StorPoolPlugin::syslog = sub {
        $status->{type} = shift;
        $status->{name} = shift;
        $status->{msg}  = shift;
    }
}

PVE::Storage::Custom::StorPoolPlugin::log_info("test");

is_deeply( $status, {type=>'info',name=>'StorPool plugin: %s',msg=>'test'}, 'log_info calls syslog' );

# log_err_and_die
undef $@;
eval {
    PVE::Storage::Custom::StorPoolPlugin::log_and_die("test-die")
}
;
is_deeply( $status, {type=>'err',name=>'StorPool plugin: %s',msg=>'test-die'}, 'log_and_die calls syslog' );
like($@, qr/test-die/, 'log_and_die dies');


