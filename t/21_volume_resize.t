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
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-21.txt';


=pod 
=head3 $plugin->volume_resize(\%scfg, $storeid, $volname, $size [, $running])

B<REQUIRED:> Must be implemented in every storage plugin.

Resizes a volume to the new C<$size> in bytes. Optionally, the guest that owns
the volume may be C<$running> (= C<1>).

C<die>s in case of errors, or if the underlying storage implementation or the
volume's format doesn't support resizing.

This function should not return any value. In previous versions the returned
value would be used to determine the new size of the volume or whether the
operation succeeded.

=cut

my ( $http_uri, $http_request, $http_method, @endpoints );

my $STAGE   = 1; # Used to follow the mocked method tests
my $expected_vsnap_request = { 
    'tags' => {
          'pve-vm' => '5',
          'pve-loc' => 'storpool',
          'pve-base' => '1',
          'virt' => 'pve',
          'pve-type' => 'images',
          'pve-disk' => 'cloudinit'
    }
};
my $expected_reassign = [{"volume"=>"~4.1.3","detach"=>"all","force"=>JSON::false}];
my $size = 6666;

truncate_http_log();
mock_lwp_request(
    test => sub {
        my $class   = shift;
        my $request = shift;
        my $uri     = $request->uri . "";
        my $content = $request->content;
        my $method  = $request->method;
        my ( $endpoint ) = ( $uri =~ m{/(\w+(?:/~\d+(?:\.\d\.\d)?)?)$} );

        # Set for later use in the tests
        $http_uri       = $uri;
        $http_request   = $content;
        $http_method    = $method;

        push @endpoints, $endpoint;

        if( $uri =~ m{ /VolumeUpdate/~4.3.2$ }x ){
			is($method, 'POST', "$STAGE: VolumeUpdate POST");
            is_deeply(decode_json($content), {size=>$size}, "$STAGE: VolumeUpdate POST data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }

        if( $uri =~ m{ /ClientConfigWait/666 }x ){

			is($method, 'GET', "$STAGE: ClientConfigWait GET");
            is($content,'', "$STAGE: ClientConfigWait empty data request");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true, clientGeneration=>666, configStatus=>'running',delay=>123,generation=>11,id=>11}}) }
        }
        elsif( $uri =~ m{/(Snapshot|Volume)/~\d+\.\d+\.\d+} ){

            my $expected = {"tags"=>{"pve-loc"=>"storpool","pve-type"=>"iso","pve"=>"storeid","pve-comment"=>"test","pve-snap"=>"4.3.2","pve-snap"=>JSON::true,"virt"=>"pve"}};

            return { code=>200, content => encode_json({generation=>12, data=>[$expected]}) };
        }
    }
);


mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

bless_plugin();

my $class = PVE::Storage::Custom::StorPoolPlugin->new();

my $version = '4.3.2';
my $volname = "test-sp-$version.iso";
my $running = 0; # Running is ignored by us

# Non image volume
undef $@;
my $result = $class->volume_resize({},'storeid', $volname, $size, $running) ;

is(!!$result, 1, "$STAGE: volume resize OK");
is_deeply(\@endpoints, ['Snapshot/~4.3.2',"VolumeUpdate/~$version",666], "$STAGE: volume resize API calls");


done_testing();
