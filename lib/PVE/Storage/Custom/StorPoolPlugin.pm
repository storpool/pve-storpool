# vim: set ts=8 sts=4 sw=4 noet cc=81,101
package PVE::Storage::Custom::StorPoolPlugin;

use v5.16;

use strict;
use warnings;
use version; our $VERSION = version->declare("v0.5.2");

use Carp qw/carp croak confess shortmess longmess/;
use Config::IniFiles;
use Data::Dumper;
use File::Path;
use Sys::Hostname;
use Sys::Syslog 'syslog';
use List::Util 'first';
use Time::HiRes 'time';
use JSON;
use LWP::UserAgent;
use LWP::Simple;

use PVE::Storage;
use PVE::Storage::Plugin;
use PVE::JSONSchema 'get_standard_option';

use base qw(PVE::Storage::Plugin);

# NOTE use shift instead @_ for parameters. Better to drain @_ and set default
# values. See PBP for more info
# And in the same spirit - do not use prototypes, see again PBP

my ($RE_DISK_ID, $RE_GLOBAL_ID, $RE_PROXMOX_ID, $RE_VM_ID);
BEGIN {
    $RE_DISK_ID = '(?: 0 | [1-9][0-9]* )';
    $RE_GLOBAL_ID = '[a-z0-9]+ \. [a-z0-9]+ \. [a-z0-9]+';
    $RE_PROXMOX_ID = '[a-z] [a-z0-9_.-]* [a-z0-9]';
    $RE_VM_ID = '[1-9][0-9]*';
}

# The volume tags that we look for and set
use constant {
    HTTP_TIMEOUT     => 30 * 60, # In seconds - 30 min
    HTTP_TOTAL_TIMEOUT=> 30 * 60,# Timeout including retries
    HTTP_RETRY_COUNT => 3, # How much retries after timeout/cant connect
    HTTP_RETRY_TIME  => 3, # How much to wait before retry in seconds
    VTAG_VIRT	     => 'virt',
    VTAG_LOC	     => 'pve-loc',
    VTAG_STORE	     => 'pve',
    VTAG_TYPE	     => 'pve-type',
    VTAG_VM	     => 'pve-vm',
    VTAG_DISK	     => 'pve-disk',
    VTAG_BASE	     => 'pve-base',
    VTAG_COMMENT     => 'pve-comment',
    VTAG_SNAP	     => 'pve-snap',
    VTAG_SNAP_PARENT => 'pve-snap-v',
    VTAG_V_PVE	     => 'pve',

    RE_NAME_GLOBAL_ID => qr{
	^
	[~]
	(?P<global_id> $RE_GLOBAL_ID )
	$
    }x,

    RE_VOLNAME_ISO => qr{
	^
	(?P<comment> .* )
	-sp- (?P<global_id> $RE_GLOBAL_ID )
	\.iso
	$
    }x,
    RE_VOLNAME_IMG => qr{
	^
	img
	- (?P<comment> .* )
	-sp- (?P<global_id> $RE_GLOBAL_ID )
	\.raw
	$
    }x,
    RE_VOLNAME_SNAPSHOT => qr{
	^
	snap
	- (?P<vm_id> $RE_VM_ID )
	-disk- (?P<disk_id> $RE_DISK_ID )
	- (?P<snapshot> $RE_PROXMOX_ID )
	-p- (?P<parent_id> $RE_GLOBAL_ID )
	-sp- (?P<global_id> $RE_GLOBAL_ID )
	\.raw
	$
    }x,
    RE_VOLNAME_VMSTATE => qr{
	^
	snap
	- (?P<vm_id> $RE_VM_ID )
	-state
	- (?P<snapshot> $RE_PROXMOX_ID )
	-sp- (?P<global_id> $RE_GLOBAL_ID )
	\.raw
	$
    }x,
    RE_VOLNAME_BASE => qr{
	^
	base
	- (?P<vm_id> $RE_VM_ID )
	-disk- (?P<disk_id> $RE_DISK_ID )
	-sp- (?P<global_id> $RE_GLOBAL_ID )
	\.raw
	$
    }x,
    RE_VOLNAME_DISK => qr{
	^
	vm
	- (?P<vm_id> $RE_VM_ID )
	-disk- (?P<disk_id> $RE_DISK_ID )
	-sp- (?P<global_id> $RE_GLOBAL_ID )
	\.raw
	$
    }x,
    RE_VOLNAME_CLOUDINIT => qr{
	^
	vm
	- (?P<vm_id> $RE_VM_ID )
	-cloudinit(-sp- (?P<global_id> $RE_GLOBAL_ID ))?
	\.raw
	$
    }x,

    RE_VOLNAME_PROXMOX_VMSTATE => qr{
	^
	vm
	- (?P<vm_id> $RE_VM_ID )
	-state
	- (?P<snapshot> $RE_PROXMOX_ID )
	(?: \.raw )?
	$
    }x,

    RE_FS_PATH => qr{
	^
	(
	/dev/storpool-byid/
	$RE_GLOBAL_ID
	)
	$
    }x,

    SP_PVE_Q_LOG => '/var/log/storpool/pve-storpool-query.log',
};

my $SP_VERS = '1.0';

#TODO upload same iso on two storpool templates (test)
#TODO disks list shows iso files from other templates
#TODO disks list shows saved states



sub log_and_die {
    my $msg = shift // "Missing message!";

    DEBUG( $msg );
    syslog 'err', 'StorPool plugin: %s', $msg;
    croak "$msg\n";
}

sub log_info {
    my $msg = shift // '';

    DEBUG( $msg );
    syslog 'info', 'StorPool plugin: %s', $msg;
}

sub debug_info {
    my $msg = shift // '';

    DEBUG( $msg );
    syslog 'info', 'StorPool plugin: %s', longmess($msg);
}

sub debug_die {
    my $msg = shift // '';

    DEBUG( $msg );
    syslog 'err', 'StorPool plugin: %s', longmess($msg);
    confess "$msg\n";
}

# Debug [trace] to file
# Usage DEBUG("Message, data %s, %s", {data=>123}, [1])
# create proxmox.conf file in /etc/storpool.conf.d/
# define _SP_PVE_DEBUG=[012] 0 disable 1 log 2 trace
# define _SP_PVE_DEBUG_PATH=IO::Path path to the file - pref /var/log/storpool/
# NOTE file is not locked, so concurrent writes may lead to messy messages
# NOTE configuration is cached, so you must restart the services on change
# NOTE function is disabled during the unit tests
# XXX DON'T use any other debug function here - beware of recursion
sub DEBUG {
    return if $ENV{PLUGIN_TEST}; # during the tests sp_confget is unavailable
    my $msg	  = shift // 'Empty message';
    my $data	  = [ @_ ];
    state $config = { sp_confget() };
    state $timing = time(); # Time of last call
    my $time	  = time(); # Time now, must be hi-res
    my $duration  = sprintf("%.4f", $time - $timing);

    $timing = $time;

    # Reload config if last debug was more than 10 sec ago
    if( $duration > 10 ) {
	$config = { sp_confget() };
    }

    return if !$config || ref($config) ne 'HASH';

    my $lvl	  = $config->{_SP_PVE_DEBUG};
    my $path	  = $config->{_SP_PVE_DEBUG_PATH};

    return if !$lvl;
    confess("Missing debug path, set _SP_PVE_DEBUG_PATH and restart") if !$path;
    confess("Message must be a string") if ref($msg);

    ($path) = ( $path =~ m{^((?:/[\w\-]+)*[\w\-]+\.\w+)$} );

    confess("Invalid path '$config->{_SP_PVE_DEBUG_PATH}'. Try with /var/log/storpool/debug.log")
	if !$path;

    if( scalar(@$data) ) {
        $msg = sprintf($msg, 
	    map{ Data::Dumper->new([$_])->Terse(1)->Indent(0)->Dump } @$data )
    }

    if( $lvl eq '1' ){
	$msg = shortmess($msg);
    } else {
	$msg = longmess($msg);
    }

    $msg = _localtime_human() . " [$$] took $duration: " . $msg . "\n";

    open( my $fh, '>>', $path ) 
	or confess("Failed to open debug file '$path' for writing: '$!'");

    print $fh $msg or confess("Failed to write to '$path'");
    close $fh or confess("Failed to flush write to '$path'");
}

# Get the localtime and return ISO 8601 date including milliseconds
# Returns %Y-%m-%d %H:%M:%S.%4f
sub _localtime_human {
    my @data = localtime();
    my $time = time();
    my $ms   = sprintf("%04d", ($time - int($time)) * 10000);

    return sprintf("%4d-%02d-%02d %02d:%02d:%02d.%04d", 
	$data[5] + 1900, $data[4], $data[3], $data[2], $data[1], $data[0], $ms);
}

sub _get_caller_args {
    my $caller_num = shift // die "Missing caller position";
    my %call_info;

    $caller_num += 1; # Here we are already 1 lvl deeper, so jump back 1 lvl back

    my $cgc = sub {
	no strict 'refs';
	return \&{"CORE::GLOBAL::caller"} if defined &{"CORE::GLOBAL::caller"};
	return;
    };

    {
    @DB::args = \$caller_num;
    package DB;
    @call_info{ qw(pack file line sub has_args wantarray evaltext is_require) } 
	= $cgc->() ? $cgc->($caller_num) : caller($caller_num);
    }

    if( $call_info{has_args} ){
	my @args = map {
	    my $arg;
	    local $@ = $@;
	    eval { $arg = $_; 1 } or do { $arg = 'not available anymore' };
	    $arg;
	    } @DB::args;
	if( 
	    "$]" >= 5.015002 && @args == 1 && ref($args[0]) eq ref \$caller_num
	    && $args[0] == \$caller_num
	) {
	    @args = ();
	    warn '@DB::args not set';
	}

	return @args;
    }
    return;
}

sub _get_migration_source_node {
    for( 0..10 ) {
	my @args = _get_caller_args( $_ );
	next if !scalar(@args);
	my $found = [ map { $_->{migratedfrom} }
	    grep { ref($_) && ref($_) eq 'HASH' && $_->{migratedfrom} } @args ];

	return $found->[0] if $found->[0];
    }
    return;
}


sub sp_request_timeouted {
    my $response = shift // return undef;

    return $response && ref($response) eq 'HASH' && $response->{error}
	&& $response->{error}->{reason}
	&& $response->{error}->{reason} eq 'timeouted'
}

# Retry a request, see HTTP_RETRY_COUNT HTTP_RETRY_TIME HTTP_TOTAL_TIMEOUT
# It makes HTTP_RETRY_COUNT retries after a request fails to connect or timeouts
# HTTP_RETRY_TIME is the wait time before each retry
# HTTP_TOTAL_TIMEOUT is a timeout including the retries, the idea is to have a
# reasonable timeout if the main HTTP_TIMEOUT is too long as it can multiply it!
sub sp_request_retry {
    my $code	 = shift // debug_die("Missing code to exec");
    my $retry	 = HTTP_RETRY_COUNT;
    my $timeout  = HTTP_TIMEOUT;
    my $ret_time = HTTP_RETRY_TIME;
    my $start	 = time();
    my $data	 = $code->(); # First request
    my $duration = time() - $start;

    debug_die("Missing code to exec")	    if ref($code) ne 'CODE';
    debug_die("Timeouted after $duration")  if $duration >= HTTP_TOTAL_TIMEOUT;
    return $data			    if !sp_request_timeouted($data);

    while (sp_request_timeouted($data) && $retry > 0) {
	sleep($ret_time);
	my $st1	  = time();
	$data	  = $code->(); # request runs here
	$duration = time() - $st1;
	my $total_duration = time() - $start;
	debug_die("Timeouted after $duration") if $duration >= $timeout;
	debug_die("Timeouted after $total_duration")
	    if $total_duration >= HTTP_TOTAL_TIMEOUT;
	$retry--;
    }
    debug_die('Timeout connecting after '.HTTP_RETRY_COUNT.' tries')
	if sp_request_timeouted($data);

    return $data;
}

# Wrapper functions for the actual request
sub sp_get {
    my $cfg   = shift;
    my $addr  = shift // debug_die("Missing GET address");

    DEBUG("GET $addr");

    return sp_request_retry( sub {
	sp_request($cfg, 'GET', $addr, undef);
    });
}

sub sp_post {
    my $cfg    = shift;
    my $addr   = shift // debug_die("Missing POST address");
    my $params = shift;

    DEBUG("POST $addr: '%s'", $params);

    return sp_request_retry( sub {
	sp_request($cfg, 'POST', $addr, $params);
    });
}

sub sp_request_log_response {
    my $method	 = shift // 'GET';
    my $addr	 = shift // 'Missing API address!';
    my $response = shift // 'Missing response';
    my $duration = shift // 0;
    my $outf;

    open($outf, '>>', SP_PVE_Q_LOG) or do {
	carp "Could not open the ".SP_PVE_Q_LOG." logfile: $!\n";
	return;
    };
    my $content = $response->decoded_content;
    chomp $content;
    say $outf gmtime()." [$$] Q " . sprintf("%.3f", $duration) .
	    "s $method $addr ".$response->code.' '.substr($content, 0, 1024).
	    (length($content) > 1024 ? '...' : '') or
	    carp("Could not append to the ".SP_PVE_Q_LOG." logfile: $!\n");
    close $outf
	or carp "Could not close the "
	    . SP_PVE_Q_LOG . " logfile after appending to it: $!\n";
}

# HTTP request to the storpool api
sub sp_request {
    my $cfg     = shift;
    my $method  = shift // 'GET';
    my $addr    = shift // debug_die('Missing address for API');
    my $params  = shift;

    return if ${^GLOBAL_PHASE} eq 'START';

    my $h = HTTP::Headers->new;
    $h->header('Authorization' => 'Storpool v1:'.$cfg->{api}->{auth_token});

    my $p = HTTP::Request->new($method, $cfg->{api}->{url}.$addr, $h);
    $p->content( encode_json( $params ) ) if defined $params;

    my $ua = LWP::UserAgent->new( timeout => HTTP_TIMEOUT );

    my $start	 = time();
    my $response = $ua->request($p);
    my $duration = time() - $start;

    sp_request_log_response($method, $addr, $response, $duration);

    DEBUG("RESULT: %s %s %s %s", $method, $addr, $response, $duration);

    if ($response->code eq "200"){
	undef $@;
	my $data = eval { decode_json($response->content) };
	if (!defined $data){
	    my $type  = $response->content ? 'Failed to decode' : 'Missing content';
	    my $error = "$type response: " . ($@||'Unknown error');
	    debug_info("$type API '$addr': $error");
	    $data = { error => { descr => $error } };
	}
	return $data;
    } else {
	undef $@;
	# this might break something
	my $res	    = eval { decode_json($response->content) };
	my $reason  = $response->header('client-warning') || '';

	$reason = 'timeouted' if $reason && $reason eq 'Internal response';

	if (!defined $res && $@) {
	    debug_info("Failed to decode response for $method $addr : $@");
	}
	if( $res && ref($res) eq 'HASH' && $res->{error} ){
	    my $err = ref $res->{error} eq 'HASH'
		? $res->{error}->{descr}
		: !ref($res->{error}) ? $res->{error} : 'Unknown error' ;
	    debug_info("$method $addr ".$response->code." error: $err");
	    return $res;
	} elsif (defined $res) {
	    debug_info("$method $addr ".$response->code." Unknown error");
	}
	return {
	    error => {
		descr => 'Error code: '.$response->code, code => $response->code,
		reason => $reason
	    }
	};
    }
}

sub sp_vol_create($$$$;$){
    my ($cfg, $size, $template, $ignoreError, $tags) = @_;

    my $req = {
	template => $template,
	size => $size,
	(defined($tags) ? (tags => $tags) : ())
    };
    my $res = sp_post($cfg, "VolumeCreate", $req);

    log_and_die($res->{error}->{descr}) if !$ignoreError && $res->{error};
    return $res
}

sub sp_vol_status($) {
    my $cfg = shift;

    my $res = sp_get($cfg, "VolumesGetStatus");

    # If there is an error here it's fatal, we do not check.
    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_volsnap_list($) {
    my $cfg = shift;

    my $res = sp_get($cfg, "VolumesAndSnapshotsList");

    # If there is an error here it's fatal, we do not check.
    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_volsnap_list_with_cache($$) {
    my $cfg   = shift;
    my $cache = shift;

    # pp: this will probably need another level for a multicluster setup some day
    $cache->{storpool}->{volsnap} //= sp_volsnap_list($cfg);
    $cache->{storpool}->{volsnap}
}

sub sp_vol_list($) {
    my $cfg = shift;
    my $res = sp_get($cfg, "VolumesList");

    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_vol_info($$) {
    my $cfg	  = shift;
    my $global_id = shift;

    my $res = sp_get($cfg, "Volume/~$global_id");

    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_vol_info_single($$) {
    my $cfg	  = shift;
    my $global_id = shift;

    my $res = sp_vol_info($cfg, $global_id);
    if (
	!defined($res->{'data'})
	|| ref($res->{'data'}) ne 'ARRAY'
	|| @{$res->{'data'}} != 1
    ) {
	log_and_die("Internal StorPool error: expected exactly one volume with"
	    ." the $global_id global ID, got ".Dumper($res));
    }
    $res->{'data'}->[0]
}

sub sp_snap_info_single($$) {
    my $cfg	  = shift;
    my $global_id = shift;

    my $res = sp_snap_info($cfg, $global_id);
    if (
	!defined($res->{'data'})
	|| ref($res->{'data'}) ne 'ARRAY'
	|| @{$res->{'data'}} != 1
    ) {
	log_and_die("Internal StorPool error: expected exactly one snapshot with"
	    ." the $global_id global ID, got ".Dumper($res));
    }
    $res->{data}->[0]
}

sub sp_snap_list($) {
    my $cfg = shift;

    my $res = sp_get($cfg, "SnapshotsList");

    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_attach_list($) {
    my $cfg = shift;
    my $res = sp_get($cfg, "AttachmentsList");

    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_snap_info($$) {
    my $cfg	 = shift;
    my $snapname = shift;

    my $res = sp_get($cfg, "Snapshot/~$snapname");
    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_disk_list($) {
    my $cfg = shift;

    my $res = sp_get($cfg, "DisksList");

    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_temp_get($$) {
    my $cfg  = shift;
    my $name = shift;

    my $res = sp_get($cfg, "VolumeTemplateDescribe/$name");

    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

sub sp_temp_status($) {
    my $cfg = shift;

    my $res = sp_get($cfg, "VolumeTemplatesStatus");

    # If there is an error here it's fatal, we do not check.
    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res;
}

#TODO, if adding more nodes, iso need to be attached to them as well
sub sp_vol_attach($$$$$;$$) {
    my $cfg		 = shift;
    my $global_id	 = shift;
    my $spid		 = shift;
    my $perms		 = shift;
    my $ignoreError	 = shift;
    my $is_snapshot	 = shift;
    my $force_detach_all = shift;
    my $keyword		 = $is_snapshot ? 'snapshot' : 'volume';
    my $res;
    my $req		 = [{
	$keyword => "~$global_id",
	$perms => [ $spid ],
	( $force_detach_all ? (detach => 'all', force => JSON::true) : () ),
    }];

    $res = sp_post($cfg, "VolumesReassignWait", $req);

    if (!$ignoreError && $res->{error}){
	log_and_die(
	    "$global_id, $spid, $perms, $ignoreError: ".$res->{error}->{descr}
	)
    }

    return $res
}

sub sp_vol_detach($$$$;$) {
    my $cfg	    = shift;
    my $global_id   = shift;
    my $spid	    = shift;
    my $ignoreError = shift;
    my $is_snapshot = shift;

    my $req;
    my $keyword = $is_snapshot ? 'snapshot' : 'volume';
    if ($spid eq "all"){
	$req = [{ $keyword => "~$global_id", detach => $spid, force => JSON::false }];
    } else {
	$req = [{ $keyword => "~$global_id", detach => [$spid], force => JSON::false }];
    }
    my $res = sp_post($cfg, "VolumesReassignWait", $req);

    log_and_die( $res->{error}->{descr} ) if !$ignoreError && $res->{error};
    return $res
}

sub sp_vol_del($$$) {
    my $cfg	    = shift;
    my $global_id   = shift;
    my $ignoreError = shift;

    my $req = {};
    my $res = sp_post($cfg, "VolumeDelete/~$global_id", $req);

    log_and_die($res->{error}->{descr})	if !$ignoreError && $res->{error};
    return $res
}

sub sp_vol_from_snapshot ($$$;$) {
    my $cfg	    = shift;
    my $global_id   = shift;
    my $ignoreError = shift;
    my $tags	    = shift;

    my $req = { parent => "~$global_id", tags => $tags // '' };
    my $res = sp_post($cfg, "VolumeCreate", $req);

    log_and_die($res->{error}->{descr}) if !$ignoreError && $res->{error};
    return $res
}

sub sp_vol_from_parent_volume ($$$;$) {
    my $cfg	    = shift;
    my $global_id   = shift;
    my $ignoreError = shift;
    my $tags	    = shift;

    my $req = { 'baseOn' => "~$global_id", 'tags' => $tags // '' };
    my $res = sp_post($cfg, "VolumeCreate", $req);

    log_and_die($res->{error}->{descr})	if !$ignoreError && $res->{error};
    return $res
}

# Currently only used for resize
sub sp_vol_update ($$$$) {
    my $cfg	    = shift;
    my $global_id   = shift;
    my $req	    = shift;
    my $ignoreError = shift;

    my $res = sp_post($cfg, "VolumeUpdate/~$global_id", $req);

    log_and_die($res->{error}->{descr})	if !$ignoreError && $res->{error};
    return $res
}

sub sp_vol_desc($$) {
    my $cfg	  = shift;
    my $global_id = shift;

    my $res = sp_get($cfg, "VolumeDescribe/~$global_id");

    log_and_die($res->{error}->{descr}) if $res->{error};

    return $res
}

sub sp_find_cloudinit_vol ($$) {
    my $cfg  = shift;
    my $vmid = shift;
    my ($newest, $vol_ci) = 0, undef;
    my $volumes = sp_vol_list($cfg);

    foreach my $vol ( @{ $volumes->{data} } ) {
	next unless
	    sp_vol_tag_is($vol, VTAG_VIRT, VTAG_V_PVE)
	    && sp_vol_tag_is($vol, VTAG_LOC, sp_get_loc_name($cfg))
	    && sp_vol_tag_is($vol, VTAG_VM, $vmid)
	    && sp_vol_tag_is($vol, VTAG_TYPE, 'images')
	    && sp_vol_tag_is($vol, VTAG_DISK, 'cloudinit');
	if ($vol->{creationTimestamp} > $newest) {
	    $newest = $vol->{creationTimestamp};
	    $vol_ci = $vol;
	}
    }
    return $vol_ci;
}

sub sp_services_list($) {
    my $cfg = shift;

    my $res = sp_get($cfg, "ServicesList");
    return $res;
}

sub sp_vol_snapshot($$$;$) {
    my $cfg	    = shift;
    my $global_id   = shift;
    my $ignoreError = shift;
    my $tags	    = shift;

    # my $req = { 'name' => $snap };
    my $req = { tags => $tags // {}, };
    my $res = sp_post($cfg, "VolumeSnapshot/~$global_id", $req);

    log_and_die($res->{error}->{descr}) if !$ignoreError && $res->{error};
    return $res
}

sub sp_snap_del($$$) {
    my $cfg	    = shift;
    my $global_id   = shift;
    my $ignoreError = shift;

    my $req = {};
    my $res = sp_post($cfg, "SnapshotDelete/~$global_id", $req);

    log_and_die($res->{error}->{descr}) if !$ignoreError && $res->{error};
    return $res
}

sub sp_placementgroup_list($$) {
    my $cfg = shift;
    my $pg  = shift;

    my $res = sp_get($cfg, "PlacementGroupDescribe/$pg");

    log_and_die($res->{error}->{descr}) if $res->{error};
    return $res;
}

sub sp_client_sync($$) {
    my $cfg	  = shift;
    my $client_id = shift;

    my $res = sp_get($cfg, "ClientConfigWait/$client_id");

    log_and_die($res->{error}->{descr}) if $res->{error};
    return $res;
}

sub sp_vol_revert_to_snapshot($$$) {
    my $cfg	= shift;
    my $vol_id  = shift;
    my $snap_id = shift;

    my $req = { 'toSnapshot' => "~$snap_id", 'revertSize' => JSON::true };
    my $res = sp_post($cfg, "VolumeRevert/~$vol_id", $req);

    log_and_die($res->{error}->{descr}) if $res->{error};
    return $res
}

sub sp_snap_not_gone($) {
    my $snap = shift // {};
    my $name = $snap->{name} // '';
    return substr($name, 0, 1) ne '*'
}

sub sp_is_ours($$%) {
    my ($cfg, $vol, %named) = @_;

    sp_vol_tag_is($vol, VTAG_VIRT, VTAG_V_PVE)
    && sp_vol_tag_is($vol, VTAG_LOC, sp_get_loc_name($cfg))
    && (
	$named{'any_storage'}
	|| sp_vol_tag_is($vol, VTAG_STORE, $cfg->{storeid})
	)
}

sub sp_volume_find_snapshots($$$) {
    my $cfg  = shift;
    my $vol  = shift;
    my $snap = shift;

    grep {
	sp_snap_not_gone($_)
	&& sp_is_ours($cfg, $_)
	&& sp_vol_tag_is($_, VTAG_SNAP_PARENT, $vol->{globalId})
	&& (
	    !defined($snap)
	    || sp_vol_tag_is($_, VTAG_SNAP, $snap)
	    )
    } @{ sp_snap_list($cfg)->{data} }
}

# Delete all snapshot that are parents of the volume provided
sub sp_clean_snaps($$) {
    my $cfg = shift;
    my $vol = shift;

    for my $snap_obj (sp_volume_find_snapshots($cfg, $vol, undef)) {
	sp_snap_del($cfg, $snap_obj->{globalId}, 0);
    }
}

# Various name encoding helpers and utility functions

# Get the value of a tag for a volume.
#
# Returns an undefined value if the volume does not have that tag.
sub sp_vol_get_tag($ $) {
    my $vol = shift;
    my $tag = shift;

    ${$vol->{tags} // {}}{$tag}
}

# Check whether a volume has the specified tag, and that its value is as expected.
sub sp_vol_tag_is($ $ $) {
    my $vol	 = shift;
    my $tag	 = shift;
    my $expected = shift;
    my $value	 = sp_vol_get_tag($vol, $tag);

    defined($value) && $value eq $expected
}

# Check whether a content type denotes an image, either of a VM or of a container.
sub sp_type_is_image($) {
    my $type = shift // '';

    $type eq 'images' || $type eq 'rootdir'
}

sub sp_is_empty($) {
    my $value = shift;

    return 1 if !defined $value || $value eq '';
    return 0;
}

sub sp_encode_volsnap_from_tags($) {
    my $vol  = shift;
    my %tags = %{$vol->{tags}};

    my $global_id = do {
	if ($vol->{snapshot}) {
	    $vol->{globalId}
	} else {
	    if ($vol->{name} !~ RE_NAME_GLOBAL_ID) {
		log_and_die(
		    'Only unnamed StorPool volumes supported: '.Dumper($vol)
		    );
	    }
	    $+{'global_id'}
	}
    };

    if ($tags{VTAG_TYPE()} eq 'iso') {
	if (
	    !sp_is_empty($tags{VTAG_VM()})
	    || !sp_is_empty($tags{VTAG_BASE()})
	    || !sp_is_empty($tags{VTAG_SNAP()})
	    || !sp_is_empty($tags{VTAG_SNAP_PARENT()})
	) {
	    log_and_die 'An ISO image should not have the VM, base, snapshot, '
		.'or snapshot parent tags: '.Dumper($vol);
	}
	if (!$vol->{snapshot}) {
	    log_and_die 'An ISO image should be a StorPool snapshot: '.Dumper($vol);
	}

	return ($tags{VTAG_COMMENT()} // 'unlabeled')."-sp-$global_id.iso";
    }

    if (!sp_type_is_image($tags{VTAG_TYPE()})) {
	log_and_die 'Internal StorPool error: not an image: '.Dumper($vol);
    }

    if (!defined $tags{VTAG_VM()}) {
	if (
	    !sp_is_empty($tags{VTAG_BASE()})
	    || !sp_is_empty($tags{VTAG_SNAP()})
	    || !sp_is_empty($tags{VTAG_SNAP_PARENT()})
	) {
	    log_and_die 'A freestanding image should not have the base, '
		.'snapshot, or snapshot parent tags: '. Dumper($vol);
	}
	if (!$vol->{snapshot}) {
	    log_and_die 'A freestanding image should be a StorPool snapshot: '
		. Dumper($vol);
	}

	return 'img-'.($tags{VTAG_COMMENT()} // 'unlabeled')."-sp-$global_id.raw";
    }

    if ($tags{VTAG_BASE()}) {
	if (
	    !sp_is_empty($tags{VTAG_SNAP()})
	    || !sp_is_empty($tags{VTAG_SNAP_PARENT()})
	) {
	    log_and_die 'A base disk image should not have the snapshot or '
		.'snapshot parent tags: '. Dumper($vol);
	}
	if (!$vol->{snapshot}) {
	    log_and_die 'A base disk image should be a StorPool snapshot: '
		. Dumper($vol);
	}
	if (sp_is_empty($tags{VTAG_DISK()})) {
	    log_and_die 'A base disk image should specify a disk: '.Dumper($vol);
	}

	return "base-$tags{VTAG_VM()}-disk-$tags{VTAG_DISK()}-sp-$global_id.raw";
    }

    if ($tags{VTAG_SNAP()}) {
	if (sp_is_empty($tags{VTAG_DISK()})) {
	    log_and_die 'A disk or VM state snapshot should specify a disk: '
		. Dumper($vol);
	}

	if ($tags{VTAG_DISK()} eq 'state') {
	    if ($vol->{snapshot}) {
		log_and_die 'A VM state snapshot should be a StorPool volume: '
		    . Dumper($vol);
	    }

	    if (!sp_is_empty($tags{VTAG_SNAP_PARENT()})) {
		log_and_die 'A VM state snapshot should not have the snapshot '
		    .'parent tag: '.Dumper($vol);
	    }

	    return "snap-$tags{VTAG_VM()}-state-$tags{VTAG_SNAP()}-sp-$global_id.raw";
	}

	if (!$vol->{snapshot}) {
	    log_and_die 'A disk or VM state snapshot should be a StorPool '
		.'snapshot: '.Dumper($vol);
	}
	if (sp_is_empty($tags{VTAG_SNAP_PARENT()})) {
	    log_and_die 'A disk snapshot should have the snapshot parent tag: '
		. Dumper($vol);
	}

	return "snap-$tags{VTAG_VM()}-disk-$tags{VTAG_DISK()}".
	    "-$tags{VTAG_SNAP()}-p-$tags{VTAG_SNAP_PARENT()}-sp-$global_id.raw";
    }

    if ($vol->{snapshot}) {
	log_and_die 'A disk image should be a StorPool volume: '
	    . Dumper($vol);
    }
    if (sp_is_empty($tags{VTAG_DISK()})) {
	log_and_die 'A disk image should specify a disk: '.Dumper($vol);
    }
    if ($tags{VTAG_DISK()} eq 'cloudinit') {
	return "vm-$tags{VTAG_VM()}-cloudinit.raw";
    }

    return "vm-$tags{VTAG_VM()}-disk-$tags{VTAG_DISK()}-sp-$global_id.raw";
}

sub sp_decode_volsnap_to_tags($$) {
    my $volname = shift;
    my $cfg	= shift;
    if ($volname =~ RE_VOLNAME_ISO) {
	my ($comment, $global_id) = ($+{comment}, $+{global_id});
	return {
	    name     => "~$global_id",
	    snapshot => JSON::true,
	    globalId => $global_id,
	    tags     => {
		VTAG_TYPE() => 'iso',
		VTAG_COMMENT() => $comment,
	    },
	};
    }

    if ($volname =~ RE_VOLNAME_IMG) {
	my ($comment, $global_id) = ($+{comment}, $+{global_id});
	return {
	    name     => "~$global_id",
	    snapshot => JSON::true,
	    globalId => $global_id,
	    tags     => {
		VTAG_TYPE() => 'images',
		VTAG_COMMENT() => $comment,
	    },
	};
    }

    if ($volname =~ RE_VOLNAME_SNAPSHOT) {
	my ($disk_id, $global_id, $parent_id, $snapshot, $vm_id)
	    = ($+{disk_id}, $+{global_id}, $+{parent_id}, $+{snapshot}, $+{vm_id});
	return {
	    name     => "~$global_id",
	    snapshot => JSON::true,
	    globalId => $global_id,
	    tags     => {
		VTAG_TYPE() => 'images',
		VTAG_VM()   => $vm_id,
		VTAG_DISK() => $disk_id,
		VTAG_SNAP() => $snapshot,
		VTAG_SNAP_PARENT() => $parent_id,
	    },
	};
    }

    if ($volname =~ RE_VOLNAME_VMSTATE) {
	my ($global_id, $snapshot, $vm_id) = ($+{global_id}, $+{snapshot}, $+{vm_id});
	return {
	    name     => "~$global_id",
	    snapshot => JSON::false,
	    globalId => $global_id,
	    tags     => {
		VTAG_TYPE() => 'images',
		VTAG_VM()   => $vm_id,
		VTAG_DISK() => 'state',
		VTAG_SNAP() => $snapshot,
	    },
	};
    }

    if ($volname =~ RE_VOLNAME_BASE) {
	my ($disk_id, $global_id, $vm_id) = ($+{disk_id}, $+{global_id}, $+{vm_id});
	return {
	    name     => "~$global_id",
	    snapshot => JSON::true,
	    globalId => $global_id,
	    tags     => {
		VTAG_TYPE() => 'images',
		VTAG_VM()   => $vm_id,
		VTAG_DISK() => $disk_id,
		VTAG_BASE() => JSON::true,
	    },
	};
    }

    if ($volname =~ RE_VOLNAME_DISK) {
	my ($disk_id, $global_id, $vm_id) = ($+{disk_id}, $+{global_id}, $+{vm_id});
	return {
	    name     => "~$global_id",
	    snapshot => JSON::false,
	    globalId => $global_id,
	    tags     => {
		VTAG_TYPE() => 'images',
		VTAG_VM()   => $vm_id,
		VTAG_DISK() => $disk_id,
	    },
	};
    }

    if ($volname =~ RE_VOLNAME_CLOUDINIT) {
	my ($global_id, $vm_id) = ($+{global_id}, $+{vm_id});
	if (!defined $global_id) {
	    my $vol = sp_find_cloudinit_vol($cfg, $vm_id);
	    $global_id = $vol->{globalId} || '';
	}
	return {
	    name     => "~$global_id",
	    snapshot => JSON::false,
	    globalId => $global_id,
	    tags     => {
		VTAG_TYPE() => 'images',
		VTAG_VM()   => $vm_id,
		VTAG_DISK() => 'cloudinit',
	    },
	};
    }

    log_and_die "Internal StorPool error: don't know how to decode "
	. Dumper(\$volname);
}

sub cfg_format_version($) {
    my $raw  = shift;
    my $sect = $raw->{'format.version'};

    if (!defined $sect || ref $sect ne 'HASH') {
	die "No [$sect] section\n";
    }
    my ($major, $minor) = ($sect->{major}, $sect->{minor});
    if (!defined $major || !defined $minor) {
	die "Both $sect.major and $sect.minor must be defined\n";
    }
    if ($major !~ /^0 | (?: [1-9] [0-9]* )$/x || $minor !~ /^0 | (?: [1-9][0-9]* )$/x) {
	die "Both $sect.major and $sect.minor must be non-negative decimal numbers\n";
    }
    return ($major, $minor);
}

# Get some storpool settings from storpool.conf and /etc/storpool.conf.d/
sub sp_confget() {
    my %res;
    open my $f, '-|', 'storpool_confget'
	or log_and_die "Could not run storpool_confget: $!";

    while (<$f>) {
	chomp;
	my ($var, $value) = split /=/, $_, 2;
	$res{$var} = $value;
    }
    return %res;
}

sub cfg_load_fmtver($ $ $) {
    my $fname = shift;
    my $major = shift;
    my $minor = shift;

    my %raw;
    tie %raw, 'Config::IniFiles', (
	-file => $fname,
	-allowcontinue => 1,
    ) or die "Could not read the $fname file: $@\n";
    my @fmtver;
    eval {
	@fmtver = cfg_format_version(\%raw);
    };
    if ($@) {
	my $msg = $@;
	die "The format version check failed for the $fname file: $msg\n";
    };
    if ($fmtver[0] != $major || $fmtver[1] != $minor) {
	die "Only format version 0.1 supported for the present for the $fname file\n";
    }
    return %raw;
}

sub cfg_parse_api() {
    my %raw = sp_confget();
    my ($host, $port, $auth_token, $ourid) = @raw{qw(
	SP_API_HTTP_HOST
	SP_API_HTTP_PORT
	SP_AUTH_TOKEN
	SP_OURID
    )};
    if (
	!defined $host
	|| !defined $port
	|| !defined $auth_token
	|| !defined $ourid
    ) {
	log_and_die 'Incomplete StorPool configuration; need host, port, '
	    . 'auth token, node id';
    }
    return {
	auth_token  => $auth_token,
	ourid	    => $ourid,
	url	    => "http://$host:$port/ctrl/$SP_VERS/",
    };
}

sub sp_cfg($$) {
    my $scfg    = shift;
    my $storeid = shift;

    return {
	api => cfg_parse_api(),
	proxmox => {
	    id => {
		name => PVE::Cluster::get_clinfo()->{'cluster'}->{'name'},
	    },
	},
	storeid => $storeid,
	scfg => $scfg,
    };
}

# Configuration

sub api {
    my $minver = 3;
    my $maxver = 11;

    # We kind of depend on the way `use constant` declares a function.
    # If we try to use barewords and not functions, the compiler will
    # throw a compile-time error, not a run-time one, which would
    # disable the whole plugin.

    my $apiver;
    eval {
	$apiver = PVE::Storage::APIVER();
    };
    if ($@) {
	# Argh, they don't even declare APIVER? Well... too bad.
	return $minver;
    }

    my $apiage;
    eval {
	$apiage = PVE::Storage::APIAGE();
    };
    if ($@) {
	# Hm, no APIAGE? OK, is their version within our range?
	if ($apiver >= $minver && $apiver <= $maxver) {
	    return $apiver;
	}

	# Ah well...
	return $minver;
    }

    # Is our version within their declared supported range?
    if ($apiver >= $maxver && $apiver <= $maxver + $apiage) {
	return $maxver;
    }

    # This is a bit of a lie, but, well...
    if ($apiver <= $maxver) {
	return $apiver;
    }

    # Oof. This is fun.
    return $minver;
}

# This is the most important method. The ID of the plugin
sub type {
    return 'storpool';
}

# The capabilities of the plugin
sub plugindata {

    return {
	content => [
	    { images => 1, rootdir => 1, iso => 1, backup => 1, none => 1 },
	    { images => 1, rootdir => 1 }
	],
	format => [ { raw => 1 } , 'raw' ],
    };
}

# The properties the plugin can handle
sub properties {

    return {
	'extra-tags' => {
	    description => 'Additional tags to add to the StorPool volumes and snapshots',
	    type => 'string',
	},
	'template' => {
	    description => 'The StorPool template to use, if different from the storage name',
	    type => 'string',
	},
    };
}

sub options {

    return {
	nodes	     => { optional => 1 },
	shared	     => { optional => 1 },
	disable	     => { optional => 1 },
	maxfiles     => { optional => 1 },
	content	     => { optional => 1 },
	format	     => { optional => 1 },
	'extra-tags' => { optional => 1 },
	template     => { optional => 1 },
   };
}

# Storage implementation

# Just check value before accepting the request
PVE::JSONSchema::register_format('pve-storage-replication', \&sp_parse_replication);
sub sp_parse_replication {
    my $rep   = shift;
    my $noerr = shift;

    if ($rep < 1 or $rep > 4) {
	return if $noerr;
	die "replication must be between 1 and 4\n";
    }

    return $rep;
}

# This creates the storpool template. It's called frequently though,
# so we ignore "already exists" errors
sub activate_storage {
    my $self	= shift;
    my $storeid = shift;
    my $scfg	= shift;
    my $cache	= shift;
    my $cfg	= sp_cfg($scfg, $storeid);

    DEBUG( "activate_storage: storeid: %s, scfg: %s , cache: %s", $storeid, $scfg, $cache );

    sp_temp_get($cfg, sp_get_template($cfg));
}

sub sp_get_tags($) {
    my $cfg = shift;

    my $extra_spec = $cfg->{scfg}->{'extra-tags'} // '';
    my %extra_tags = map { split /=/, $_, 2 } split /\s+/, $extra_spec;
    return (
	VTAG_VIRT()  => VTAG_V_PVE,
	VTAG_LOC()   => sp_get_loc_name($cfg),
	VTAG_STORE() => $cfg->{storeid},
	%extra_tags,
    );
}

sub sp_get_template($) {
    my $cfg = shift;

    return $cfg->{scfg}->{template} // $cfg->{storeid};
}

sub sp_get_loc_name($) {
    my $cfg = shift;

    return $cfg->{proxmox}->{id}->{name};
}

sub find_free_disk($ $) {
    my $cfg   = shift;
    my $vm_id = shift;

    # OK, maybe there might be a better way to do this some day...
    my $lst = sp_volsnap_list($cfg);
    my $disk_id = 0;
    for my $vol (@{$lst->{data}->{volumes}}) {
	next
	    unless sp_is_ours($cfg, $vol, any_storage => 1)
	    && ($vol->{tags}->{VTAG_VM()} // '') eq $vm_id;

	my $current_str = $vol->{tags}->{VTAG_DISK()};
	if (
	    defined $current_str
	    && $current_str ne 'state'
	    && $current_str ne 'cloudinit'
	) {
	    my $current = int $current_str;
	    if ($current >= $disk_id) {
		$disk_id = $current + 1;
	    }
	}
    }
    return $disk_id;
}

# Create the volume
# XXX $self is used for blessed objects, and $class for unblessed
sub alloc_image {
    my $self	= shift;
    my $storeid = shift;
    my $scfg	= shift;
    my $vmid	= shift;
    my $fmt	= shift;
    my $name	= shift;
    my $size	= shift;
    my $cfg	= sp_cfg($scfg, $storeid);

    DEBUG("alloc_image: storeid %s, scfg %s, vmid %s, fmt %s, name %s, size %s",
	$storeid, $scfg, $vmid, $fmt, $name, $size );
    # One of the few places where size is in K
    $size *= 1024;
    log_and_die("unsupported format '$fmt'") if $fmt ne 'raw';

    my %extra_tags = do {
	if (defined $name && $name =~ RE_VOLNAME_PROXMOX_VMSTATE) {
	    my ($state_snapshot, $state_vmid) = ($+{snapshot}, $+{vm_id});
	    if ($state_vmid ne $vmid) {
		log_and_die "Inconsistent VM snapshot state name: "
		    ."passed in VM id $vmid and name $name\n";
	    }

	    (
		VTAG_VM()   => $state_vmid,
		VTAG_DISK() => 'state',
		VTAG_SNAP() => $state_snapshot,
	    )
	} elsif (defined $name && $name =~ m/^vm-\d*-cloudinit/) {
	    (
		VTAG_VM()   => "$vmid",
		VTAG_DISK() => 'cloudinit',
	    )
	} elsif (defined $vmid) {
	    my $disk_id = find_free_disk($cfg, $vmid);
	    (
		VTAG_VM()   => "$vmid",
		VTAG_DISK() => "$disk_id",
	    )
	} else {
	    ()
	}
    };

    my $c_res = sp_vol_create($cfg, $size, sp_get_template($cfg), 0, {
	sp_get_tags($cfg),
	VTAG_TYPE() => 'images',
	%extra_tags,
    });
    my $global_id = ($c_res->{'data'} // {})->{'globalId'};
    if (!defined($global_id) || $global_id eq '') {
	log_and_die 'StorPool internal error: no globalId in the VolumeCreate'
	    .' API response: '.Dumper($c_res);
    }

    my $vol = sp_vol_info_single($cfg, $global_id);
    sp_vol_attach(
	$cfg,
	$vol->{globalId},
	$cfg->{api}->{ourid},
	'rw',
	0,
	$vol->{snapshot},
	1
    );
    my $result = sp_encode_volsnap_from_tags($vol);
    DEBUG('alloc_image result: %s', $result);
    return $result;
}

# Status of the space of the storage
sub status {
    my $self	= shift;
    my $storeid = shift;
    my $scfg	= shift;
    my $cache	= shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $name	= sp_get_template($cfg);
    my @ours = grep { $_->{name} eq $name} @{ sp_temp_status($cfg)->{data} };

    DEBUG( 'status: storeid %s, scfg %s, cache %s, name %s', $storeid, $scfg, $cache, $name );

    if (@ours != 1) {
	log_and_die "StorPool internal error: expected exactly one '$name' "
	    ."entry in the 'template status' output, got ".Dumper(\@ours);
    }

    my ($capacity, $free) =
	($ours[0]->{stored}->{capacity}, $ours[0]->{stored}->{free});
    DEBUG( 'status result: capacity %s, free %s', $capacity, $free );
    return ($capacity, $free, $capacity - $free, 1);
}

sub parse_volname ($;$) {
    my $self	= shift;
    my $volname = shift;
    my $cfg	= shift;

    DEBUG('parse_volname: volname %s, cfg %s', $volname, $cfg);
    # needed for decoding cloud-init volumes and not supplied by PVE::Storage
    $cfg //= sp_cfg(undef, undef);

    my $vol = sp_decode_volsnap_to_tags($volname, $cfg);

    DEBUG(
	'parse_volname result: vtype %s, name %s, vmid %s, basename %s, '
	    .'basevmid %s, isBase %s, format %s',
	$vol->{tags}->{VTAG_TYPE()},
	$vol->{globalId},
	$vol->{tags}->{VTAG_VM()},
	undef,
	undef,
	($vol->{tags}->{VTAG_BASE()} // '0') eq '1',
	'raw',	
    );
    return (
	$vol->{tags}->{VTAG_TYPE()},
	$vol->{globalId},
	$vol->{tags}->{VTAG_VM()},
	undef,
	undef,
	($vol->{tags}->{VTAG_BASE()} // '0') eq '1',
	'raw',
    )
}

sub filesystem_path {
    my $self	 = shift;
    my $scfg	 = shift;
    my $volname  = shift;
    my $snapname = shift;

    DEBUG('filesystem_path: scfg %s, volname %s, snapname %s',
	$scfg, $volname, $snapname);
    # tags->VTAG_TYPE, globalId, tags->VTAG_VM
    my ($vtype, $name, $vmid) = $self->parse_volname("$volname");

    log_and_die("Missing type '$vtype' volume '$volname'") if !$name;

    my $path = "/dev/storpool-byid/$name";
    if ($path =~ RE_FS_PATH) {
	$path = $1; # untaint name value coming from SP API
    } else {
	log_and_die("StorPool internal error: bad block device path $path");
    }

    DEBUG('filesystem_path result: path %s, vmid %s, vtype %s, is_array %s',
	$path, $vmid, $vtype, wantarray);
    return wantarray ? ($path, $vmid, $vtype) : $path;
}


# Returns the vmID's lock/hastate status
# return { lock => '', hastate => '' }
# PVE::API2::Cluster +404
sub get_vm_status {
    my $vmid	    = shift // debug_die("Missing vmid");

    my $tags	    = ['lock'];
    my $props	    = PVE::Cluster::get_guest_config_properties($tags) || {};
    my $hastatus    = PVE::HA::Config::read_manager_status()   || {service_status=>{}};
    my $haresources = PVE::HA::Config::read_resources_config() || {ids=>{}};
    my $vm_props    = $props->{ $vmid } || {};
    my $hatypemap   = { qw/qemu vm lxc ct/ };
    my $hastate	    = '';
    my $sid1	    = $hatypemap->{qemu} . ':' . $vmid;
    my $sid2	    = $hatypemap->{lxc}  . ':' . $vmid;

    my $hastate_sid = $hastatus->{service_status}->{$sid1}
	|| $hastatus->{service_status}->{$sid2}
	|| $haresources->{ids}->{$sid1}
	|| $haresources->{ids}->{$sid2}
	|| {};

    my $lock = $vm_props->{lock}     || '';
    $hastate = $hastate_sid->{state} || '';

    my $status = { lock => $lock, hastate => $hastate };
    log_info("VM $vmid parsed status: { lock => $lock, hastate => $hastate }");

    return $status;
}


sub activate_volume {
    my $self	    = shift;
    my $storeid	    = shift;
    my $scfg	    = shift;
    my $volname	    = shift;
    my $exclusive   = shift;
    my $cache	    = shift;
    my $cfg	    = sp_cfg($scfg, $storeid);
    my $path	    = $self->path($scfg, $volname, $storeid);
    my $vol	    = sp_decode_volsnap_to_tags($volname, $cfg);
    my $global_id   = $vol->{globalId};
    my $perms	    = $vol->{snapshot} ? 'ro' : 'rw';
    my $vmid	    = $vol->{tags}->{VTAG_VM()};
    my $force_detach = 0;
    my $src_node    = _get_migration_source_node() || '';

    DEBUG('activate_volume: storeid %s, src %s scfg %s, volname %s, exclusive %s',
	$storeid, $src_node, $scfg, $volname, $exclusive);

    if (!sp_is_empty($vmid)) {
	log_info("Volume $vol->{name} is related to VM $vmid, checking status");
	my $vm_status = $src_node ? get_vm_status($vmid) : {};
	if (
	    ($vm_status->{lock} // '') ne 'migrate'
	    && ($vm_status->{hastate} // '') ne 'migrate'
	) {
	    log_info("NOT a live migration of VM $vmid, will force detach "
		."volume $vol->{'name'}");
	    # VM status is not migrate, but is called from migration
	    # Can happen when the parent PID dies for some reason
	    # and the shared FS VM lock status is removed from the src node
	    log_and_die("Failed migration") if $src_node;
	    $force_detach = 1;
	} else {
	    log_info("Live migration of VM $vmid, will not force detach volume "
		. $vol->{name});
	}
    } else {
	log_info("Volume $vol->{'name'} is not related to a VM, not checking "
	    ."status");
    }

    # TODO: pp: remove this when the configuration goes into the plugin?
    sp_vol_attach(
	$cfg,
	$global_id,
	$cfg->{api}->{ourid},
	$perms,
	0,
	$vol->{snapshot},
	$force_detach
    );
    DEBUG('activate_volume done');
    if (!-e $path){
	log_and_die "Internal StorPool error: could not find the just-attached"
	    ." volume $global_id at $path"
    }
}

sub deactivate_volume {
    my $self	= shift;
    my $storeid = shift;
    my $scfg	= shift;
    my $volname = shift;
    my $cache	= shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $path	= $self->path($scfg, $volname, $storeid);

    DEBUG('deactivate_volume: storeid %s, scfg %s, volname %s, path %s, exist %s',
	$storeid, $scfg, $volname, $path, -b $path);
    return if ! -b $path;

    my $vol = sp_decode_volsnap_to_tags($volname, $cfg);
    my $global_id = $vol->{globalId};

    # TODO: pp: remove this when the configuration goes into the plugin?
    my $result = sp_vol_attach(
	$cfg, $global_id, $cfg->{api}->{ourid}, 'ro', 0, $vol->{snapshot}, 0);
    DEBUG('deactivate_volume result: %s', $result);
    return $result;
}

sub free_image {
    my $self	= shift;
    my $storeid = shift;
    my $scfg	= shift;
    my $volname = shift;
    my $is_base	= shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $vol	= sp_decode_volsnap_to_tags($volname, $cfg);
    my ($global_id, $is_snapshot) = ($vol->{globalId}, $vol->{snapshot});

    DEBUG('free_image: storeid %s, scfg %s, volname %s, is_base %s, vol %s',
	$storeid, $scfg, $volname, $is_base, $vol);
    # Volume could already be detached, we do not care about errors
    sp_vol_detach($cfg, $global_id, 'all', 1, $is_snapshot);

    if ($is_snapshot) {
	sp_snap_del($cfg, $global_id, 0);
    } else {
	sp_vol_del($cfg, $global_id, 0);
	sp_clean_snaps($cfg, $vol);
    }

    DEBUG('free_image done');
    return
}

sub volume_has_feature {
    my $self	 = shift;
    my $scfg	 = shift;
    my $feature  = shift;
    my $storeid  = shift;
    my $volname  = shift;
    my $snapname = shift;
    my $running  = shift;
    my $key	 = undef;

    DEBUG('volume_has_feature: scfg %s, feature %s, storeid %s, volname %s,'
	.'snapname %s, running %s',
	$scfg, $feature, $storeid, $volname, $snapname, $running);
    my $features = {
	snapshot    => { current => 1, snap => 1 },
	clone	    => { base => 1, current => 1, snap => 1 },
	template    => { current => 1 },
	rename	    => { current => 1, },
	sparseinit  => { base => 1, current => 1, snap => 1 },
	copy	    => { base => 1, current => 1, snap => 1 },
    };
    my ($vtype, $name, $vmid, , undef, undef, $isBase) =
	$self->parse_volname($volname, sp_cfg($scfg, $storeid));


    if ($snapname){
	$key = 'snap';
    } else {
	$key =  $isBase ? 'base' : 'current';
    }

    DEBUG('volume_has_feature result: has_feature? %s',
	$features->{$feature}->{$key} ? 1 : 0 );
    return 1 if defined $features->{$feature}->{$key};

    return;
}

#sub file_size_info {
#    my ($filename, $timeout) = @_;
#}

# We return the used volume space equal to the volume size because the API calls
# to get the actual used space (e.g. VolumesSpace or VolumesGetStatus) are way
# too slow, and can timeout issues. Caching them across the PVE cluster also
# appears to be a non-trivial amount of work.
sub volume_size_info {
    my $self	= shift;
    my $scfg	= shift;
    my $storeid = shift;
    my $volname = shift;
    my $timeout = shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $vol	= sp_decode_volsnap_to_tags($volname, $cfg);
    my $vol_desc;

    DEBUG('volume_size_info: scfg %s, storeid %s, volname %, timeout %s',
	$scfg, $storeid, $volname, $timeout);

    if( $vol->{snapshot} ) {
	$vol_desc = sp_snap_info_single($cfg, $vol->{globalId});
    } else {
	$vol_desc = sp_vol_desc($cfg, $vol->{globalId})->{data};
    }

    # Right. So Proxmox seems to need these to be validated.
    my $size = $vol_desc->{size};
    if ($size =~ /^ (?P<size> 0 | [1-9][0-9]* ) $/x) {
	$size = $+{size};
    } else {
	log_and_die "Internal error: unexpected size '$size' for $volname";
    }

    DEBUG('volume_size_info result: size %s, type raw', $size);

    # TODO: pp: do we ever need to support anything other than 'raw' here?
    return wantarray ? ($size, 'raw', $size, undef) : $size;
}

sub list_volumes_with_cache {
    my $self	  = shift;
    my $storeid   = shift;
    my $scfg	  = shift;
    my $vmid	  = shift;
    my $content_types = shift;
    my $cache	  = shift;
    my $cfg	  = sp_cfg($scfg, $storeid);
    my %ctypes    = map { $_ => 1 } @{$content_types};
    my $volStatus = sp_volsnap_list_with_cache($cfg, $cache);
    my $res	  = [];

    DEBUG(
	'list_volumes_with_cache: storeid %s,scfg %s,vmid %s,content-types %s',
	$storeid, $scfg, $vmid, $content_types);

    for my $vol (@{$volStatus->{data}->{volumes}}) {
	next if !sp_is_ours($cfg, $vol);
	my $v_type = sp_vol_get_tag($vol, VTAG_TYPE);
	next unless defined($v_type) && exists $ctypes{$v_type};

	my $v_vmid = sp_vol_get_tag($vol, VTAG_VM);
	if (defined $vmid) {
	    next unless defined($v_vmid) && $v_vmid eq $vmid;
	}

	# TODO: pp: apply the rootdir/images fix depending on $v_vmid

	# TODO: pp: figure out whether we ever need to store non-raw data on StorPool
	my $data = {
	    volid   => "$storeid:".sp_encode_volsnap_from_tags($vol),
	    content => $v_type,
	    vmid    => $v_vmid,
	    size    => $vol->{size},
	    used    => $vol->{storedSize},
	    parent  => undef,
	    format  => 'raw',
	};
	push @{$res}, $data;
    }

    DEBUG('list_volumes_with_cache result: %s', $res);

    return $res;
}

sub list_volumes {
    DEBUG('list_volumes');
    return list_volumes_with_cache( @_, {} );
}

sub list_images {
    my $self	= shift;
    my $storeid = shift;
    my $scfg	= shift;
    my $vmid	= shift;
    my $vollist = shift;
    my $cache	= shift;

    DEBUG('list_images: storeid %s, scfg %s, vmid %s, vollist %s',
	$storeid, $scfg, $vmid, $vollist);
    if (defined $vollist) {
	log_and_die "TODO: list_images() with a volume list not implemented "
	    ."yet: ".Dumper(\$vmid, $vollist);
    }

    # pp: possibly optimize for the "only a single ID in @{$vollist}" case... maybe
    return $self->list_volumes_with_cache(
	$storeid, $scfg, $vmid, [keys %{$scfg->{content}}], $cache);
}

sub create_base {
    my $self	= shift;
    my $storeid = shift;
    my $scfg	= shift;
    my $volname = shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $vol	= sp_decode_volsnap_to_tags($volname, $cfg);
    my ($global_id, $vtype) = ($vol->{'globalId'}, $vol->{tags}->{VTAG_TYPE()});

    DEBUG('create_base: storeid %s, scfg %s, volname %s, vol %s',
	$storeid, $scfg, $volname, $vol);

    # my ($vtype, $name, $vmid, undef, undef, $isBase) =
	# $self->parse_volname($volname);
    log_and_die("create_base not possible with types other than images. '$vtype' given.\n")
	if $vtype ne 'images';

    log_and_die("create_base not possible with base image\n")
	if $vol->{tags}->{VTAG_BASE()};

    # my ($size, $format, $used, $parent) = $self->volume_size_info($scfg, $storeid, $volname, 0);
    # die "file_size_info on '$volname' failed\n" if !($format && $size);

    # die "volname '$volname' contains wrong information about parent\n"
	# if $isBase && !$parent;

    # my $newname = $name;
    # $newname =~ s/^vm-/base-/;

    my $current_tags = (
	$vol->{snapshot}
	    ? sp_snap_info_single($cfg, $vol->{globalId})
	    : sp_vol_info_single($cfg, $vol->{globalId})
    )->{tags} // {};

    my $snap_res = sp_vol_snapshot(
	$cfg, $global_id, 0, { %{$current_tags}, VTAG_BASE() => "1", });

    my $snap_id = $snap_res->{data}->{snapshotGlobalId};
    my $snap	= sp_snap_info_single($cfg, $snap_id);

    sp_vol_detach($cfg, $global_id, 'all', 0);
    sp_vol_del($cfg, $global_id, 0);

    my $result = sp_encode_volsnap_from_tags($snap);
    DEBUG('create_base result: name %s', $result);
    return $result;
}

sub clone_image {
    my $self	= shift;
    my $scfg	= shift;
    my $storeid = shift;
    my $volname = shift;
    my $vmid	= shift;
    my $snap	= shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $vol	= sp_decode_volsnap_to_tags($volname, $cfg);

    DEBUG('clone_image: scfg %s, storeid %s, volname %s, vmid %s, snap %s, vol %s',
	$scfg, $storeid, $volname, $vmid, $snap, $vol);

    if ($snap) {
	my @found = sp_volume_find_snapshots($cfg, $vol, $snap);
	if (@found != 1) {
	    log_and_die(
		"Expected exactly one StorPool snapshot for $vol / $snap, got "
		.Dumper(\@found)
	    )
	}

	# OK, let's go wild...
	$vol = $found[0];
    }

    my ($global_id, $vtype, $isBase) = (
	$vol->{globalId},
	$vol->{tags}->{VTAG_TYPE()},
	$vol->{tags}->{VTAG_BASE()},
    );

    log_and_die("clone_image on wrong vtype '$vtype'\n") if $vtype ne 'images';

    my $updated_tags = sub {
	my $current_tags = shift;
	my $disk_id;
	if (defined $current_tags->{VTAG_DISK()}) {
	    if ($current_tags->{VTAG_DISK()} eq 'cloudinit') {
		$disk_id = 'cloudinit';
	    } else {
		$disk_id = find_free_disk($cfg, $vmid);
	    }
	}

	return {
	    %{$current_tags},
	    VTAG_BASE() => '0',
	    VTAG_VM()   => "$vmid",
	    (defined $disk_id ? (VTAG_DISK() => "$disk_id") : ()),
	};
    };

    my $c_res;
    if ($vol->{snapshot}) {
	my $current_tags = sp_snap_info_single(
	    $cfg, $vol->{'globalId'})->{'tags'} // {};
	$c_res = sp_vol_from_snapshot(
	    $cfg, $global_id, 0, $updated_tags->($current_tags));
    } else {
	my $current_tags = sp_vol_info_single(
	    $cfg, $vol->{'globalId'})->{'tags'} // {};
	$c_res = sp_vol_from_parent_volume(
	    $cfg, $global_id, 0, $updated_tags->($current_tags));
    }

    my $newvol = sp_vol_info_single($cfg, $c_res->{data}->{globalId});

    my $result = sp_encode_volsnap_from_tags($newvol);
    DEBUG('clone_image result: name %s', $result);
    return $result;
}

sub volume_resize {
    my $self	= shift;
    my $scfg	= shift;
    my $storeid = shift;
    my $volname = shift;
    my $size	= shift;
    my $running = shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $vol	= sp_decode_volsnap_to_tags($volname, $cfg);

    DEBUG('volume_resize: scfg %s, storeid %s, volname %s, size %s, run %s, vol %s',
	$scfg, $storeid, $volname, $size, $running, $vol);
    sp_vol_update($cfg, $vol->{globalId}, { size => $size }, 0);

    # Make sure storpool_bd has told the kernel to update
    # the attached volume's size if needed
    my $res = sp_client_sync($cfg, $cfg->{api}->{ourid});

    DEBUG('volume_resize: done');
    return 1;
}

sub deactivate_storage {
    my $self	= shift;
    my $storeid = shift;
    my ($scfg, $cache) = @_;
    log_and_die "deactivate_storage($storeid) not implemented yet";

    #TODO this does NOT occur when deleting a storage

}

sub check_connection {
    my $self	= shift;
    my $storeid = shift;
    my $scfg	= shift;

    DEBUG('check_connection: enter');

    my $cfg	= sp_cfg($scfg, $storeid);
    my $res	= sp_services_list($cfg);


    log_and_die "Could not fetch the StorPool services list\n" if !defined $res;
    log_and_die "Could not fetch the StorPool services list: $res->{error}\n"
	if $res->{error};
    DEBUG('check_connection: done');
    return 1;
}

sub volume_snapshot {
    my $self	= shift;
    my $scfg	= shift;
    my $storeid = shift;
    my $volname = shift;
    my $snap	= shift;
    my $running = shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $vol	= sp_decode_volsnap_to_tags($volname, $cfg);

    DEBUG('volume_snapshot: scfg %s, storeid %s, volname %s, snap %s, run %s,vol %s',
	$scfg, $storeid, $volname, $snap, $running, $vol);

    sp_vol_snapshot(
	$cfg,
	$vol->{'globalId'},
	0,
	{
	    %{$vol->{tags}},
	    sp_get_tags($cfg),
	    VTAG_SNAP()		=> $snap,
	    VTAG_SNAP_PARENT()  => $vol->{globalId},
	}
    );

    DEBUG('volume_snapshot: done');
    return;
}

sub volume_snapshot_delete {
    my $self	= shift;
    my $scfg	= shift;
    my $storeid = shift;
    my $volname = shift;
    my $snap	= shift;
    my $running = shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $vol	= sp_decode_volsnap_to_tags($volname, $cfg);

    DEBUG(
	'volume_snapshot_delete: scfg %s, storeid %s, volname %s, '
	.'snap %s, run %s, vol %s',
	$scfg, $storeid, $volname, $snap, $running, $vol);


    for my $snap_obj (sp_volume_find_snapshots($cfg, $vol, $snap)) {
	sp_snap_del($cfg, $snap_obj->{globalId}, 0);
    }

    DEBUG('volume_snapshot_delete: done');
    return
}

sub volume_snapshot_rollback {
    my $self	= shift;
    my $scfg	= shift;
    my $storeid	= shift;
    my $volname = shift;
    my $snap	= shift;
    my $cfg	= sp_cfg($scfg, $storeid);
    my $vol	= sp_decode_volsnap_to_tags($volname, $cfg);
    my @found	= sp_volume_find_snapshots($cfg, $vol, $snap);

    DEBUG('volume_snapshot_rollback: scfg %s, storeid %s, volname %s, snap %s,'
	.'vol %s, found %s',
	$scfg, $storeid, $volname, $snap, $vol, \@found);

    if (@found != 1) {
	log_and_die(
	    "volume_snapshot_rollback: expected exactly one '$snap' snapshot "
	    . "for $vol->{globalId}, got ".Dumper(\@found)
	)
    }

    my $snap_obj = $found[0];
    sp_vol_detach($cfg, $vol->{'globalId'}, 'all', 0);
    sp_vol_revert_to_snapshot($cfg, $vol->{globalId}, $snap_obj->{globalId});

    DEBUG('volume_snapshot_rollback: done');
    return
}

sub volume_snapshot_needs_fsfreeze {
    return 1;
}

sub get_subdir {
    my $self = shift;
    my $scfg = shift;
    my $vtype= shift;
    log_and_die "get_subdir($vtype) not implemented yet";
}

sub delete_store {
    my $self	= shift;
    my $storeid = shift;
    log_and_die "delete_store($storeid) not implemented yet";

    my $cfg	    = sp_cfg({}, $storeid);
    my $vols_hash   = sp_vol_list($cfg);
    my $snaps_hash  = sp_snap_list($cfg);
    my $atts_hash   = sp_attach_list($cfg);

    my %attachments = map { ($_->{volume}, 1) } @{$atts_hash->{'data'}};

    foreach my $vol (@{$vols_hash->{data}}){
	    next unless sp_vol_tag_is($vol, VTAG_VIRT, VTAG_V_PVE) &&
		sp_vol_tag_is($vol, VTAG_LOC, sp_get_loc_name($cfg));
	    next unless $vol->{'templateName'} eq sp_get_template($cfg);
	    if ($attachments{$vol->{'name'}}) {
		    sp_vol_detach($cfg, $vol->{'globalId'}, 'all', 0);
	    }
	    sp_vol_del($cfg, $vol->{'globalId'}, 0);
    }

    foreach my $snap (@{$snaps_hash->{data}}){
	    next unless sp_snap_not_gone($snap);
	    next unless sp_vol_tag_is($snap, VTAG_VIRT, VTAG_V_PVE) &&
		sp_vol_tag_is($snap, VTAG_LOC, sp_get_loc_name($cfg));
	    next unless $snap->{'templateName'} eq sp_get_template($cfg);
	    if ($attachments{$snap->{'name'}}) {
		    sp_vol_detach($snap->{'globalId'}, 'all', 0, 1);
	    }
	    sp_snap_del($cfg, $snap->{'globalId'},0);
    }
}

sub rename_volume($$$$$$) {
    my $self		= shift;
    my $scfg		= shift;
    my $storeid		= shift;
    my $source_volname	= shift;
    my $target_vmid	= shift;
    my $target_volname	= shift;
    my $cfg		= sp_cfg($scfg, $storeid);
    my $vol		= sp_decode_volsnap_to_tags($source_volname, $cfg);

    DEBUG('rename_volume: scfg %s, storeid %s, source_volname %s,'
	.'target_vmid %s, target_volume %s, vol %s',
	$scfg, $storeid, $source_volname, $target_vmid, $target_volname, $vol);

    sp_vol_update($cfg, $vol->{'globalId'}, {
	tags => {
	    %{$vol->{tags}},
	    VTAG_VM() => $target_vmid,
	},
    }, 0);

    my $updated = sp_vol_info_single($cfg, $vol->{globalId});
    my $result = "$storeid:" . sp_encode_volsnap_from_tags($updated);
    DEBUG('rename_volume result: volumeID %s', $result);
    return $result;
}

1;
#TODO when creating new storage, fix placementgroups
#TODO detach on normal shutdown (maybe done)
#TODO reattach iso after reboot
#misc TODO
# remove "raw" from interface make storage!
#full clone (dropped)
#TODO clean sectionconfig.pm
