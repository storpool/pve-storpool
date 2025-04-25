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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-12.txt';


#= $plugin->filesystem_path(\%scfg, $volname [, $snapname])
# 
# $plugin->filesystem_path(...)
# 
# B<SITUATIONAL:> This method must be implemented for file-based storages.
# 
# Returns the absolute path on the filesystem for the given volume or snapshot.
# In list context, returns path, guest ID and content type:
# 
#     my $path = $plugin->filesystem_path($scfg, $volname, $snapname)
#     my ($path, $vmid, $vtype) = $plugin->filesystem_path($scfg, $volname, $snapname)
# 
# =cut


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

my $version = '4.3.2';
my $volname = "test-sp-$version.iso";
my $result = [ 'iso', $version, undef, undef, undef, !!0, 'raw' ];

taint($volname);
bless_plugin();

my $class = PVE::Storage::Custom::StorPoolPlugin->new();

# filesystem_path uses parse_volname() under the hood and there is a separate test for it
my $path = PVE::Storage::Custom::StorPoolPlugin::filesystem_path($class, undef, $volname, undef );
like($path, qr{/dev/storpool-byid/$version}, 'filesystem_path correct path returned');

undef $@;
$path = eval { PVE::Storage::Custom::StorPoolPlugin::filesystem_path($class, undef, "invalid_volume_name?", undef ) };
is($path, undef, 'invalid volume name');
is(defined($@), 1, 'died with the invalid volume name');

undef $@;
$path = PVE::Storage::Custom::StorPoolPlugin::filesystem_path($class, undef, "snap-55-disk-0-proxmox-p-1.2.3-sp-$version.raw", undef );
like($path, qr{/dev/storpool-byid/$version}, 'filesystem_path correct path returned');

my @path = PVE::Storage::Custom::StorPoolPlugin::filesystem_path($class, undef, "snap-55-disk-0-proxmox-p-1.2.3-sp-$version.raw", undef );
is_deeply(\@path, [ qq{/dev/storpool-byid/$version}, qw/55 images/], 'wantarray');

# Missing cloudinit volume - it searches for it if no global ID is provided
undef $@;
truncate_http_log();
mock_lwp_request( data => { content => '{}', code => 200 } );
$path = eval { PVE::Storage::Custom::StorPoolPlugin::filesystem_path($class, undef, "vm-11-cloudinit.raw", undef ) };

is($path, undef, 'cloudinit missing image result');
like($@, qr/Missing.*volume/, 'cloudinit missing image died');

# cloudinit with global ID
undef $@;
$path = PVE::Storage::Custom::StorPoolPlugin::filesystem_path($class, undef, "vm-11-cloudinit-sp-$version.raw", undef );
is($path, "/dev/storpool-byid/$version", 'cloudinit image with global ID');

# cloudinit found image
undef $@;
my $data = { generation => 12, data =>[{
        bw=>123,globalId=>$version, creationTimestamp => time(),
        tags => {'pve-loc'=>'storpool', 'pve-vm'=>11, 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}
    }]
};

mock_lwp_request( data => { content => encode_json($data), code => 200 } );
$path = PVE::Storage::Custom::StorPoolPlugin::filesystem_path($class, undef, "vm-11-cloudinit.raw", undef );
is($path, "/dev/storpool-byid/$version", 'cloudinit image with global ID');

done_testing();
