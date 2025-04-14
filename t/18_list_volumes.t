#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More tests => 10;
use Scalar::Util qw/tainted/;
use JSON;
use unconstant; # disable constant inlining

use PVE::Storpool qw/mock_confget taint not_tainted mock_sp_cfg mock_lwp_request truncate_http_log slurp_http_log bless_plugin/;
use PVE::Storage::Custom::StorPoolPlugin;
# Use different log for every test in order to parallelize them
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-18.txt';


# =head3 $plugin->list_volumes($storeid, \%scfg, $vmid, \@content_types)
# 
# B<REQUIRED:> Must be implemented in every storage plugin.
# 
# Returns a list of volumes for the given guest whose content type is within the
# given C<\@content_types>. If C<\@content_types> is empty, no volumes will be
# returned. See C<L<< plugindata()|/"$plugin->plugindata()" >>> for all content types.
# 
#     # List all backups for a guest
#     my $backups = $plugin->list_volumes($storeid, $scfg, $vmid, ['backup']);
# 
#     # List all containers and virtual machines on the storage
#     my $guests = $plugin->list_volumes($storeid, $scfg, undef, ['rootdir', 'images'])
# 
# The returned listref of hashrefs has the following structure:
# 
#     [
# 	{
# 	    content => "images",
# 	    ctime => "1702298038", # creation time as unix timestamp
# 	    format => "raw",
# 	    size => 9663676416, # in bytes!
# 	    vmid => 102,
# 	    volid => "local-lvm:vm-102-disk-0",
# 	},
# 	# [...]
#     ]
# 
# Backups will also contain additional keys:
# 
#     [
# 	{
# 	    content => "backup",
# 	    ctime => 1742405070, # creation time as unix timestamp
# 	    format => "tar.zst",
# 	    notes => "...", # comment that was entered when backup was created
# 	    size => 328906840, # in bytes!
# 	    subtype => "lxc", # "lxc" for containers, "qemu" for VMs
# 	    vmid => 106,
# 	    volid => "local:backup/vzdump-lxc-106-2025_03_19-18_24_30.tar.zst",
# 	},
# 	# [...]
#     ]

# XXX in our case we use $plugin->list_volumes_with_cache

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


        if( $uri =~ /VolumesAndSnapshotsList$/ ){

            is($content,'',"$STAGE: VolumesAndSnapshotsList called withoud arguments");
            return { code => 200, content => encode_json({generation=>12,
                    data=>{ok=>JSON::true,
                        volumes=>[ { tags=>{'pve-disk'=>123, virt=>'pve','pve-loc'=>'storpool','pve-vm'=>11,'pve-type'=>'images','pve-snap-v'=>'4.1.3',pve=>'storeid'}, name=>'~4.1.3', size=>6666 } ]
                        }
                })
            };
        }

    }
);

truncate_http_log();
my $class = PVE::Storage::Custom::StorPoolPlugin->new();

@endpoints = ();
my $result = $class->list_volumes('storeid',{}, '11', []);

is(scalar @$result,0, "$STAGE: no content types");
TODO: {
    note "Here the API calls must be 0!";
    local $TODO = "$STAGE API call should be avoided when \$content_type argument is empty";
    is_deeply(\@endpoints, [], "$STAGE: no API call on empty content types");
}


truncate_http_log();
$STAGE = 2;
@endpoints = ();
$result = $class->list_volumes('storeid',{}, '11', [qw/images/]);

my $expected = [{
    'vmid' => 11,
    'size' => 6666,
    'content' => 'images',
    'format' => 'raw',
    'volid' => 'storeid:vm-11-disk-123-sp-4.1.3.raw',
    'parent' => undef,
    'used' => undef
}];


is_deeply($result, $expected, "$STAGE: result correct");
is($http_method, 'GET', "$STAGE: API call method GET");
is($http_request,'',"$STAGE: API call empty request");
is_deeply(\@endpoints, ['VolumesAndSnapshotsList'], "$STAGE: get images API call");

my $log = slurp_http_log();

like($log, qr/^[^\n]+$/s, "HTTP log one line");
like($log, qr/ GET\s+VolumesAndSnapshotsList\s+200 /x, "HTTP log correct API call");


