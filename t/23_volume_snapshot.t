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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-23.txt';


=pod
=head3 $plugin->volume_snapshot(\%scfg, $storeid, $volname, $snap)

B<OPTIONAL:> May be implemented if the underlying storage supports snapshots.

Takes a snapshot of a volume and gives it the name provided by C<$snap>.

C<die>s if the underlying storrage doesn't support snapshots or an error
occurs while taking a snapshot.
=cut


my ( $http_uri, $http_request, $http_method, @endpoints );

my $response = { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true,generation=>12,snapshotGlobalId=>11}}) };

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

		my $expected = {"tags"=>{"pve-loc"=>"storpool","pve-type"=>"iso","pve"=>"storeid","pve-comment"=>"test","pve-snap-v"=>"4.3.2","pve-snap"=>JSON::null,"virt"=>"pve"}};
        push @endpoints, $endpoint;

        if( $uri =~ m{ VolumeSnapshot/~4\.3\.2 }x ){
			is($method, 'POST', "API call POST method");
			is_deeply(decode_json($content), $expected, "API call POST data");
            return $response;
        }
        elsif( $uri =~ m{/(Snapshot|Volume)/~\d+\.\d+\.\d+} ){

            my $expected = {"tags"=>{"pve-loc"=>"storpool","pve-type"=>"iso","pve"=>"storeid","pve-comment"=>"test","pve-snap"=>"4.3.2","pve-snap"=>JSON::true,"virt"=>"pve"}};

            return { code=>200, content => encode_json({generation=>12, data=>[$expected]}) };
        }

    }
);


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );
bless_plugin();

my $version = '4.3.2';
my $volname = "test-sp-$version.iso";
my $class 	= PVE::Storage::Custom::StorPoolPlugin->new();
my $cfg 	= PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

# Connection OK
undef $@;
my $result = $class->volume_snapshot({},'storeid',$volname);

is($result, undef, "Snapshot result");
is_deeply(\@endpoints,['Snapshot/~4.3.2',"VolumeSnapshot/~$version"], "Correct API call used");


## Error from the API
undef $@;
@endpoints = ();
$response->{content} = encode_json({error=>{descr=>'Main error'}});
$result = eval { $class->volume_snapshot({},'storeid',$volname) };

is($result,undef,"error result");
like($@, qr/Main error/, "API error displayed");
is_deeply(\@endpoints,['Snapshot/~4.3.2',"VolumeSnapshot/~$version"], "Correct API call used");


done_testing();
