#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More;
use Scalar::Util qw/tainted/;
use JSON;
use unconstant; # disable constant inlining

use PVE::Storpool qw/mock_confget bless_plugin/;
use PVE::Storage::Custom::StorPoolPlugin;


# =head3 $plugin->volume_has_feature(\%scfg, $feature, $storeid, $volname, $snapname [, $running, \%opts])
# 
# =head3 $plugin->volume_has_feature(...)
# 
# B<REQUIRED:> Must be implemented in every storage plugin.
# 
# Checks whether a volume C<$volname> or its snapshot C<$snapname> supports the
# given C<$feature>, returning C<1> if it does and C<undef> otherwise. The guest
# owning the volume may optionally be C<$running>.
# 
# C<$feature> may be one of the following:
# 
#     clone      # linked clone is possible
#     copy       # full clone is possible
#     replicate  # replication is possible
#     snapshot   # taking a snapshot is possible
#     sparseinit # volume is sparsely initialized
#     template   # conversion to base image is possible
#     rename     # renaming volumes is possible
# 
# Which features are available under which circumstances depends on multiple
# factors, such as the underlying storage implementation, the format used, etc.
# It's best to check out C<L<PVE::Storage::Plugin>> or C<L<PVE::Storage::ZFSPoolPlugin>>
# for examples on how to handle features.
# 
# Additional keys are given in C<\%opts>:
# 


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );


bless_plugin();

my $class 	= PVE::Storage::Custom::StorPoolPlugin->new();

my @same = qw/test-sp-4.3.2.iso img-test-sp-4.0.1.raw snap-55-disk-0-proxmox-p-1.2.3-sp-4.5.6.raw 
    snap-1-state-proxmox-sp-6.5.4.raw vm-19-disk-0-sp-10.0.13.raw vm-5-cloudinit-sp-5.1.3.raw/;
my $count = 1;
foreach my $volname ( @same ){
# Without snapshot
    is( $class->volume_has_feature({}, 'clone', 11, $volname),      1,      "feature $count clone" );
    is( $class->volume_has_feature({}, 'copy', 11, $volname),       1,      "feature $count copy" );
    is( $class->volume_has_feature({}, 'replicate', 11, $volname),  undef,  "feature $count replicate" );
    is( $class->volume_has_feature({}, 'snapshot', 11, $volname),   1,      "feature $count snapshot" );
    is( $class->volume_has_feature({}, 'sparseinit', 11, $volname), 1,      "feature $count sparseinit" );
    is( $class->volume_has_feature({}, 'template', 11, $volname),   1,      "feature $count template" );
    is( $class->volume_has_feature({}, 'rename', 11, $volname),     1,      "feature $count rename" );


# With snapshot
    is( $class->volume_has_feature({}, 'clone', 11, $volname,'snap'),       1,     "feature $count snapshot clone" );
    is( $class->volume_has_feature({}, 'copy', 11, $volname,'snap'),        1,     "feature $count snapshot copy" );
    is( $class->volume_has_feature({}, 'replicate', 11, $volname,'snap'),   undef, "feature $count snapshot replicate" );
    is( $class->volume_has_feature({}, 'snapshot', 11, $volname,'snap'),    1,     "feature $count snapshot snapshot" );
    is( $class->volume_has_feature({}, 'sparseinit', 11, $volname,'snap'),  1,     "feature $count snapshot sparseinit" );
    is( $class->volume_has_feature({}, 'template', 11, $volname,'snap'),    undef, "feature $count snapshot template" );
    is( $class->volume_has_feature({}, 'rename', 11, $volname,'snap'),      undef, "feature $count snapshot rename" );
    $count++;
}

my $volname = 'base-10-disk-234-sp-4.9.3.raw';

is( $class->volume_has_feature({}, 'clone', 11, $volname),      1,      "feature base volname clone" );
is( $class->volume_has_feature({}, 'copy', 11, $volname),       1,      "feature base volname copy" );
is( $class->volume_has_feature({}, 'replicate', 11, $volname),  undef,  "feature base volname replicate" );
is( $class->volume_has_feature({}, 'snapshot', 11, $volname),   undef,  "feature base volname snapshot" );
is( $class->volume_has_feature({}, 'sparseinit', 11, $volname), 1,      "feature base volname sparseinit" );
is( $class->volume_has_feature({}, 'template', 11, $volname),   undef,  "feature base volname template" );
is( $class->volume_has_feature({}, 'rename', 11, $volname),     undef,  "feature base volname rename" );

is( $class->volume_has_feature({}, 'clone', 11, $volname,'snap'),       1,     "feature base snapshot clone" );
is( $class->volume_has_feature({}, 'copy', 11, $volname,'snap'),        1,     "feature base snapshot copy" );
is( $class->volume_has_feature({}, 'replicate', 11, $volname,'snap'),   undef, "feature base snapshot replicate" );
is( $class->volume_has_feature({}, 'snapshot', 11, $volname,'snap'),    1,     "feature base snapshot snapshot" );
is( $class->volume_has_feature({}, 'sparseinit', 11, $volname,'snap'),  1,     "feature base snapshot sparseinit" );
is( $class->volume_has_feature({}, 'template', 11, $volname,'snap'),    undef, "feature base snapshot template" );
is( $class->volume_has_feature({}, 'rename', 11, $volname,'snap'),      undef, "feature base snapshot rename" );




done_testing();
