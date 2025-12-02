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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-15.txt';


# $plugin->free_image($class, $storeid, $scfg, $volname, $isBase, $format)
# deletes a snapshot
# on volume it traverses it's parent snapshots and deletes them


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

        $http_uri       = $uri;
        $http_request   = $content;

        push @endpoints, $endpoint;

        if( $uri =~ /VolumesReassignWait$/ ) {
            my $decoded = decode_json($content);
            is($method,'POST', "$STAGE: VolumesReassignWait POST");
            is_deeply($decoded, $expected_reassign_request, "$STAGE: VolumesReassignWait POST data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }
        if( $uri =~ /SnapshotDelete/ ) {

            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }
        if( $uri =~ /VolumeDelete/ ) {

            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }
        if( $uri =~ /SnapshotsList/ ) {

            return { code => 200, content => encode_json({generation=>12, 
                data=>[
                    {globalId=>11},
                    # sp_is_ours
                    {globalId=>12,tags=>{'pve-snap-v'=>'4.1.3','pve-loc'=>'storpool', 'pve-vm'=>'5',virt=>'pve',pve=>'storeid'} }
                ]
                }) 
            }
        }
        elsif( $uri =~ m{/(Snapshot|Volume)/~\d+\.\d+\.\d+} ){

            my $expected = {"tags"=>{"pve-loc"=>"storpool","pve-type"=>"iso","pve"=>"storeid","pve-comment"=>"test","pve-snap"=>"4.3.2","pve-snap"=>JSON::true,"virt"=>"pve"}};

            return { code=>200, content => encode_json({generation=>12, data=>[$expected]}) };
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
my $result = eval { $class->free_image('storeid',{}, 'invalid') };
is($result, undef, 'Invalid volname');
like($@, qr/don't know how to decode/, 'Invalid volname died');
is_deeply(\@endpoints,[], 'Invalid volume no API call');

undef $@;
$STAGE = 2;
@endpoints = ();
$result = $class->free_image('storeid',{}, $volname);
is($result, undef, "$STAGE: snapshot delete");
is_deeply(\@endpoints,['Snapshot/~4.3.2','VolumesReassignWait','SnapshotDelete/~4.3.2'], "$STAGE: snapshot delete API call");

undef $@;
$STAGE = 3;
@endpoints = ();
$volname = "vm-11-disk-0-sp-4.1.3.raw";
$expected_reassign_request = [{volume=>"~4.1.3", force=>JSON::false,detach=>'all'}];
$result = $class->free_image('storeid',{}, $volname);

is($result, undef, "$STAGE: cleanup parent snapshots result OK");
is_deeply(\@endpoints,['Volume/~4.1.3','VolumesReassignWait','VolumeDelete/~4.1.3','SnapshotsList','SnapshotDelete/~12'], "$STAGE: API calls OK");

done_testing();
