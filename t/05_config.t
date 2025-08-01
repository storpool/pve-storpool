#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

use PVE::Storage::Custom::StorPoolPlugin;
use PVE::Storpool qw/storpool_confget_data write_config mock_confget/;

# use storpool_confget cli in t/
my ($bin)  = ($Bin =~ /^(.*)$/); # untaint
my ($path) = ($ENV{PATH} =~ /^(.*)$/); # untaint
$ENV{PATH} = $bin . ':' . $path;

sub get_config { # --> %Hash
    PVE::Storage::Custom::StorPoolPlugin::sp_confget()
}

sub sp_cfg_get {
    PVE::Storage::Custom::StorPoolPlugin::sp_cfg('Scfg','StoreID')
}


### sp_confget
write_config( exit_code => 0, data => "var=value" );
is_deeply( {get_config()}, {var=>'value'}, "one value" );

write_config( exit_code => 0, data => "var=value\ntest=123" );
is_deeply( {get_config()}, {var=>'value', test=>123}, "two values" );

write_config( exit_code => 1, data => "var=value\ntest=123" );
is_deeply( {get_config()}, {var=>'value', test=>123}, "two values. exit code 1" );

write_config( exit_code => 1, data => "var=" );
is_deeply( {get_config()}, {var=>''}, 'Key no value');

write_config( exit_code => 1, data => "var=test=123" );
is_deeply( {get_config()}, {var=>'test=123'}, 'Triple value error');

write_config( exit_code => 1, data => "var=test\nvar=test2\ntest=omg" );
is_deeply( {get_config()}, {var=>'test2',test=>'omg'}, 'Overwrite variable');

write_config( exit_code => 1, data => "key = value" );
is_deeply( {get_config()}, {'key '=>' value'}, 'Whitespaces bug'); # TODO

write_config( exit_code => 0, data => "" );
is_deeply( {get_config()}, {}, 'Empty response');

## sp_cfg
# Here we replace the sp_confget sub
write_config( exit_code => 0, data => "key=test\nsecond=test2" );
my $conf = eval { sp_cfg_get(); };
my $err = $@;
ok( $err, 'sp_cfg misconfiguration' );
like( $err, qr/Incomplete StorPool configuration/, 'sp_cfg die msg' );

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_AUTH_TOKEN=>'token' );
$conf = eval { sp_cfg_get(); };
$err = $@;
ok( $err, 'sp_cfg misconfiguration' );
like( $err, qr/Incomplete StorPool configuration/, 'sp_cfg die msg missing SP_OURID' );

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666 );
$conf = eval { sp_cfg_get(); };
$err = $@;
ok( $err, 'sp_cfg misconfiguration' );
like( $err, qr/Incomplete StorPool configuration/, 'sp_cfg die msg missing SP_AUTH_TOKEN' );

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_OURID=>666, SP_AUTH_TOKEN=>'token' );
$conf = eval { sp_cfg_get(); };
$err = $@;
ok( $err, 'sp_cfg misconfiguration' );
like( $err, qr/Incomplete StorPool configuration/, 'sp_cfg die msg missing SP_API_HTTP_PORT' );

mock_confget( SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );
$conf = eval { sp_cfg_get(); };
$err = $@;
ok( $err, 'sp_cfg misconfiguration' );
like( $err, qr/Incomplete StorPool configuration/, 'sp_cfg die msg missing SP_API_HTTP_HOST' );

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_AUTH_TOKEN=>'token', SP_OURID=>666 );

my $expected = {
    storeid => 'StoreID',
    scfg    => 'Scfg',
    api     => {
        url => 'http://local-machine:80/ctrl/1.0/',
        ourid => 666,
        auth_token => 'token'
    },
    proxmox => {
        id => {
           name => 'storpool'
        }
    }
};

is_deeply( sp_cfg_get(), $expected, 'sp_cfg Config structure' );

done_testing();
