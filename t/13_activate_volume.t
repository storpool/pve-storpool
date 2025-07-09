#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More;
use Scalar::Util qw/tainted/;
use JSON;
use unconstant; # disable constant inlining
use Socket;
use IO::Handle;
use Time::HiRes qw/sleep/;


use PVE::Storpool qw/mock_confget taint not_tainted mock_sp_cfg mock_lwp_request truncate_http_log slurp_http_log bless_plugin/;
use PVE::Storage::Custom::StorPoolPlugin;
# Use different log for every test in order to parallelize them
use constant *PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG => '/tmp/storpool_http_log-13.txt';

my $init_pid = get_init_pid();
{
    no warnings qw/redefine prototype/;
    *PVE::Storage::Custom::StorPoolPlugin::INIT_PID = sub { $init_pid };
}

# =head3 $plugin->activate_volume($storeid, \%scfg, $volname, $snapname [, \%cache])
# 
# =head3 $plugin->activate_volume(...)
# 
# B<REQUIRED:> Must be implemented in every storage plugin.
# 
# Activates a volume or its associated snapshot, making it available to the
# system for further use. For example, this could mean activating an LVM volume,
# mounting a ZFS dataset, checking whether the volume's file path exists, etc.
# 
# C<die>s in case of errors or if an operation is not supported.
# 
# If this isn't needed, the method should simply be a no-op.
# 
# This method may reuse L<< cached information via C<\%cache>|/"CACHING EXPENSIVE OPERATIONS" >>.
# 
# =cut

mock_confget( SP_API_HTTP_HOST => 'local-machine', SP_API_HTTP_PORT=>80, SP_OURID=>666, SP_AUTH_TOKEN=>'token' );

my $cfg = PVE::Storage::Custom::StorPoolPlugin::sp_cfg(undef,undef);

my $STAGE   = 1;
my $version = '4.3.2';
my $volname = "test-sp-$version.iso";
my $response_reassign = {};
my $http_uri;
my $http_request;
my @endpoints;

taint($volname);
bless_plugin();

my $expected_reassign_request = [{ro=>[666],snapshot=>"~4.3.2"}];

truncate_http_log();
mock_lwp_request(
    test => sub {
        my $class   = shift;
        my $request = shift;
        my $uri     = $request->uri . "";
        my $content = $request->content;
        my $method  = $request->method;
        my ( $endpoint ) = ( $uri =~ m{/(\w+(?:/~\d)?)$} );

        $http_uri       = $uri;
        $http_request   = $content;

        push @endpoints, $endpoint;

        if( $uri =~ /VolumesReassignWait$/ ) {
            my $decoded = decode_json($content);
            is($method,'POST', "$STAGE: VolumesReassignWait POST");
            is_deeply($decoded, $expected_reassign_request, "$STAGE: VolumesReassignWait POST data");
            return { code => 200, content => encode_json({generation=>12, data=>{ok=>JSON::true}}) }
        }


    }
);

my $return_path = 1;
my $skip_path_test = 0;
{
    no warnings qw/redefine prototype once/;
    *PVE::Storage::Custom::StorPoolPlugin::path = sub {
        my $path = PVE::Storage::Plugin::path(@_);

        ok($path,"$STAGE: path returned") if !$skip_path_test;

        return $return_path ? PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG : '';
    };
}

my $class = PVE::Storage::Custom::StorPoolPlugin->new();

undef $@;
@endpoints = ();
my $result = eval { $class->activate_volume('storeid',{}, 'invalid') };
is($result, undef, 'Invalid volname');
like($@, qr/don't know how to decode/, 'Invalid volname died');
is_deeply(\@endpoints,[], 'Invalid volume no API call');

undef $@;
@endpoints = ();
$STAGE = 2;
$return_path = 0;
$result = eval { $class->activate_volume('storaid', {}, $volname) };
is($result, undef, "$STAGE: missing attached volume");
like($@, qr/could not find the just-attached/, "$STAGE: missing attached volume died");

undef $@;
@endpoints = ();
$STAGE = 3;
$return_path = 1;
$result = $class->activate_volume('storeid',{}, $volname);

is($@, '', "$STAGE: volume attached");
is_deeply(\@endpoints, ['VolumesReassignWait'], "$STAGE: API called");

## Snapshot

my $vm_status_response = {};
my $vm_status_response_vmid;
{
    no warnings qw/redefine prototype/;
    *PVE::Storage::Custom::StorPoolPlugin::get_vm_status = sub {
        $vm_status_response_vmid = shift;
        return $vm_status_response;
    }
}

undef $@;
@endpoints = ();
$STAGE = 4.1;
$volname = "snap-55-disk-0-proxmox-p-1.2.3-sp-$version.raw";
$vm_status_response = {lock=>1};
$expected_reassign_request->[0]->{force}  = JSON::true;
$expected_reassign_request->[0]->{detach} = 'all';
$result = eval { $class->activate_volume('storeid',{migratedfrom=>'mars'}, $volname) };

is($result, 0, "$STAGE: failed migration result");


undef $@;
@endpoints = ();
$STAGE = 4;
$volname = "snap-55-disk-0-proxmox-p-1.2.3-sp-$version.raw";
$vm_status_response = {lock=>1};
$expected_reassign_request->[0]->{force}  = JSON::true;
$expected_reassign_request->[0]->{detach} = 'all';
$result = $class->activate_volume('storeid',{}, $volname);

isnt($result, undef, "$STAGE: snapshot");
is($vm_status_response_vmid, 55, "$STAGE: get_vm_status correct ID");
is_deeply(\@endpoints,['VolumesReassignWait'], "$STAGE: api called");


undef $@;
@endpoints = ();
$STAGE = 5;
$vm_status_response_vmid = undef;
$volname = "vm-11-disk-0-sp-4.1.3.raw";
$expected_reassign_request = [{"detach"=>"all","rw"=>[666],"force"=>JSON::true,"volume"=>"~4.1.3"}];
$result = $class->activate_volume('storeid',{}, $volname);

isnt($result, undef, "$STAGE: volume");
is($vm_status_response_vmid, 11, "$STAGE: volume ID vm_status called");
is_deeply(\@endpoints,['VolumesReassignWait'], "$STAGE: api called");

# Lock migrate from migration
undef $@;
@endpoints = ();
$STAGE = 6;
$volname = "vm-11-disk-0-sp-4.1.3.raw";
$vm_status_response = { lock => 'migrate', hastate => '' };
$expected_reassign_request = [{"rw"=>[666],"volume"=>"~4.1.3"}];
$result = $class->activate_volume('storeid',{migratedfrom=>'mars'}, $volname);

isnt($result, undef, "$STAGE: volume");
is($vm_status_response_vmid, 11, "$STAGE: volume ID");
is_deeply(\@endpoints,['VolumesReassignWait'], "$STAGE: api called");



# Lock migrate, not executed from migration
undef $@;
@endpoints = ();
$STAGE = 7;
$volname = "vm-11-disk-0-sp-4.1.3.raw";
$vm_status_response = { lock => 'migrate', hastate => '' };
$expected_reassign_request = [{"rw"=>[666],"volume"=>"~4.1.3"}];
$result = $class->activate_volume('storeid',{other=>'mars'}, $volname);

isnt($result, undef, "$STAGE: volume");
is($vm_status_response_vmid, 11, "$STAGE: volume ID");
is_deeply(\@endpoints,['VolumesReassignWait'], "$STAGE: api called");


# Killed worker parent
undef $@;
@endpoints = ();
$STAGE = 8;
$skip_path_test = 1;
my ( $result_fork, $error_fork ) = worker();

is( $result_fork, 'undef', "$STAGE: died on parent missing before call");
like($error_fork, qr/activate_volume parent PID is dead/, "$STAGE: died on parent missing before call error message");
$skip_path_test = 0;



# Get init pid, systemd or init
# 1 if run as a daemon, else the user session init pid
sub get_init_pid {
    socketpair(my $child, my $parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ||  die "socketpair: $!";
    $child->autoflush(1);
    $parent->autoflush(1);

    my $main_pid = 0;

    my $pid = fork() // die "Failed fork: $!";

    if( $pid ){
        close $parent;
        chomp(my $line = <$child>);
        close $child;
        $main_pid = $line;
        waitpid($pid,0);
        #exit;
    } else {
        close $child;
        my $pid2 = fork() // die "Failed fork2: $!";

        if( $pid2 ){
            waitpid($pid2,0);
            exit(0);
        } else {
            kill(15,getppid);
            sleep 0.1;
            print $parent getppid;
            close $parent;
            exit(0);
        }
    }

    return $main_pid;
}


sub worker {
    socketpair(my $child, my $parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ||  die "socketpair: $!";
    $child->autoflush(1);
    $parent->autoflush(1);
    my @data;

    my $pid1 = fork() // die "Failed to fork parent1: $!";

    if( $pid1 ) {
        close $parent;
        chomp(my $line = <$child>);
        chomp(my $line2 = <$child>);
        push @data, $line;
        push @data, $line2;
        close $child;
        waitpid($pid1,0);
        #exit;
    } else { # Child 1
        close $child;
        my $pid2 = fork() // die "Failed to fork parent2: $!";

        if( $pid2 ){
            waitpid($pid2,0);
            exit;
        } else { # Child 2
            undef $@;
            kill(15, getppid);
            sleep 0.1; # It takes some time before gettpid show the PID of the adopter INIT
            my $res = eval { $class->activate_volume('storeid',{}, $volname) } // 'undef';
            print $parent $res."\n";
            print $parent $@."\n";
            close $parent;

            exit;
        }
    }
    return @data;
}


done_testing();
