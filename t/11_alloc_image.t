#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;
use unconstant; # disable constant inlining
use JSON;
use Scalar::Util qw/tainted/;

use PVE::Storage::Custom::StorPoolPlugin;
use PVE::Storpool qw/mock_confget truncate_http_log slurp_http_log mock_lwp_request/;
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-11.txt';


# =head3 $plugin->alloc_image($storeid, $scfg, $vmid, $fmt, $name, $size)
#
# B<REQUIRED:> Must be implemented in every storage plugin.
#
# Allocates a disk image with the given format C<$fmt> and C<$size> in bytes,
# returning the name of the new image (the new C<$volname>). See
# C<L<< plugindata()|/"$plugin->plugindata()" >>> for all disk formats.
#
# Optionally, if given, set the name of the image to C<$name>. If C<$name> isn't
# provided, the next name should be determined via C<L<< find_free_diskname()|/"$plugin->find_free_diskname(...)" >>>.
#
# C<die>s in case of an error of if the underlying storage doesn't support
# allocating images.
#
# This method is called in the context of C<L<< cluster_lock_storage()|/"cluster_lock_storage(...)" >>>,
# i.e. when the storage is B<locked>.
#

( $ENV{PATH} ) = ( $ENV{PATH} =~ /^(.*)$/ );

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

undef $@;

my $result = eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, 'vmid', 'raw2', 'name', 1024) };

like($@, qr/unsupported format.*raw2/, 'dies on unsupported format');

my ($http_uri, $http_request);
my $STAGE = ''; # Used to follow inner LWP mock tests
my @endpoints;
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
        bw => 123, creationTimestamp=>time(), id=>6411, iops => 10000, globalId => 5, name => 'invalid-volname',
        tags => {'pve-loc'=>'storpool', 'pve-vm'=>'5', 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}
    }]
};
my $expected_request = { template => 666, size => 1024 * 1024,
    tags=>{pve=>666, 'pve-loc' => 'storpool', 'pve-type'=>'images',virt=>'pve' }
};

truncate_http_log();
mock_lwp_request( # Every HTTP call lands here
    test => sub {
        my $class   = shift;
        my $request = shift;
        my $uri     = $request->uri . "";
        my $content = $request->content;
        my $method  = $request->method;

        $http_uri = $uri;
        $http_request = $content;

        my ( $endpoint ) = ( $uri =~ m{/(\w+(?:/~\d)?)$} );

        push @endpoints, $endpoint;

        if( $uri =~ /VolumesAndSnapshotsList$/ ){

            is($content,'',"$STAGE: VolumesAndSnapshotsList called withoud arguments");
            return { code => 200, content => encode_json({generation=>12,
                    data=>{ok=>JSON::true,
                        volumes=>[ { tags=>{'pve-disk'=>123, virt=>'pve','pve-loc'=>'storpool','pve-vm'=>11} } ]
                        }
                })
            };
        }

        if( $uri =~ /VolumesReassignWait$/ ) {
            my $decoded = decode_json($content);
            is_deeply($decoded, [{"force"=>JSON::true,"volume"=>"~5","rw"=>[666],"detach"=>"all"}], "$STAGE: volume reassign");
            is($method,'POST',"$STAGE: volume reassign POST");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) };
        }
        if( $uri =~ /VolumeCreate$/ ) { # sp_vol_create
            my $decoded = decode_json($content);

            is_deeply( $decoded, $expected_request, "$STAGE: VolumeCreate tags passed" );
            is($method,'POST',"$STAGE: VolumeCreate POST");
            return { code => 200, content => encode_json( $response_data ) }
        }
        if( $uri =~ m{Volume/~5$} ) { # sp_vol_info_single
            is( $content, '', "$STAGE: vol_info request empty" );
            is($method,'GET',"$STAGE: Volume/~5 GET");
            return { code => 200, content => encode_json( $response_vol_info ) }
        }
    }
);




# No extra tags not returning array
$response_vol_info->{data} = { %{ $response_vol_info->{data}->[0] } }; # Clone the data and put it into Hash
$STAGE = '1';
undef $@;
$result = eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, undef, 'raw', 'name', 1024) };
like($@, qr/expected exactly one volume/, "$STAGE: Bad response, data not array");

is( scalar(@endpoints), 2, "$STAGE: two endpoints called" );
like(join("--",@endpoints), qr{VolumeCreate--Volume/~5}, "$STAGE: correct API calls used") or diag explain \@endpoints;

$response_vol_info->{data} = [{ %{$response_vol_info->{data}} }]; # Restore the correct structure

# No extra tags invalid volume name
# API Workflow is volume create, vol info, volume reassign ( vol_attach )
$STAGE = '2';
undef $@;
@endpoints = ();
$result =  eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, undef, 'raw', 'name', 1024) };
like($@, qr/Only unnamed StorPool volumes supported/, "$STAGE: Invalid volume name");
like(join("--",@endpoints), qr{^ VolumeCreate--Volume/~5 $}x, "$STAGE: correct API calls used") or diag explain \@endpoints;



# No extra tags empty volume name
$STAGE = '3';
@endpoints = ();
$response_vol_info->{data}->[0]->{name} = '~4.1.3';

$result =  PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, undef, 'raw', 'kakak', 1024);
is($result, 'vm-5-cloudinit.raw', "$STAGE: alloc_image returns the correct name");
like(join("--",@endpoints), qr{^ VolumeCreate--Volume/~5 $}x, "$STAGE: correct API calls used") or diag explain \@endpoints;



# cloudinit name
$STAGE = '4';
@endpoints = ();
$expected_request->{tags}->{'pve-vm'}   = '';
$expected_request->{tags}->{'pve-disk'} = 'cloudinit'; # In the request we get that it's a cloudinit type disk
$result =  PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, "", 'raw', 'vm-6-cloudinit', 1024);
is($result, 'vm-5-cloudinit.raw', "$STAGE: alloc_image returns the correct name");
like(join("--",@endpoints), qr{^ VolumeCreate--Volume/~5 $}x, "$STAGE: correct API calls used") or diag explain \@endpoints;

# VM snapshot state inconsistent name
$STAGE = '5';
@endpoints = ();
undef $@;
$result =  eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, '', 'raw', 'vm-11-state-proxmox.raw', 1024) };
like($@, qr/Inconsistent VM snapshot state name/, "$STAGE: inconsistent name error");
is(scalar(@endpoints),0, "$STAGE: no API calls");

# VM snapshot state
$STAGE = '6';
@endpoints = ();
$expected_request->{tags}->{'pve-vm'} = '11';
$expected_request->{tags}->{'pve-disk'} = 'state';
$expected_request->{tags}->{'pve-snap'} = 'proxmox.raw';
$result = PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, '11', 'raw', 'vm-11-state-proxmox.raw', 1024);
is($result, 'vm-5-cloudinit.raw', "$STAGE: alloc_image returns the correct name");
like(join("--",@endpoints), qr{^ VolumeCreate--Volume/~5 $}x, "$STAGE: correct API calls used") or diag explain \@endpoints;

# Find free disk by vmid
$STAGE = '7';
@endpoints = ();
$expected_request->{tags}->{'pve-disk'} = '124';
delete $expected_request->{tags}->{'pve-snap'};

$result = PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, '11', 'raw', undef, 1024);
is($result, 'vm-5-cloudinit.raw', "$STAGE: alloc_image returns the correct name");
like(
    join("--",@endpoints),
    qr{^ VolumesAndSnapshotsList--VolumeCreate--Volume/~5 $}x,
    "$STAGE: correct API calls used"
) or diag explain \@endpoints;
# TODO untaint

TODO: {
    note "Fix the tainted data";
    local $TODO = "$STAGE tainted data";
    is(tainted($result), 0, "$STAGE: Data not tainted") or diag "Tainted";
}



### VEEAM

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token', _SP_VEEAM_COMPAT => 1 );
$STAGE = '8 VEEAM';
@endpoints = ();
$expected_request->{tags}->{'pve-snap'} = 'proxmox.raw';
$expected_request->{tags}->{'pve-disk'} = 'state'; # In the request we get that it's a cloudinit type disk
$result =  PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, "11", 'raw', 'vm-11-state-proxmox.raw', 1024);
is($result, 'vm-5-cloudinit.raw', "$STAGE: alloc_image returns the correct name");
like(join("--",@endpoints), qr{^ VolumeCreate--Volume/~5--VolumesReassignWait $}x, "$STAGE: correct API calls used") or diag explain \@endpoints;

delete $expected_request->{tags}->{'pve-snap'};
$expected_request->{tags}->{'pve-disk'} = '124'; # In the request we get that it's a cloudinit type disk

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token', _SP_VEEAM_COMPAT => 0 );


### Missing API responses
# Missing volume info
$STAGE = '9';
@endpoints = ();
undef $@;
$response_vol_info->{data_orig} = $response_vol_info->{data};
$response_vol_info->{data} = [];
$result = eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, '11', 'raw', undef, 1024) };
is($result, undef, "$STAGE: alloc_image returns the correct name");
like($@, qr/expected exactly one volume/, "$STAGE: missing volume info");
like(
    join("--",@endpoints),
    qr{^ VolumesAndSnapshotsList--VolumeCreate--Volume/~5 $}x,
    "$STAGE: correct API calls used"
) or diag explain \@endpoints;

# Missing create volume response
$STAGE = '10';
@endpoints = ();
undef $@;
$response_vol_info->{data} = $response_vol_info->{data_orig};
$response_data->{data} = {};
$result = eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, '11', 'raw', undef, 1024) };
is($result, undef, "$STAGE: alloc_image returns the correct name");
like($@, qr/no globalId in the VolumeCreate API/, "$STAGE: missing volume info");
like(join("--",@endpoints), qr{^ VolumesAndSnapshotsList--VolumeCreate $}x, "$STAGE: correct API calls used") or diag explain \@endpoints;


done_testing();


