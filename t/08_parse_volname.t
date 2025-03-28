#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use Scalar::Util qw/tainted/;
use lib 'tlib/'; # Taint mode removes PERL5LIB
use lib 'lib/';

use PVE::Storpool qw/storpool_confget_data write_config mock_confget taint/;
use PVE::Storage::Custom::StorPoolPlugin;


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);
# Invalid volname
undef $@;
my $result = eval { PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef,"test") };

ok( !defined $result , 'invalid volname dies' );
like( $@, qr/Internal StorPool error: don't know how to decode/, 'invalid volname die msg' );


my $iso_vol = "test-sp-4.3.2.iso";
taint($iso_vol);
my @res = PVE::Storage::Custom::StorPoolPlugin::parse_volname(undef, $iso_vol );

foreach my $val ( @res ) {
	next if !$val;
#	say "VAL $val - " . tainted($val);
}

done_testing();
