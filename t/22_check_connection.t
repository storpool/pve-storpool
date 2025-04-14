#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More;
use Scalar::Util qw/tainted/;
use JSON;
use unconstant; # disable constant inlining

use PVE::Storpool qw/mock_confget taint not_tainted mock_sp_cfg mock_lwp_request truncate_http_log slurp_http_log bless_plugin/;
use PVE::Storage::Custom::StorPoolPlugin;
# Use different log for every test in order to parallelize them
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-22.txt';



# B<OPTIONAL:> May be implemented in a storage plugin.
# 
# Performs a connection check.
# 
# This method is useful for plugins that require some kind of network connection
# or similar and is called before C<L<< activate_storage()|/"$plugin->activate_storage($storeid, \%scfg, \%cache)" >>>.
# 
# This method can be implemented by network-based storages. It will be
# called before storage activation attempts. Non-network storages should
# not implement it.

my ( $http_uri, $http_request, $http_method, @endpoints );

my $response = { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) };

truncate_http_log();
mock_lwp_request(
    test => sub {
        my $class   = shift;
        my $request = shift;
        my $uri     = $request->uri . "";
        my $content = $request->content;
        my $method  = $request->method;
        my ( $endpoint ) = ( $uri =~ m{/(\w+(?:/~\d+(?:\.\d\.\d)?)?)$} );

        # Set for later use in the tests
        $http_uri       = $uri;
        $http_request   = $content;
        $http_method    = $method;

        push @endpoints, $endpoint;

        if( $uri =~ m{ ServicesList }x ){
            return $response;
        }

    }
);


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );
bless_plugin();

my $class = PVE::Storage::Custom::StorPoolPlugin->new();
my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

# Connection OK
undef $@;
my $result = $class->check_connection('storeid',{});

is(!!$result,1, "Check connection running");
is_deeply(\@endpoints,['ServicesList'], "API call ServicesList");

# 404
undef $@;
$response->{code} = 404;
$result = eval { $class->check_connection('storeid',{}) };

is(!!$result,'', "404 from API");
like($@, qr/Could not fetch/, "404 died");

# missing response
undef $@;
$response->{code} = 200;
$response->{content} = "";

$result = eval { $class->check_connection('storeid',{}) };
my $error = $@;
is(!!$result,'', "missing response from API");
like($error, qr/malformed JSON string/, "missing response died");

TODO: {
    local $TODO = "Missing response must die with more appropriate error";
    note "TODO fix error on missing response";
    like($error, qr/Failed to fetch data/, "Correct message");
}

done_testing();
