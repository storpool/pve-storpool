#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;
#use Scalar::Util qw/reftype readonly/;

use PVE::Storage::Custom::StorPoolPlugin;

my $ver = \%{PVE::Storage::Custom::StorPoolPlugin::};
my $methods = [ 
    qw/
    activate_storage alloc_image status parse_volname filesystem_path activate_volume deactivate_volume 
    free_image volume_has_feature volume_size_info list_volumes_with_cache list_volumes list_images create_base 
    clone_image volume_resize deactivate_storage check_connection volume_snapshot volume_snapshot_delete
    volume_snapshot_rollback volume_snapshot_needs_fsfreeze get_subdir delete_store rename_volume
    / 
];

foreach my $method ( @$methods ) {
    next if !$method;
    ok( $ver->{ $method }, "sub $method exists" );
    is( ref *{ $ver->{ $method } }{CODE}, 'CODE', "sub $method is sub" )
}


done_testing();
