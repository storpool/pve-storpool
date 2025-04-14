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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-24.txt';


=pod
=head3 $plugin->volume_snapshot_delete(\%scfg, $storeid, $volname, $snap [, $running])

Deletes the C<$snap>shot of C<$volname>.

C<die>s in case of errors.

Optionally, the guest that owns the given volume may be C<$running> (= C<1>).

B<Deprecated:> The C<$running> parameter is deprecated and will be removed on the
next C<APIAGE> reset.

=cut

my ( $http_uri, $http_request, $http_method, @endpoints );


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

        if( $uri =~ m{ /SnapshotsList$ }x ){
			is($method, 'GET', "API call GET method");
            return { code => 200, content => encode_json({generation=>12, 
                data=>[
                    {globalId=>11},
                    # sp_is_ours
                    {globalId=>12,tags=>{'pve-snap-v'=>'4.1.3','pve-loc'=>'storpool', 'pve-vm'=>'5',virt=>'pve',pve=>'storeid'} }
                ]
                }) 
            }
        }
        if( $uri =~ m{ /SnapshotDelete/~12 }x ) {

            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }

    }
);


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );
bless_plugin();

my $version = '4.1.3';
my $volname = "test-sp-$version.iso";
my $class 	= PVE::Storage::Custom::StorPoolPlugin->new();
my $cfg 	= PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

# Connection OK
undef $@;
my $result = $class->volume_snapshot_delete({},'storeid',$volname);

is($result, undef, "Snapshot result");
is_deeply(\@endpoints,["SnapshotsList","SnapshotDelete/~12"], "Correct API call used");


done_testing();
