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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-20.txt';


=pod 
=head3 $plugin->create_base($storeid, \%scfg, $volname)

B<OPTIONAL:> May be implemented in a storage plugin.

Creates a base volume from an existing volume, allowing the volume to be
L<< cloned|/"$plugin->clone_image(...)" >>. This cloned volume (usually
a disk image) may then be used as a base for the purpose of creating linked
clones. See L<C<PVE::Storage::LvmThinPlugin>> and
L<C<PVE::Storage::ZFSPoolPlugin>> for example implementations.

On completion, returns the name of the new base volume (the new C<$volname>).

This method is called in the context of C<L<< cluster_lock_storage()|/"cluster_lock_storage(...)" >>>,
i.e. when the storage is B<locked>.

=cut

my ( $http_uri, $http_request, $http_method, @endpoints );

my $STAGE   = 1; # Used to follow the mocked method tests
my $expected_vsnap_request = { 
    'tags' => {
          'pve-vm' => '5',
          'pve-loc' => 'storpool',
          'pve-base' => '1',
          'virt' => 'pve',
          'pve-type' => 'images',
          'pve-disk' => 'cloudinit'
    }
};
my $expected_reassign = [{"volume"=>"~4.1.3","detach"=>"all","force"=>JSON::false}];

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


        if( $uri =~ m{ /Snapshot/~(4\.1\.3|11) }x ){

			is($method, 'GET', "$STAGE: Snapshot GET");
            is($content,'',"$STAGE: Snapshot called withoud arguments");
            return { code => 200, content => encode_json({generation=>12, 
                data=>[{
                    bw => 123, creationTimestamp=>time(), id=>6411, iops => 10000, globalId => 5, name => '~4.1.3', # Named are invalid for this test, keep for reference
                    size => 6666,
                    tags => {'pve-loc'=>'storpool', 'pve-vm'=>'5', 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}                       
                }]}) 
            }
        }

		if( $uri =~ m{ /VolumeSnapshot/~4\.1\.3 }x ){
			is($method, 'POST', "$STAGE: VolumeSnapshot POST");
			is_deeply(decode_json($content), $expected_vsnap_request, "$STAGE: VolumeSnapshot request data");
			return { code => 200, content => encode_json({generation=>12,
				data => {generation=>12, ok=>JSON::true, snapshotGlobalId=>11}
			})}
		}

        if( $uri =~ m{ /VolumesReassignWait$ }x ){
			is($method, 'POST', "$STAGE: VolumesReassignWait POST");
            is_deeply(decode_json($content), $expected_reassign, "$STAGE: VolumesReassignWait POST data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }

        if( $uri =~ m{ /VolumeDelete/~4.1.3 }x ){

			is($method, 'POST', "$STAGE: VolumeDelete POST");
            is($content,'{}', "$STAGE: VolumeDelete POST empty data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }
    }
);


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

bless_plugin();

my $class = PVE::Storage::Custom::StorPoolPlugin->new();

my $version = '4.3.2';
my $volname = "test-sp-$version.iso";

# Non image volume
undef $@;
my $result = eval { $class->create_base('storeid',{}, $volname) };

is($result,undef,"$STAGE: undef on error");
like($@, qr/not possible with types other than images/, "$STAGE: invalid volume");
is_deeply(\@endpoints, [], "$STAGE: no API calls");

# Base disk - invalid
$STAGE 	  = 2;
$volname  = "base-11-disk-0-sp-$version.raw";

$result = eval { $class->create_base('storeid',{},$volname) };
is($result,undef,"$STAGE: undef on error");
like($@, qr/create_base not possible with base image/, "$STAGE: invalid volume");
is_deeply(\@endpoints, [], "$STAGE: no API calls");


# Valid image
$STAGE 	 = 3;
$volname = "img-comment-sp-4.1.3.raw";
@endpoints = ();

$result = $class->create_base('storeid',{},$volname);

is($result, "vm-5-cloudinit.raw", "$STAGE: correct new base volume");
is_deeply(\@endpoints,["Snapshot/~4.1.3", "VolumeSnapshot/~4.1.3", "Snapshot/~11", "VolumesReassignWait", "VolumeDelete/~4.1.3"], "$STAGE: correct API calls");

done_testing();
