#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;
use unconstant; # disable constant inlining
use JSON;
use Data::Dumper;

use PVE::Storage::Custom::StorPoolPlugin;
use PVE::Storpool qw/mock_confget truncate_http_log slurp_http_log mock_lwp_request/;
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-11.txt';

 
# =head3 $plugin->alloc_image($storeid, $scfg, $vmid, $fmt, $name, $size)
# 
# B<REQUIRED:> Must be implemented in every storage plugin.
# 
# Allocates a disk image with the given format C<$fmt> and C<$size> in bytes,
# returning the name of the new image (the new C<$volname>). See
# C<L<< plugindata()|/"$plugin->plugindata()" >>> for all disk formats.
# 
# Optionally, if given, set the name of the image to C<$name>. If C<$name> isn't
# provided, the next name should be determined via C<L<< find_free_diskname()|/"$plugin->find_free_diskname(...)" >>>.
# 
# C<die>s in case of an error of if the underlying storage doesn't support
# allocating images.
# 
# This method is called in the context of C<L<< cluster_lock_storage()|/"cluster_lock_storage(...)" >>>,
# i.e. when the storage is B<locked>.
# 

( $ENV{PATH} ) = ( $ENV{PATH} =~ /^(.*)$/ );

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

undef $@;

my $result = eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, 'vmid', 'raw2', 'name', 1024) };

like($@, qr/unsupported format.*raw2/, 'dies on unsupported format');

my ($http_uri, $http_request);
my $STAGE = ''; # Used to follow inner LWP mock tests
my $response_data = { 
    generation => 12, 
    data => {
        generation => 12, ok => JSON::true,
        bw=>123,globalId=>5, creationTimestamp => time(), 
    }
};
my $response_vol_info = {
    generation => 12,
    data => {
        bw => 123, creationTimestamp=>time(), id=>6411, iops => 10000, globalId => 5
    }
};
my $expected_request = { template => 666, size => 1024 * 1024, 
    tags=>{pve=>666, 'pve-loc' => 'storpool', 'pve-type'=>'images',virt=>'pve' } 
    };

truncate_http_log();
mock_lwp_request( # Every HTTP call lands here
    test => sub {
        my $class = shift;
        my $request = shift;
        my $uri     = $request->uri . "";
        my $content = $request->content;
        my $method  = $request->method;

        if( $uri =~ /VolumeCreate$/ ) { # sp_vol_create
            my $decoded = decode_json($content);

            is_deeply( $decoded, $expected_request, "$STAGE: create volume tags passed" );
        }
        if( $uri =~ m{Volume/~5$} ) { # sp_vol_info_single
            
            is( $content, '', "$STAGE: vol_info request empty" );
            say "LWP";
            say Dumper $uri;
            say Dumper $content;
            say Dumper $method;
        }


		$http_uri = $uri;
		$http_request = $content;

        return { code => 200, content => encode_json( $response_data ) }
    }
);

# No extra tags not returning array
$STAGE = '1';
undef $@;
$result = eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, undef, 'raw', 'name', 1024) };
like($@, qr/expected exactly one volume/, 'Bad response, data not array');

say "="x150;
# No extra tags returning array elems > 1
#$response_data->{data} = [ $response_data->{data}, $response_data->{data} ];
$STAGE = '2';
undef $@;
$result = eval { PVE::Storage::Custom::StorPoolPlugin::alloc_image(undef, 666, {}, undef, 'raw', 'name', 1024) };
like($@, qr/expected exactly one volume/, 'Bad response, data not array');

say "RES";
say Dumper $http_uri;
say Dumper $http_request;

say Dumper $result;


done_testing();
