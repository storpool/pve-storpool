#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More;
use Scalar::Util qw/tainted/;
use JSON;
use unconstant; # disable constant inlining

use PVE::Storpool qw/mock_confget taint not_tainted mock_sp_cfg mock_lwp_request truncate_http_log slurp_http_log bless_plugin create_block_file/;
use PVE::Storage::Custom::StorPoolPlugin;
# Use different log for every test in order to parallelize them
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-14.txt';


# =head3 $plugin->deactivate_volume($storeid, \%scfg, $volname, $snapname [, \%cache])
# 
# =head3 deactivate_volume(...)
# 
# B<REQUIRED:> Must be implemented in every storage plugin.
# 
# Deactivates a volume or its associated snapshot, making it unavailable to
# the system. For example, this could mean deactivating an LVM volume,
# unmapping a Ceph/RBD device, etc.
# 
# If this isn't needed, the method should simply be a no-op.
# 
# This method may reuse L<< cached information via C<\%cache>|/"CACHING EXPENSIVE OPERATIONS" >>.
# 


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

my $STAGE   = 1;
my $version = '4.3.2';
my $volname = "test-sp-$version.iso";
my $response_reassign = {};
my $http_uri;
my $http_request;
my @endpoints;

taint($volname);
bless_plugin();

my $expected_reassign_request = [{ro=>[666],snapshot=>"~4.3.2"}];
my $response_error = undef;

truncate_http_log();
mock_lwp_request(
    test => sub {
        my $class   = shift;
        my $request = shift;
        my $uri     = $request->uri . "";
        my $content = $request->content;
        my $method  = $request->method;
        my ( $endpoint ) = ( $uri =~ m{/(\w+(?:/~\d.*)?)$} );

        $http_uri       = $uri;
        $http_request   = $content;

        push @endpoints, $endpoint;

        if( $response_error ){
            return { code => 200, content => encode_json({generation=>12, error=>$response_error}) }
        }

        if( $uri =~ /VolumesReassignWait$/ ) {
            my $decoded = decode_json($content);
            is($method,'POST', "$STAGE: VolumesReassignWait POST");
            is_deeply($decoded, $expected_reassign_request, "$STAGE: VolumesReassignWait POST data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        } 
        elsif( $uri =~ m{/(Snapshot|Volume)/~\d+\.\d+\.\d+} ){

            my $expected = {"tags"=>{"pve-loc"=>"storpool","pve-type"=>"iso","pve"=>"storeid","pve-comment"=>"test","pve-snap"=>"4.3.2","pve-snap"=>JSON::true,"virt"=>"pve"}};

            return { code=>200, content => encode_json({generation=>12, data=>[$expected]}) };
        } else {
            fail("Unknown URI $uri");
        }

    }
);

my $return_path;
{
    no warnings qw/redefine prototype once/;
    *PVE::Storage::Custom::StorPoolPlugin::path = sub {
        my $path = PVE::Storage::Plugin::path(@_);

        ok($path,"$STAGE: path returned");

        return $return_path;
    };
}

my $class = PVE::Storage::Custom::StorPoolPlugin->new();

undef $@;
@endpoints = ();
$return_path = '';
my $result = eval { $class->deactivate_volume('storeid',{}, 'invalid') };
is($result, undef, 'Invalid volname');
like($@, qr/don't know how to decode/, 'Invalid volname died');
is_deeply(\@endpoints,[], 'Invalid volume no API call');

undef $@;
$STAGE = 2;
@endpoints = ();
$result = $class->deactivate_volume('storeid',{}, $volname);
is($result, undef, "$STAGE: return on missing volume");
is_deeply(\@endpoints,[], "$STAGE: missing volume no API calls");

undef $@;
$STAGE = 3;
@endpoints = ();
$return_path = '/tmp/block_file';
create_block_file($return_path);
$expected_reassign_request = [{snapshot=>"~4.3.2", force=>JSON::false, detach=>[666]}];

$result = $class->deactivate_volume('storeid',{}, $volname);
unlink $return_path;

SKIP: {
    skip "You must be root to test with creating block file", 2 if $> != 0;
    #is_deeply($result,{generation=>12, data=>{ok=>JSON::true}},"$STAGE: detached");
    is_deeply($result,undef,"$STAGE: detached");
    is_deeply(\@endpoints, ['Snapshot/~4.3.2','VolumesReassignWait'], "$STAGE: API called");
}

# VEEAM
undef $@;
$STAGE = '4 VEEAM';
@endpoints = ();
$return_path = '/tmp/block_file';
create_block_file($return_path);
$expected_reassign_request = [{ro=>[666],snapshot=>"~4.3.2"}];
mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_AUTH_TOKEN=>'token', SP_OURID=>666, _SP_VEEAM_COMPAT => 1 );

$result = $class->deactivate_volume('storeid',{}, $volname);
unlink $return_path;

SKIP: {
    skip "You must be root to test with creating block file", 2 if $> != 0;
    is_deeply($result,{generation=>12, data=>{ok=>JSON::true}},"$STAGE: attached ro");
    is_deeply(\@endpoints, ['Snapshot/~4.3.2','VolumesReassignWait'], "$STAGE: API called");
}

# Error is raised - volume detach is called with ignoreError => 0
undef $@;
$STAGE = '5 VEEAM Error';
@endpoints = ();
$return_path = '/tmp/block_file';
create_block_file($return_path);
$response_error = { descr => 'Error-here' };
mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_AUTH_TOKEN=>'token', SP_OURID=>666, _SP_VEEAM_COMPAT => 1 );

$result = eval { $class->deactivate_volume('storeid',{}, $volname) };
unlink $return_path;

SKIP: {
    skip "You must be root to test with creating block file", 2 if $> != 0;
    like($@, qr/Error-here/, "$STAGE: died");
    is_deeply(\@endpoints, ['Snapshot/~4.3.2'], "$STAGE: API called");

}

done_testing();
