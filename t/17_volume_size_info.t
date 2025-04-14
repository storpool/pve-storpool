#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More tests => 26;
use Scalar::Util qw/tainted/;
use JSON;
use unconstant; # disable constant inlining

use PVE::Storpool qw/mock_confget taint not_tainted mock_sp_cfg mock_lwp_request truncate_http_log slurp_http_log bless_plugin create_block_file/;
use PVE::Storage::Custom::StorPoolPlugin;
# Use different log for every test in order to parallelize them
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-17.txt';


# =head3 $plugin->volume_size_info(\%scfg, $storeid, $volname [, $timeout])
# 
# B<REQUIRED:> Must be implemented in every storage plugin.
# 
# Returns information about the given volume's size. In scalar context, this returns
# just the volume's size in bytes:
# 
#     my $size = $plugin->volume_size_info($scfg, $storeid, $volname, $timeout)
# 
# In list context, returns an array with the following structure:
# 
#     my ($size, $format, $used, $parent, $ctime) = $plugin->volume_size_info(
# 	$scfg, $storeid, $volname, $timeout
#     )
# 
# where C<$size> is the size of the volume in bytes, C<$format> one of the possible
# L<< formats listed in C<plugindata()>|/"$plugin->plugindata()" >>, C<$used> the
# amount of space used in bytes, C<$parent> the (optional) name of the base volume
# and C<$ctime> the creation time as unix timestamp.
# 
# Optionally, a C<$timeout> may be provided after which the method should C<die>.
# This timeout is best passed to other helpers which already support timeouts,
# such as C<L<< PVE::Tools::run_command|PVE::Tools/run_command >>>.
# 
# See also the C<L<< PVE::Storage::Plugin::file_size_info|PVE::Storage::Plugin/file_size_info >>> helper.

# We return the used volume space equal to the volume size because the API calls
# to get the actual used space (e.g. VolumesSpace or VolumesGetStatus) are way
# too slow, and can timeout issues. Caching them across the PVE cluster also
# appears to be a non-trivial amount of work.

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

my $STAGE   = 1;
my $version = '4.3.2';
my $volname = "test-sp-$version.iso";
my $response_reassign = {};
my $http_uri;
my $http_request;
my $http_method;
my @endpoints;

taint($volname);
bless_plugin();

my $expected_reassign_request = [{snapshot=>"~4.3.2", force=>JSON::false,detach=>'all'}];

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

        if( $uri =~ m{/Snapshot/} ) {

            return { code => 200, content => encode_json({generation=>12, 
                data=>[{
                    bw => 123, creationTimestamp=>time(), id=>6411, iops => 10000, globalId => 5, name => 'invalid-volname',
                    size => 6666,
                    tags => {'pve-loc'=>'storpool', 'pve-vm'=>'5', 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}                       
                }]}) 
            }
        }
        if( $uri =~ m{/VolumeDescribe/} ) {

            return { code => 200, content => encode_json({generation=>12, 
                data=>{
                    bw => 123, creationTimestamp=>time(), id=>6411, iops => 10000, globalId => 5, name => 'invalid-volname',
                    size => 6666,
                    tags => {'pve-loc'=>'storpool', 'pve-vm'=>'5', 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}                       
                }}) 
            }
        }

    }
);

truncate_http_log();
my $class = PVE::Storage::Custom::StorPoolPlugin->new();

# Snapshot

undef $@;
@endpoints = ();
my $result = eval { $class->volume_size_info('storeid',{}, 'invalid') };
is($result, undef, 'Invalid volname');
like($@, qr/don't know how to decode/, 'Invalid volname died');
is_deeply(\@endpoints,[], 'Invalid volume no API call');

# Snapshot single size
undef $@;
$STAGE = 2;
@endpoints = ();
$http_method = undef;
$result = $class->volume_size_info('storeid',{}, $volname);
is($result, 6666, "$STAGE: snap size single");
is_deeply(\@endpoints,['Snapshot/~4.3.2'], "$STAGE: snap size single API call");
is(tainted($result), 0, "$STAGE: snap size single not tainted");
is($http_method,'GET', "$STAGE: snap size single API call method");
is($http_request, '', "$STAGE: snap size single API call request empty");

# Snapshot multi size
undef $@;
$STAGE = 3;
@endpoints = ();
$http_method = undef;
my @result = $class->volume_size_info('storeid',{}, $volname);

is(scalar not_tainted(@result), 4, "$STAGE: snap size multi result not tainted");
is_deeply(\@result,[6666,'raw',6666,undef], "$STAGE: snap size multi result");
is_deeply(\@endpoints,['Snapshot/~4.3.2'], "$STAGE: nap size multi API call");
is(tainted($result), 0, "$STAGE: volume size multi not tainted");
is($http_method,'GET', "$STAGE: snap size multi API call method");
is($http_request, '', "$STAGE: snap size multi API call request empty");

# volume single size
$volname = 'vm-11-disk-0-sp-4.1.3.raw';
$STAGE = 4;
@endpoints = ();
$http_method = undef;
$result = $class->volume_size_info('storeid',{}, $volname);
is($result, 6666, "$STAGE: volume size single");
is_deeply(\@endpoints,['VolumeDescribe/~4.1.3'], "$STAGE: volume size single API call");
is(tainted($result), 0, "$STAGE: volume size single not tainted");
is($http_method,'GET', "$STAGE: volume size single API call method");
is($http_request, '', "$STAGE: volume size single API call request empty");

# volume multi size
$STAGE = 5;
@endpoints = ();
$http_method = undef;
@result = $class->volume_size_info('storeid',{}, $volname);

is(scalar not_tainted(@result), 4, "$STAGE: volume size multi result not tainted");
is_deeply(\@result,[6666,'raw',6666,undef], "$STAGE: volume size multi result");
is_deeply(\@endpoints,['VolumeDescribe/~4.1.3'], "$STAGE: nap size multi API call");
is(tainted($result), 0, "$STAGE: volume size multi not tainted");
is($http_method,'GET', "$STAGE: volume size multi API call method");
is($http_request, '', "$STAGE: volume size multi API call request empty");

# Here we must 4 calls to the API
my $http_log = slurp_http_log();

like($http_log, qr{(.*Snapshot/~4.3.2 200.*\n){2}(.*VolumeDescribe/~4.1.3 200.*\n?){2}}, "Total API calls correct");


