#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More tests => 4;

use PVE::Storage::Custom::StorPoolPlugin;
use PVE::Storpool qw/mock_confget/;

# log_info calls syslog

( $ENV{PATH} ) = ( $ENV{PATH} =~ /^(.*)$/ );

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

# get_subdir
undef $@;
eval {
    PVE::Storage::Custom::StorPoolPlugin::get_subdir(undef,undef, "test-type")
};
like($@, qr/not implemented yet/, 'get_subdir');


# delete_store
undef $@;
eval {
    PVE::Storage::Custom::StorPoolPlugin::delete_store(undef,"store-id")
};
like($@, qr/not implemented yet/, 'delete_store');


# deactivate_storage
undef $@;
eval {
    PVE::Storage::Custom::StorPoolPlugin::deactivate_storage(undef,"store-id")
};
like($@, qr/not implemented yet/, 'deactivate_storage');


# list_images with volume list
undef $@;
eval {
    PVE::Storage::Custom::StorPoolPlugin::list_images(undef,undef,undef,'vmID',1)
};
like($@, qr/not implemented yet/, 'deactivate_storage');

