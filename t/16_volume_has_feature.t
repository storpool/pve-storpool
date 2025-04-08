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

my $version = '4.3.2';
my $volname = "test-sp-$version.iso";
my $cfg 	= PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);
my $class 	= PVE::Storage::Custom::StorPoolPlugin->new();



# Without snapshot
is( $class->volume_has_feature({}, 'clone', 11, $volname),      1,      "feature clone" );
is( $class->volume_has_feature({}, 'copy', 11, $volname),       1,      "feature copy" );
is( $class->volume_has_feature({}, 'replicate', 11, $volname),  undef,  "feature replicate" );
is( $class->volume_has_feature({}, 'snapshot', 11, $volname),   1,      "feature snapshot" );
is( $class->volume_has_feature({}, 'sparseinit', 11, $volname), 1,      "feature sparseinit" );
is( $class->volume_has_feature({}, 'template', 11, $volname),   1,      "feature template" );
is( $class->volume_has_feature({}, 'rename', 11, $volname),     1,      "feature rename" );


# With snapshot
is( $class->volume_has_feature({}, 'clone', 11, $volname,'snap'),       1,     "feature snapshot clone" );
is( $class->volume_has_feature({}, 'copy', 11, $volname,'snap'),        1,     "feature snapshot copy" );
is( $class->volume_has_feature({}, 'replicate', 11, $volname,'snap'),   undef, "feature snapshot replicate" );
is( $class->volume_has_feature({}, 'snapshot', 11, $volname,'snap'),    1,     "feature snapshot snapshot" );
is( $class->volume_has_feature({}, 'sparseinit', 11, $volname,'snap'),  1,     "feature snapshot sparseinit" );
is( $class->volume_has_feature({}, 'template', 11, $volname,'snap'),    undef, "feature snapshot template" );
is( $class->volume_has_feature({}, 'rename', 11, $volname,'snap'),      undef, "feature snapshot rename" );

done_testing();
