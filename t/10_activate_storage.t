#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Test::More;
use unconstant; # disable constant inlining
use JSON;

use PVE::Storage::Custom::StorPoolPlugin;
use PVE::Storpool qw/mock_confget truncate_http_log slurp_http_log mock_lwp_request/;
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-10.txt';

# $plugin->activate_storage($storeid, \%scfg, \%cache)
# B<REQUIRED:> Must be implemented in every storage plugin.
# 
# Activates the storage, making it ready for further use.
# 
# In essence, this method performs the steps necessary so that the storage can be
# used by remaining parts of the system.
# 
# In the case of file-based storages, this usually entails creating the directory
# of the mountpoint, mounting the storage and then creating the directories for
# the different content types that the storage has enabled. See
# C<L<PVE::Storage::NFSPlugin>> and C<L<PVE::Storage::CIFSPlugin>> for examples
# in that regard.
# 
# Other types of storages would use this method for establishing a connection to
# the storage and authenticating with it or similar. See C<L<PVE::Storage::ISCSIPlugin>>
# for an example.
# 
# If the storage doesn't need to be activated in some way, this method can be a
# no-op.
# 
# C<die>s in case of errors.
# 
# This method may reuse L<< cached information via C<\%cache>|/"CACHING EXPENSIVE OPERATIONS" >>.
# 
# =cut

( $ENV{PATH} ) = ( $ENV{PATH} =~ /^(.*)$/ );

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $http_uri;
my $http_request;
my $data = { 
    generation => 12, 
    data => {
        bw=>123,globalId=>5, creationTimestamp => time(), 
        tags => {'pve-loc'=>'storpool', 'pve-vm'=>'5', 'pve-type'=>'images', 'pve-disk'=>'cloudinit', virt=>'pve'}
    }
};

truncate_http_log();
mock_lwp_request(
    test => sub {
        my $class = shift;
        my $request = shift;
        my $uri     = $request->uri . "";
        my $content = $request->content;

		$http_uri = $uri;
		$http_request = $content;

        return { code => 200, content => encode_json( $data ) }
    }
);


my @result = PVE::Storage::Custom::StorPoolPlugin::activate_storage(undef, 666, {}, 'test');
my $log = slurp_http_log();
my $gmtime  = gmtime() . "";

is_deeply( \@result, [$data], 'volume template got data as is');
like($http_uri, qr/VolumeTemplateDescribe\/666/, 'called correct API endpoint');
is($http_request, '', 'no http params passed');
like($log, qr/$gmtime.*GET VolumeTemplateDescribe\/666 200/, 'cloudinit2 VolumesList API logged');


done_testing();
