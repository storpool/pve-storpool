#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;
use LWP::UserAgent;
use Data::Dumper;

use PVE::Storage::Custom::StorPoolPlugin;
use PVE::Storpool qw/mock_sp_cfg mock_lwp_request/;

my $ver = \%{PVE::Storage::Custom::StorPoolPlugin::};

sub make_http_request {
    my $params = { @_ };
    my $method = $params->{method}  || 'GET';
    my $path   = $params->{path}    || die "Missing path";
    my $request= $params->{request};

    mock_sp_cfg();
    PVE::Storage::Custom::StorPoolPlugin::sp_request(
        PVE::Storage::Custom::StorPoolPlugin::sp_cfg(1,2),
        $method,
        $path,
        $request
    );
}

mock_lwp_request( data => 1, test => sub {
    my $class = shift;
    say "Got into class $class";
    say Dumper $class;
});

make_http_request( path => 'test-pat', request => { vars => 123 } );


done_testing();
