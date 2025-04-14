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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-25.txt';


=pod
 
=head3 $plugin->volume_snapshot_rollback(\%scfg, $storeid, $volname, $snap)

Performs a rollback to the given C<$snap>shot on C<$volname>.

C<die>s in case of errors.

=cut

my ( $http_uri, $http_request, $http_method, @endpoints );

my $snapshots_list = { 
    code => 200, 
    content => encode_json({generation=>12, 
        data=>[
            {globalId=>11},
            # sp_is_ours
            {globalId=>12,tags=>{'pve-snap-v'=>'4.1.3','pve-loc'=>'storpool', 'pve-vm'=>'5',virt=>'pve',pve=>'storeid'} }
        ]
    }) 
};

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

        my $expected_reassign = [{"detach"=>"all","force"=>JSON::false,"volume"=>"~4.1.3"}];
        push @endpoints, $endpoint;

        if( $uri =~ m{ /VolumeRevert/~4\.1\.3 }x ){
            is($method,'POST', "VolumeRevert POST method");
            is_deeply(decode_json($content),{"revertSize"=>JSON::true,"toSnapshot"=>"~12"}, "VolumeRevert POST data ok");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }
        if( $uri =~ m{ /VolumesReassignWait }x ){

			is($method, 'POST', "VolumesReassignWait POST");
            is_deeply(decode_json($content), $expected_reassign, "VolumesReassignWait POST data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }
        if( $uri =~ m{ /SnapshotsList$ }x ){
			is($method, 'GET', "SnapshotsList API call GET method");
            is($content,'', "SnapshotsList no content request");
            return $snapshots_list;
        }
        if( $uri =~ m{ /SnapshotDelete/~12 }x ) {

			is($method, 'GET', "SnapshotDelete API call GET method");
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

# Result OK
undef $@;
my $result = $class->volume_snapshot_rollback({},'storeid',$volname);

is($result, undef, "Snapshot rollback result");
is_deeply(\@endpoints,["SnapshotsList","VolumesReassignWait","VolumeRevert/~4.1.3"], "Correct API calls used");

# Multiple snapshots
$snapshots_list->{content} = encode_json({generation=>12, 
        data=>[
            # sp_is_ours
            {globalId=>12,tags=>{'pve-snap-v'=>'4.1.3','pve-loc'=>'storpool', 'pve-vm'=>'5',virt=>'pve',pve=>'storeid'} },
            {globalId=>12,tags=>{'pve-snap-v'=>'4.1.3','pve-loc'=>'storpool', 'pve-vm'=>'5',virt=>'pve',pve=>'storeid'} }
        ]
}); 

undef $@;
$result = eval { $class->volume_snapshot_rollback({},'storeid',$volname,'snap') };
like($@, qr/expected exactly one 'snap' snapshot/, "Multiple snaps found error died");

done_testing();
