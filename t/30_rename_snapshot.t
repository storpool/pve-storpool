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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-30.txt';

=pod

=head3 rename_snapshot

    $plugin->rename_snapshot($scfg, $storeid, $volname, $source_snap, $target_snap)

Rename a volume source snapshot C<$source_snap> to a target snapshot C<$target_snap>.

=cut

my ( $http_uri, $http_request, $http_method, @endpoints );
my $STAGE = 1;
my $global_id = '4.1.3';
my $tags_return = { 'pve-snap'=>'old_snap', 'pve-snap-v' => $global_id ,'pve-loc'=>'storpool', 'pve-vm'=>'5',virt=>'pve',pve=>'storeid' };
my $tags = { 'pve-snap'=>'new_snap', 'pve-snap-v' => $global_id ,'pve-loc'=>'storpool', 'pve-vm'=>'5',virt=>'pve',pve=>'storeid' };

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

        if( $uri =~ /SnapshotsList$/ ){
            return { 
                code => 200, 
                content => encode_json({generation=>12, 
                    data=>[
                        {globalId=>$global_id,tags=>$tags_return }
                    ]
                }) 
            };
        }

        if( $uri =~ m{ /SnapshotUpdate/~\Q$global_id\E$ }x ){
			is($method, 'POST', "SnapshotUpdate POST");
            is_deeply(decode_json($content), {tags=>$tags}, "SnapshotUpdate POST data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }

    }
);


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );
bless_plugin();


my $volname = "test-sp-$global_id.iso";
my $class 	= PVE::Storage::Custom::StorPoolPlugin->new();
my $cfg 	= PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

# Result OSnapshotUpdate
undef $@;
my $result = $class->rename_snapshot({},'storeid',$volname, "old_snap", "new_snap");

is($result, undef, "Snapshot rename result");
# Get current snapshot, check if snapshot exists with same name, snapshot update
is_deeply(\@endpoints,['SnapshotsList','SnapshotsList',"SnapshotUpdate/~$global_id"], "Correct API calls used");

# Snapshot exists error
undef $@;
$result = eval { $class->rename_snapshot({},'storeid',$volname, "old_snap", "old_snap") };
like($@, qr/Target snapshot.*already exists/, 'New snapshot error exists');

# Snapshot missing error
undef $@;
$result = eval { $class->rename_snapshot({},'storeid',$volname, "old_snap2", "old_snap3") };
like($@, qr/no snapshot found with the name old_snap2/, 'Missing snapshot error');


done_testing();
