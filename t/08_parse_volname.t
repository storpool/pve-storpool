#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use Scalar::Util qw/tainted/;
use JSON;
use unconstant; # disable constant inlining

use PVE::Storpool qw/mock_confget taint not_tainted mock_sp_cfg mock_lwp_request truncate_http_log slurp_http_log/;
use PVE::Storage::Custom::StorPoolPlugin;
# Use different log for every test in order to parallelize them
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-08.txt';


# Parses $volname, returning a list representing the parts encoded in
# the volume name:
#
#    my ($vtype, $name, $vmid, $basename, $basevmid, $isBase, $format)
#	= $plugin->parse_volname($volname);
# 
# Not all parts need to be included in the list. Those marked as I<optional>
# in the list below may be set to C<undef> if not applicable.
# 
# This method may die in case of errors.
# 
## $vtype
# 
# The content type ("volume type") of the volume, e.g. "images", "iso", etc.
# 
# See "$plugin->plugindata()" for all content types.
# 
## $name
# 
# The display name of the volume. This is usually what the underlying storage
# itself uses to address the volume.
# 
# For example, disks for virtual machines that are stored on LVM thin pools are
# named C<vm-100-disk-0>, C<vm-1337-disk-1>, etc. That would be the C<$name> in
# this case.
# 
## $vmid (optional)
# 
# The ID of the guest that owns the volume.
# 
## $basename (optional)
# 
# The C<$name> of the volume this volume is based on. Whether this part
# is returned or not depends on the plugin and underlying storage.
# Only applies to disk images.
# 
# For example, on ZFS, if the VM is a linked clone, C<$basename> refers
# to the C<$name> of the original disk volume that the parsed disk volume
# corresponds to.
# 
## $basevmid (optional)
# 
# Equivalent to C<$basename>, except that C<$basevmid> refers to the
# C<$vmid> of the original disk volume instead.
# 
## $isBase (optional)
# 
# Whether the volume is a base disk image.
# 
## $format
# 
# The format of the volume. If the volume is a VM disk (C<$vtype> is
# C<"images">), this should be whatever format the disk is in. For most
# other content types C<"raw"> should be used.
# 
# $plugin->plugindata() for all formats.

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);
# Invalid volname
undef $@;
my $result = eval { PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef,"test.iso") };

ok( !defined $result , 'invalid volname dies' );
like( $@, qr/Internal StorPool error: don't know how to decode/, 'invalid volname die msg' );

## ISO
my $volname = "test-sp-4.3.2.iso";
$result = [ 'iso', '4.3.2', undef, undef, undef, !!0, 'raw' ];

taint($volname);

my @res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $volname );

is_deeply(\@res, [not_tainted(@res)], 'iso not tainted');
is_deeply(\@res, $result, 'iso correct result');


## IMG
$volname = 'img-test-sp-4.0.1.raw';
$result = [ 'images', '4.0.1', undef, undef, undef, !!0, 'raw' ];

@res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $volname );

is_deeply(\@res, [not_tainted(@res)], 'img not tainted');
is_deeply(\@res, $result, 'img correct result');

## Snaphost
$volname = 'snap-55-disk-0-proxmox-p-1.2.3-sp-4.5.6.raw';
$result = [ 'images', '4.5.6', 55, undef, undef, !!0, 'raw' ];

@res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $volname );

is_deeply(\@res, [not_tainted(@res)], 'snapshot not tainted');
is_deeply(\@res, $result, 'snapshot correct result');

## VMState
$volname = 'snap-1-state-proxmox-sp-6.5.4.raw';
$result = [ 'images', '6.5.4', 1, undef, undef, !!0, 'raw' ];

@res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $volname );

is_deeply(\@res, [not_tainted(@res)], 'vmstate not tainted');
is_deeply(\@res, $result, 'vmstate correct result');

## Base
$volname = 'base-10-disk-234-sp-4.9.3.raw';
$result  = [ 'images', '4.9.3', 10, undef, undef, 1, 'raw' ];

@res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $volname );

is_deeply(\@res, [not_tainted(@res)], 'base not tainted');
is_deeply(\@res, $result, 'base correct result');

## Disk
$volname = 'vm-19-disk-0-sp-10.0.13.raw';
$result  = [ 'images', '10.0.13', 19, undef, undef, '', 'raw' ];

@res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $volname );

is_deeply(\@res, [not_tainted(@res)], 'disk not tainted');
is_deeply(\@res, $result, 'disk correct result');

## Cloudinit
$volname = 'vm-5-cloudinit-sp-5.1.3.raw';
$result  = [ 'images', '5.1.3', 5, undef, undef, '', 'raw' ];

@res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $volname );

is_deeply(\@res, [not_tainted(@res)], 'cloudinit not tainted');
is_deeply(\@res, $result, 'cloudinit correct result');

# Cloudinit without volume

mock_sp_cfg();

$volname = 'vm-5-cloudinit.raw';
$result  = [ 'images', '5', 5, undef, undef, '', 'raw' ];

my $http_uri = undef;
my $http_request = undef;
# Here it must call VolumesList and get the volume from it
truncate_http_log();
mock_lwp_request(
    test => sub {
        my $class = shift;
        my $request = shift;
        my $uri     = $request->uri . "";
        my $content = $request->content;

		$http_uri = $uri;
		$http_request = $content;

		my $data = { generation => 12, data =>[{
				bw=>123,globalId=>5, creationTimestamp => time(), 
				tags => {'pve-loc'=>'storpool', 'pve-vm'=>'5', 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}
			}] 
		};

        return { code => 200, content => encode_json( $data ) }
    }
);


@res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $volname );

my $gmtime  = gmtime() . "";
my $log = slurp_http_log();

like($http_uri, qr/\/VolumesList$/, 'cloundinit2 VolumesList API called');
like($log, qr/$gmtime.*GET VolumesList 200/, 'cloudinit2 VolumesList API logged');
is($http_request, '', 'cloudinit2 VolumesList API called without parameters');
#is_deeply(\@res, [not_tainted(@res)], 'cloudinit2 not tainted'); # TODO here is tainted
is_deeply(\@res, $result, 'cloudinit2 correct result');



done_testing();
