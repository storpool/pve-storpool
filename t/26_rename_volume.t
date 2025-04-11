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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-26.txt';


=pod
=head3 $plugin->rename_volume(\%scfg, $storeid, $source_volname, $target_vmid, $target_volname)

B<OPTIONAL:> May be implemented in a storage plugin.

Renames the volume given by C<$source_volname> to C<$target_volname> and assigns
it to the guest C<$target_vmid>. Returns the volume ID of the renamed volume.

This method is needed for the I<Change Owner> feature.

C<die>s if the rename failed.

=cut 

my ( $http_uri, $http_request, $http_method, @endpoints );
my $STAGE = 1;
my $size  = 6666;
my $version = '4.1.3';
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


        my $expected_reassign = [{"detach"=>"all","force"=>JSON::false,"volume"=>"~4.1.3"}];
        push @endpoints, $endpoint;

        if( $uri =~ m{ /VolumeUpdate/~\Q$version\E$ }x ){
			is($method, 'POST', "VolumeUpdate POST");
            is_deeply(decode_json($content), {"tags"=>{"pve-vm"=>JSON::null,"pve-type"=>"iso","pve-comment"=>"test"}}, "VolumeUpdate POST data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }
        if( $uri =~ m{ /Volume/~\Q$version\E }x ){
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

# Result OK
undef $@;
my $result = $class->rename_volume({},'storeid',$volname);

is($result, 'storeid:vm-5-cloudinit.raw', "Snapshot rollback result");
is_deeply(\@endpoints,["VolumeUpdate/~$version","Volume/~$version"], "Correct API calls used");


done_testing();
