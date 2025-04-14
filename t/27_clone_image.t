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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-27.txt';


=pod
=head3 $plugin->clone_image($scfg, $storeid, $volname, $vmid [, $snap])

=head3 $plugin->clone_image(...)

B<REQUIRED:> Must be implemented in every storage plugin.

Clones a disk image or a snapshot of an image, returning the name of the new
image (the new C<$volname>). Note that I<cloning> here means to create a linked
clone and not duplicating an image. See L<C<PVE::Storage::LvmThinPlugin>> and
L<C<PVE::Storage::ZFSPoolPlugin>> for example implementations.

C<die>s in case of an error of if the underlying storage doesn't support
cloning images.

This method is called in the context of C<L<< cluster_lock_storage()|/"cluster_lock_storage(...)" >>>,
i.e. when the storage is B<locked>.

=cut


my ( $http_uri, $http_request, $http_method, @endpoints );
my $STAGE = 1;
my $version = '4.3.2';
my $expected_request = { # {"tags":{"pve-type":"images","pve-disk":"cloudinit","virt":"pve","pve-loc":"storpool","pve-vm":"vmid","pve-base":"0"},"parent":"~4.3.2"}
    parent => "~$version",
    tags=>{'pve-loc' => 'storpool', 'pve-type'=>'images',virt=>'pve','pve-disk'=>'cloudinit','pve-vm'=>'vmid','pve-base'=>0 }
};
my $response_data = {
    generation => 12,
    data => {
        generation => 12, ok => JSON::true,
        bw=>123,globalId=>5, creationTimestamp => time(),
    }
};
my $response_vol_info = {
    generation => 12,
    data => [{
        bw => 123, creationTimestamp=>time(), id=>6411, iops => 10000, globalId => 5, name => '~4.1.3',
        tags => {'pve-loc'=>'storpool', 'pve-vm'=>'5', 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}
    }]
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


        push @endpoints, $endpoint;

        if( $uri =~ m{ /Snapshot/~$version }x ) {

			is($method, 'GET', "$STAGE: API call POST method");
            return { code => 200, content => encode_json({generation=>12, 
                data=>[{
                    bw => 123, creationTimestamp=>time(), id=>6411, iops => 10000, globalId => 5, name => 'invalid-volname',
                    size => 6666,
                    tags => {'pve-loc'=>'storpool', 'pve-vm'=>'5', 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}                       
                }]}) 
            }
        }
        if( $uri =~ /VolumeCreate$/ ) { # sp_vol_create
            my $decoded = decode_json($content);

            is_deeply( $decoded, $expected_request, "$STAGE: VolumeCreate tags passed" );
            is($method,'POST',"$STAGE: VolumeCreate POST");
            return { code => 200, content => encode_json( $response_data ) }
        }
        if( $uri =~ m{ /Volume/ }x ){
			is($method, 'GET', "Volume/~... method GET");

            return { code => 200, content => encode_json( $response_vol_info ) }
        }
    }
);


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );
bless_plugin();


my $volname = "test-sp-$version.iso";
my $class 	= PVE::Storage::Custom::StorPoolPlugin->new();
my $cfg 	= PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);



# Non image volume
undef $@;
@endpoints = ();
my $result = eval { $class->clone_image({}, 'storeid', $volname, 'vmid') };

is($result,undef,"$STAGE: not an iso");
like($@, qr/clone_image on wrong vtype/, "$STAGE: not an iso died");
is_deeply(\@endpoints,[], "$STAGE: not an iso no API calls");

undef $@;
@endpoints = ();
$STAGE = 2;
$volname = "img-test-sp-$version.raw";
$result = $class->clone_image({}, 'storeid', $volname, 'vmid');

is($result,'vm-5-cloudinit.raw', "$STAGE: result OK");
is_deeply(\@endpoints,["Snapshot/~$version","VolumeCreate","Volume/~5"], "$STAGE: API calls OK");

undef $@;
@endpoints = ();
$STAGE = 3;
$volname = "snap-55-disk-0-proxmox-p-1.2.3-sp-$version.raw";
$result = $class->clone_image({}, 'storeid', $volname, 'vmid');

is($result,'vm-5-cloudinit.raw', "$STAGE: result OK");
is_deeply(\@endpoints,["Snapshot/~$version","VolumeCreate","Volume/~5"], "$STAGE: API calls OK");


undef $@;
@endpoints = ();
$STAGE = 4;
$volname = "snap-1-state-proxmox-sp-$version.raw";
$expected_request->{baseOn} = $expected_request->{parent};
delete $expected_request->{parent};
$result = $class->clone_image({}, 'storeid', $volname, 'vmid');

is($result,'vm-5-cloudinit.raw', "$STAGE: result OK");
is_deeply(\@endpoints,["Volume/~$version","VolumeCreate","Volume/~5"], "$STAGE: API calls OK");


undef $@;
@endpoints = ();
$STAGE = 5;
$volname = "base-11-disk-0-sp-$version.raw";
$expected_request->{parent} = $expected_request->{baseOn};
delete $expected_request->{baseOn};
$result = $class->clone_image({}, 'storeid', $volname, 'vmid');

is($result,'vm-5-cloudinit.raw', "$STAGE: result OK");
is_deeply(\@endpoints,["Snapshot/~$version","VolumeCreate","Volume/~5"], "$STAGE: API calls OK");


undef $@;
@endpoints = ();
$STAGE = 6;
$volname = "vm-11-disk-0-sp-$version.raw";
$expected_request->{baseOn} = $expected_request->{parent};
delete $expected_request->{parent};
$result = $class->clone_image({}, 'storeid', $volname, 'vmid');

is($result,'vm-5-cloudinit.raw', "$STAGE: result OK");
is_deeply(\@endpoints,["Volume/~$version","VolumeCreate","Volume/~5"], "$STAGE: API calls OK");


undef $@;
@endpoints = ();
$STAGE = 7;
$volname = "vm-5-cloudinit-sp-$version.raw";
$result = $class->clone_image({}, 'storeid', $volname, 'vmid');

is($result,'vm-5-cloudinit.raw', "$STAGE: result OK");
is_deeply(\@endpoints,["Volume/~$version","VolumeCreate","Volume/~5"], "$STAGE: API calls OK");


done_testing();
