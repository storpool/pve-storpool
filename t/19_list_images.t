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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-19.txt';


# XXX it uses list_volumes_with_cache() sub under the hood, so See 18_list_volumes.t


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

bless_plugin();

my $class = PVE::Storage::Custom::StorPoolPlugin->new();

undef $@;
my $result = eval { $class->list_images('storeid',{},'11',[]) };
my $error = $@;
is($result,undef, "list images volumes undef on volumes list");
like($error, qr/volume list not implemented yet/, "list images dies on volumes list");

TODO: {
    local $TODO = "implement list_images() with volumes list argument handling";
    note "list_images uses list_volumes_with_cache and volumes list is not yet implemented";
    is($error, '', "list_images() with volumes list implamented");
}

done_testing();
