#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;
use LWP::UserAgent;
use unconstant; # disable constant inlining
use JSON;

use PVE::Storage::Custom::StorPoolPlugin;
use PVE::Storpool qw/mock_sp_cfg mock_lwp_request truncate_http_log slurp_http_log make_http_request/;

# Use different log for every test in order to parallelize them
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-06.txt';
use constant *PVE::Storage::Custom::StorPoolPlugin::HTTP_RETRY_TIME => 0;

my $plugin = \%{PVE::Storage::Custom::StorPoolPlugin::};


## Timeout and Headers
mock_lwp_request( 
    #data => { code => 200, content => '{}', msg => 'GET' }, # Not required in 
    test => sub { # Inject the LWP::UserAgent object
        my $class = shift;
        my $request = shift;
        my $token = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(1,2)->{api}->{auth_token};
        BAIL_OUT("Missing API auth_token from sp_cfg") if !$token;

        my $headers = $request->as_string =~ /Authorization: Storpool v1:$token/ ? 'header' : 'header missing';
        my $uri     = $request->uri . "";
        my $content = $request->content;

        is($class->timeout, PVE::Storage::Custom::StorPoolPlugin::HTTP_TIMEOUT, 'Timeout correct');

        return { code => 200, content => encode_json([$headers]) }
    }
);


my $result  = make_http_request( path => 'test-path', request => { vars => 123 } );

is_deeply( $result, ['header'], 'Header set' );
my $cfg = { api =>{auth_token=>'',url=>''} }; 
my $count = 0;
my $retries = PVE::Storage::Custom::StorPoolPlugin::HTTP_RETRY_COUNT + 1;
undef $@;
# Retry GET
mock_lwp_request( test => sub {
        $count++;
        return { code=>500, content=>'{}',header=>['client-warning','Internal response'] }
    }
);
$result = eval { PVE::Storage::Custom::StorPoolPlugin::sp_get($cfg,'/test') };

is($result, undef, 'Timeout GET result OK');
is($count, $retries, 'Timeout GET retries OK');
like($@, qr/Timeout connection/, 'Timeout GET dies');

# Retry POST
$count = 0;
$result = eval { PVE::Storage::Custom::StorPoolPlugin::sp_post($cfg,'/test',{}) };

is($result, undef, 'Timeout POST result OK');
is($count, $retries, 'Timeout POST retries OK');
like($@, qr/Timeout connection/, 'Timeout POST dies');

## Log HTTP response

mock_lwp_request( data => { code => 200, content => encode_json(['We got the response']) } );
truncate_http_log();

make_http_request( path => 'test-path', request => { vars => 123 } );
my $gmtime  = gmtime() . "";
my $log     = slurp_http_log();

like( $log, qr/$gmtime/, 'GM time in the line' );
like( $log, qr/We got the response/, 'Response here' );
like( $log, qr/test\-path/, 'Path present' );
like( $log, qr/\b200\b/, 'Response code' );

## Path

mock_lwp_request( test => sub { 
    my $class=shift; 
    my $uri = shift->uri."";
    my $url = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(1,2)->{api}->{url};

    BAIL_OUT("Missing API uri from sp_cfg") if !$url;
    { code => 200, content => encode_json([ $uri eq ($url . 'test-path')]) }
});

my $response = make_http_request( path => 'test-path' );

is( $response->[0], '1', 'Path correct' );

## JSON parameters
mock_lwp_request( test => sub {
    my $class = shift;
    my $content = shift->content;
    
    { code => 200, content => $content }
});

my $params = { vars => 666, testing_here => 'test111' };
$response = make_http_request( path => 'test-path', request => $params );

is_deeply( $response, $params, 'Request JSON parameters' );

# Missing path
$response = eval { make_http_request( request => $params ) };

like( $@, qr/Missing path/, 'Missing path' );

# Missing JSON params
$response = eval { make_http_request( path => 'here-path' ) };

is($response, undef, 'Missing params');
#like( $@, qr/malformed JSON string/, 'Missing params' );

# Error 404 with error
mock_lwp_request( data => { code => 404, content => encode_json({error=>'missing page'}) } );

truncate_http_log();
$response = make_http_request( path => 'path', request => $params );
$log = slurp_http_log();

like( $log, qr/\b404\b/, '404 code log' );
like( $log, qr/missing page/, '404 error' );
is_deeply( $response, {error=>'missing page'}, '404 response' );

# Error 404 without error but content

mock_lwp_request( data => { code => 404, content => encode_json({errors=>'missing page'}) } );
$response = make_http_request( path => 'path', request => $params );

is_deeply( $response, {error=>{descr=>'Error code: 404',code=>404,reason=>''}}, '404 generic error' );

truncate_http_log();

### sp_request is working so test sp_get and sp_post

{
    no warnings qw/redefine prototype/;
    *PVE::Storage::Custom::StorPoolPlugin::sp_request = sub {
        return \@_;
    }
};

my $send_params = { vars => 666, testing_here => 'test111' };

# sp_get
is_deeply(
    PVE::Storage::Custom::StorPoolPlugin::sp_get( $cfg, 'addr' ),
    [$cfg, 'GET', 'addr', undef ],
    'sp_get response'
);

# sp_post
is_deeply(
    PVE::Storage::Custom::StorPoolPlugin::sp_post( $cfg, 'addr', $send_params ),
    [$cfg, 'POST', 'addr', $send_params ],
    'sp_post response'
);


done_testing();
