package PVE::Storage::Custom::StorPoolPlugin;

use v5.16;

use strict;
use warnings;

use Carp qw(croak);
use Data::Dumper;
use File::Path;
use PVE::Storage::Plugin;
use PVE::JSONSchema qw(get_standard_option);
use Sys::Hostname;
use List::Util qw'first';

use JSON;
use LWP::UserAgent;
use LWP::Simple;

use base qw(PVE::Storage::Plugin);

# The volume tags that we look for and set
use constant {
    VTAG_VIRT => 'virt',
    VTAG_CLUSTER => 'pve-cluster',
    VTAG_TYPE => 'pve-type',
    VTAG_FORMAT => 'pve-format',
    VTAG_VM => 'pve-vm',
    VTAG_BASE => 'pve-base',

    VTAG_V_PVE => 'pve',
};

# TODO: pp: get this from the storage pool configuration
use constant OUR_CLUSTER => 'test';

my @SP_IDS = ();
my $SP_HOST = "127.0.0.1";
my $SP_PORT = "81";
my $SP_AUTH;
my $SP_NODES = {};

my $SP_VERS = '1.0';
my $SP_URL = "";

#TODO upload same iso on two storpool templates (test)
#TODO disks list shows iso files from other templates
#TODO disks list shows saved states



sub log_and_die($) {
    my ($msg) = @_;

    warn "FIXME-WIP: $msg\n";
    croak "FIXME-WIP: $msg\n";
}

# Get some storpool settings from storpool.conf
sub sp_confget() {
	#TODO gives error on starting of the service (compilation failed). Does it expect the file to always be there?
	open( INPUTFILE, "</etc/storpool.conf" ) or die "$!";
	my $node;
	@SP_IDS = ();
	while (<INPUTFILE>) {
		$node = $1 if ( $_ =~ m/^\s*\[(\S+)\]\s*$/ );
		if ( $_ =~ m/^\s*SP_OURID\s*=(\d+)/ ){
			push @SP_IDS, int $1;
			$SP_NODES->{$node} = int $1;
		}
		$SP_HOST = $1 if ( $_ =~ m/^\s*SP_API_HTTP_HOST\s*=(\S+)/ );
		$SP_PORT = $1 if ( $_ =~ m/^\s*SP_API_HTTP_PORT\s*=(\d+)/ );
		$SP_AUTH = $1 if ( $_ =~ m/^\s*SP_AUTH_TOKEN\s*=(\d+)/ );
		$SP_URL = "http://$SP_HOST:$SP_PORT/ctrl/$SP_VERS/"
	}
	return { 'sp_host' => $SP_HOST, 'sp_port' => $SP_PORT, 'sp_auth' => $SP_AUTH, 'sp_nodes' => $SP_NODES, 'sp_ids' => \@SP_IDS } ;
}

# Wrapper functions for the actual request
sub sp_get($) {
	my ($addr) = @_;

	return sp_request('GET', $addr, undef);
}

sub sp_post($$) {
	
	my ($addr, $params) = @_;
	my $res = sp_request('POST', $addr, $params);
	return $res
}

# HTTP request to the storpool api
sub sp_request($$$){
	sp_confget();
	my ($method, $addr, $params) = @_;
	
	return undef if ( ${^GLOBAL_PHASE} eq 'START' );

	my $h = HTTP::Headers->new;
	$h->header('Authorization' => "Storpool v1:$SP_AUTH" );
	
	my $p = HTTP::Request->new($method, $SP_URL.$addr, $h);
	$p->content( encode_json( $params ) ) if defined( $params );
	
	my $ua = new LWP::UserAgent;
	$ua->timeout(2 * 60 * 60);
	my $response = $ua->request($p);
	if ($response->code eq "200"){
		return decode_json($response->content);
	}else{
		# this might break something
		my $res = decode_json($response->content);
		return $res if $res and $res->{'error'};
		return { 'error' => { 'descr' => 'Error code: '.$response->code} };
	}
}

sub sp_vol_create($$$$;$){
	my ($name, $size, $template, $ignoreError, $tags) = @_;
        if (defined($name) && $name) {
            log_and_die 'FIXME-WIP: sp_vol_create: non-null name: '.Dumper({name => $name, size => $size, template => $template, ignoreError => $ignoreError});
        }
	
	my $req = { 'template' => $template, 'size' => $size, (defined($tags) ? (tags => $tags) : ()) };
	my $res = sp_post("VolumeCreate", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_vol_create_from_snap($$$$){
	my ($name, $template, $snap, $ignoreError) = @_;
        log_and_die 'sp vol_create_from_snap: args: '.Dumper({name => $name, template => $template, snap => $snap, ignoreError => $ignoreError});
	
	my $req = { 'template' => $template, 'name' => $name, 'parent' => $snap };
	my $res = sp_post("VolumeCreate", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_vol_rename($$$){
	my ($name, $newname, $ignoreError) = @_;
	
	my $req = { 'rename' => $newname };
	my $res = sp_post("VolumeUpdate/$name", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_temp_create($$$$$){
	my ($name, $repl, $placeAll, $placeTail, $ignoreError) = @_;
	
	my $req = { 'replication' => $repl, 'name' => $name, 'placeAll' => $placeAll, 'placeTail' => $placeTail };
	my $res = sp_post("VolumeTemplateCreate", $req);
	
        # TODO: pp: only ignore "already exists" errors
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_vol_status() {
	
	my $res = sp_get("VolumesGetStatus");
	
	# If there is an error here it's fatal, we do not check.
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	
	return $res;
}

sub sp_vol_list() {
	my $res = sp_get("VolumesList");
	
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	
	return $res;
}

sub sp_vol_info($) {
	my ($volname) = @_;
	
	my $res = sp_get("Volume/$volname");
	
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	
	return $res;
}

sub sp_snap_list() {
	
	my $res = sp_get("SnapshotsList");
	
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	
	return $res;
}

sub sp_attach_list() {
	my $res = sp_get("AttachmentsList");
	
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	
	return $res;
}

sub sp_snap_info($) {
	my ($snapname) = @_;
	
	my $res = sp_get("Snapshot/$snapname");
	#use Devel::StackTrace;
	#my $trace = Devel::StackTrace->new;
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	
	return $res;
}

sub sp_disk_list() {
	
	my $res = sp_get("DisksList");
	
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	
	return $res;
}

sub sp_temp_list() {
	
	my $res = sp_get("VolumeTemplatesList");
	
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	
	return $res;
}

sub sp_temp_get($) {
	my ($name) = @_;
	
	my $res = sp_get("VolumeTemplateDescribe/$name");
	
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	return $res;
}

#TODO, if adding more nodes, iso need to be attached to them as well
sub sp_vol_attach($$$$) {
	my ($global_id, $spid, $perms, $ignoreError) = @_;
	
	my $res;
	if ($spid eq "all") {
		#Storpool does not support "all" in attach, hence the difference from detach
		my $req = [{ 'volume' => "~$global_id", $perms => \@SP_IDS, 'force' => JSON::false }];
		$res = sp_post("VolumesReassign", $req);
	}else{
		my $req = [{ 'volume' => "~$global_id", $perms => [$spid], 'force' => JSON::false }];
		$res = sp_post("VolumesReassign", $req);
	}
	
	die "Storpool: $global_id, $spid, $perms, $ignoreError: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	
	
	return $res
}

sub sp_vol_detach($$$) {
	my ($global_id, $spid, $ignoreError) = @_;
	
	my $req;
	if ($spid eq "all"){
		$req = [{ 'volume' => "~$global_id", 'detach' => $spid, 'force' => JSON::false }];
	}else{
		$req = [{ 'volume' => "~$global_id", 'detach' => [$spid], 'force' => JSON::false }];
	}
	my $res = sp_post("VolumesReassign", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_snap_detach($$$) {
	my ($global_id, $spid, $ignoreError) = @_;
	
	my $req;
	if ($spid eq "all"){
		$req = [{ 'snapshot' => "~$global_id", 'detach' => $spid, 'force' => JSON::false }];
	}else{
		$req = [{ 'snapshot' => "~$global_id", 'detach' => [$spid], 'force' => JSON::false }];
	}
	my $res = sp_post("VolumesReassign", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_vol_del($$) {
	my ($global_id, $ignoreError) = @_;
	
	my $req = {};
	my $res = sp_post("VolumeDelete/~$global_id", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_vol_freeze($$) {
	my ($volname, $ignoreError) = @_;
	
	my $req = {};
	my $res = sp_post("VolumeFreeze/$volname", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_vol_fromSnap ($$$) {
	my ($parent, $newvol, $ignoreError) = @_;
	
	my $req = { 'parent' => $parent, 'name' => $newvol };
	my $res = sp_post("VolumeCreate", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

# Currently only used for resize
sub sp_vol_update ($$$) {
	my ($name, $size, $ignoreError) = @_;
	
	my $req = { 'size' => $size };
	my $res = sp_post("VolumeUpdate/$name", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_services_list() {
	
	my $res = sp_get("ServicesList");
	return $res;
}

sub sp_vol_snapshot($$$) {
	my ($vol, $snap, $ignoreError) = @_;
	
	my $req = { 'name' => $snap };
	my $res = sp_post("VolumeSnapshot/$vol", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_snap_del($$) {
	my ($global_id, $ignoreError) = @_;
	
	my $req = { };
	my $res = sp_post("SnapshotDelete/~$global_id", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_placementgroup_list($) {
	my ($pg) = @_;
	
	my $res = sp_get("PlacementGroupDescribe/$pg");
	
	die $res->{'error'}->{'descr'} if ($res->{'error'});
	return $res;
}

# Delete all snapshot that are parents of the volume provided
# We do this the simplest way, by parsing info in the names
sub sp_clean_snaps($) {
        # TODO: pp: figure out how to do this with global IDs and tags
        return;

	my ($volname) = @_;
	my @snaps = map { $_->{"name"} } @{sp_snap_list()->{"data"}};
	my $vmid = undef;
	my $diskid = undef;
	if ($volname =~ m/vm-(\d+)-\S+-(\d+)/){
		$vmid = $1;
		$diskid = $2;
	}else{
		return;
	}
	
	foreach my $snap (@snaps) {
		if ($snap =~ m/^snap-$vmid-disk-$diskid-\S+/){
			sp_snap_del($snap, 0);
			
		}
	}
}

# Various name encoding helpers and utility functions

# Get the value of a tag for a volume.
#
# Returns an undefined value if the volume does not have that tag.
sub sp_vol_get_tag($ $) {
    my ($vol, $tag) = @_;

    ${$vol->{tags} // {}}{$tag}
}

# Check whether a volume has the specified tag, and that its value is as expected.
sub sp_vol_tag_is($ $ $) {
    my ($vol, $tag, $expected) = @_;
    my $value = sp_vol_get_tag($vol, $tag);

    defined($value) && $value eq $expected
}

# Check whether a content type denotes an image, either of a VM or of a container.
sub sp_type_is_image($) {
    my ($type) = @_;

    $type eq 'images' || $type eq 'rootdir'
}

# Encode a single key/value pair.
sub sp_encode_single($) {
    my ($pair) = @_;
    if (scalar @{$pair} != 2) {
        log_and_die "Internal error: sp_encode_single: expected two elements: ".Dumper($pair);
    }
    my ($key, $value) = @{$pair};

    if (length($key) != 1) {
        log_and_die "Internal error: sp_encode_single: expected a single-character key: ".Dumper($pair);
    }
    $value //= '';

    if (index($value, '-') != -1) {
        log_and_die 'FIXME-TODO: sp_encode_single: encode a dash: '.Dumper($pair);
    }
    "$key$value"
}

# Encode a list of [key, value] pairs into a "V0-ga.b.c-timages"-style string.
sub sp_encode_list($) {
    my ($raw) = @_;
    my @slugs = map { sp_encode_single($_) } @{$raw};
    join('-', @slugs)
}

sub sp_encode_volsnap_from_tags($ $) {
    my ($vol, $parent) = @_;

    sp_encode_list([
        [
            ($vol->{'snapshot'} ? 'S' : 'V'),
            '0',
        ],
        [
            'g',
            $vol->{'globalId'},
        ],
        [
            't',
            $vol->{'tags'}->{VTAG_TYPE()},
        ],
        [
            'v',
            $vol->{'tags'}->{VTAG_VM()} // '',
        ],
        [
            'p',
            defined($parent)
                ? (
                    ($parent->{'snapshot'} ? 'S' : 'V').
                    $parent->{'globalId'}
                )
                : '',
        ],
        [
            'B',
            $vol->{'tags'}->{VTAG_BASE()} // '0',
        ],
        # TODO: pp: 'f' for a format other than "raw"
    ])
}

sub sp_decode_single($) {
    my ($part) = @_;

    if (!defined($part) || $part eq '') {
        log_and_die 'Internal error: sp_decode_single: got part '.Dumper(\$part);
    }
    split //, $part, 2
}

sub sp_decode_list($) {
    my ($raw) = @_;
    if (index($raw, '--') != -1) {
        log_and_die 'FIXME-TODO: decode dashes: '.Dumper(\$raw);
    }
    my @parts = split /-/, $raw;
    map { sp_decode_single($_) } @parts
}

sub sp_s($) {
    my ($value) = @_;

    if (defined($value) && $value eq '') {
        undef
    } else {
        $value
    }
}

sub sp_decode_volsnap_to_tags($) {
    my ($volname) = @_;

    my ($first, $rest) = split /-/, $volname, 2;
    if (!defined($first)) {
        log_and_die "sp_decode_volname_to_tags: no dashes at all: ".Dumper(\$volname);
    }

    my $snapshot;
    if ($first eq 'V0') {
        $snapshot = JSON::false;
    } elsif ($first eq 'S0') {
        $snapshot = JSON::true;
    } else {
        log_and_die 'sp_decode_volname_to_tags: unsupported first slug: '.Dumper(\$volname);
    }

    my %pairs = sp_decode_list($rest // '');

    my $parent_spec = sp_s($pairs{'p'});
    my $parent;
    if (defined($parent_spec)) {
        my ($parent_snaptype, $parent_id) = split //, $parent_spec, 2;
        $parent = {
            snapshot => $parent_snaptype eq 'S' ? JSON::true : JSON::false,
            globalId => $parent_id,
        };
    }

    return (
        {
            snapshot => $snapshot,
            globalId => $pairs{'g'},
            tags => {
                VTAG_TYPE() => $pairs{'t'},
                VTAG_VM() => sp_s($pairs{'v'}),
                VTAG_BASE() => $pairs{'B'} // '0',
            },
        },
        $parent,
    );
}

# Configuration

sub api {
    return 10;
}

# This is the most important method. The ID of the plugin
sub type {
    return 'storpool';
}

# The capabilities of the plugin
sub plugindata {
    
    return {
	content => [ { images => 1, rootdir => 1, vztmpl => 1, iso => 1, backup => 1, none => 1 },
		     { images => 1,  rootdir => 1 }],
	format => [ { raw => 1 } , 'raw' ],
    };
}   

# The properties the plugin can handle
sub properties {

    return {
	replication => {
	    description => "Storpool test.",
	    type => 'integer', format => 'pve-storage-replication',
	},
	
    };
}

sub options {

    return {
	path => { fixed => 1 },
	replication => { fixed => 1 },
        nodes => { optional => 1 },
	shared => { optional => 1 },
	disable => { optional => 1 },
        maxfiles => { optional => 1 },
	content => { optional => 1 },
	format => { optional => 1 },
   };
}

# Storage implementation

# The path has to be provided separately for iso file listing
sub check_config {
    my ($class, $sectionId, $config, $create, $skipSchemaCheck) = @_;

    $config->{path} = "/dev/storpool-byid" if $create && !$config->{path};

    return $class->SUPER::check_config($sectionId, $config, $create, $skipSchemaCheck);
}

# Just chech value before accepting the request
PVE::JSONSchema::register_format('pve-storage-replication', \&sp_parse_replication);
sub sp_parse_replication {
    my ($rep, $noerr) = @_;

    if ($rep < 1 or $rep > 4) {
	return undef if $noerr;
	die "replication must be between 1 and 4\n";
    }

    return $rep;
}

# This creates the storpool template. It's called frequently though,
# so we ignore "already exists" errors
sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    
    #sp_confget();
    
    my $replication = $scfg->{replication};
    
    # TODO: pp: discuss: change this to require that the template already exists?
    #TODO should I check if already created rather than ignoring the error?
    sp_temp_create($storeid, $replication, "hdd", "hdd", 1);
}

# Create the volume
sub alloc_image {
	my ($class, $storeid, $scfg, $vmid, $fmt, $name, $size) = @_;

	# One of the few places where size is in K
	$size *= 1024;
	die "unsupported format '$fmt'" if $fmt ne 'raw';
	
        if (defined($name)) {
            log_and_die "FIXME-WIP: alloc_image: non-null name passed: ".Dumper({class => $class, storeid => $storeid, scfg => $scfg, vmid => $vmid, fmt => $fmt, name => $name, size => $size});
        }
	
	my $c_res = sp_vol_create(undef, $size, $storeid, 0, {
            VTAG_VIRT() => VTAG_V_PVE,
            VTAG_CLUSTER() => OUR_CLUSTER,
            VTAG_TYPE() => 'images',
            VTAG_FORMAT() => $fmt,
            (defined($vmid) ? (VTAG_VM() => "$vmid"): ()),
        });
        my $global_id = ($c_res->{'data'} // {})->{'globalId'};
        if (!defined($global_id) || $global_id eq '') {
            log_and_die 'StorPool internal error: no globalId in the VolumeCreate API response: '.Dumper($c_res);
        }

        my $vol_res = sp_vol_info("~$global_id");
        my $vol_data = $vol_res->{'data'};
        if (!defined($vol_data) || ref($vol_data) ne 'ARRAY' || @{$vol_data} != 1) {
            log_and_die 'StorPool internal error: volinfo for a just-created volume returned '.Dumper($vol_res);
        }
        sp_encode_volsnap_from_tags($vol_data->[0], undef);
}

# Status of the space of the storage
sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
    # TODO: pp: discuss: we should probably change this to process "template status" in some way
    my $disks = sp_disk_list();

    my $total = 0;
    my $free = 0;
    my $used = 0;
    
    my $template = sp_temp_get($storeid);
    my $placeAll = sp_placementgroup_list($template->{data}->{placeAll})->{data}->{disks};
    my $placeTail = sp_placementgroup_list($template->{data}->{placeTail})->{data}->{disks};
    my $minAG = 100000000000000;

    foreach my $diskID (@$placeAll){
	$minAG = $disks->{data}->{$diskID}->{agCount} if $disks->{data}->{$diskID}->{agCount} < $minAG;
	$used += $disks->{data}->{$diskID}->{'objectsOnDiskSize'};
    }

    if ($template->{data}->{placeAll} eq $template->{data}->{placeTail}){
	$total = $minAG * 512*1024*1024 * 4096 / (4096 + 128) * scalar(@$placeAll);
    }else{
	foreach my $diskID (@$placeTail){
	    $minAG = $disks->{data}->{$diskID}->{agCount} if $disks->{data}->{$diskID}->{agCount} < $minAG;
	    $used += $disks->{data}->{$diskID}->{'objectsOnDiskSize'};
	}
	$total = $minAG * 512*1024*1024 * 4096 / (4096 + 128) * (scalar(@$placeAll) + scalar(@$placeTail));
    }

    #while ((my $key, my $disk) = each $disks->{'data'}){
	#$total += $disk->{'agCount'} * 512*1024*1024 * 4096 / (4096 + 128);
	#$used += $disk->{'objectsOnDiskSize'};
    #}
    
    #This way this could be negative
    $free = $total - $used;
    #my $template = sp_temp_get($storeid);
        
    my $replication = $template->{'data'}->{'replication'};
    return ($total/$replication, $free/$replication, $used/$replication, 1);
}

sub parse_volname ($) {
    my ($class, $volname) = @_;

    my ($vol, $parent) = sp_decode_volsnap_to_tags($volname);

    my ($basename, $baseid);
    if (defined($parent)) {
        my $vinfo = $parent->{snapshot}
            ? sp_snap_info('~'.$parent->{'globalId'})
            : sp_vol_info('~'.$parent->{'globalId'});
        if (@{$vinfo->{'data'}}) {
            $basename = $vinfo->{'data'}->[0]->{'globalId'};
            $baseid = $vinfo->{'data'}->[0]->{'tags'}->{VTAG_VM()};
        }
    }

    return (
        $vol->{'tags'}->{VTAG_TYPE()},
        $vol->{'globalId'},
        $vol->{'tags'}->{VTAG_VM()},
        $basename,
        $baseid,
        ($vol->{'tags'}->{VTAG_BASE()} // '0') eq '1',
        'raw',
    )
}

sub filesystem_path {
    my ($class, $scfg, $volname, $snapname) = @_;

    my ($vtype, $name, $vmid) = $class->parse_volname("$volname");
    
    my $path = "/dev/storpool-byid/$name";

    return wantarray ? ($path, $vmid, $vtype) : $path;
}

sub activate_volume {
    my ($class, $storeid, $scfg, $volname, $exclusive, $cache) = @_;
	
    my $path = $class->path($scfg, $volname, $storeid);

    my (undef, $global_id) = $class->parse_volname($volname);
    my $host = hostname();
    my $perms = "rw";

    # TODO: pp: remove this when the configuration goes into the plugin?
    if (!%{$SP_NODES}) {
        sp_confget();
    }
    
    sp_vol_attach($global_id, $SP_NODES->{$host}, $perms, 0);
    log_and_die "Internal StorPool error: could not find the just-attached volume $global_id at $path" unless -e $path;
}

sub deactivate_volume {
    my ($class, $storeid, $scfg, $volname, $cache) = @_;
    
    my $path = $class->path($scfg, $volname, $storeid);
    
    return if ! -b $path;

    my (undef, $global_id) = $class->parse_volname($volname);
    my $host = hostname();

    # TODO: pp: remove this when the configuration goes into the plugin?
    if (!%{$SP_NODES}) {
        sp_confget();
    }
    
    sp_vol_detach($global_id, $SP_NODES->{$host}, 0);
}

sub free_image {
    my ($class, $storeid, $scfg, $volname, $isBase) = @_;
    my (undef, $global_id) = $class->parse_volname($volname);
    my $isSnap = scalar grep { $_->{'globalId'} eq $global_id } @{ sp_snap_list()->{'data'} };
    if ($isSnap) {
	sp_snap_del($global_id, 0)
    }else{
	# Volume could already be detached, we do not care about errors
	sp_vol_detach($global_id, 'all', 1);
	sp_vol_del($global_id, 0);
	sp_clean_snaps($global_id);
    }
    
    
	

    return undef;
}

sub volume_has_feature {
    my ($class, $scfg, $feature, $storeid, $volname, $snapname, $running) = @_;
    log_and_die "volume_has_feature: args: ".Dumper({class => $class, scfg => $scfg, feature => $feature, storeid => $storeid, snapname => $snapname, running => $running});

    my $features = {
	snapshot => { current => 1, snap => 1 },
	clone => { base => 1 },
	template => { current => 1 },
	copy => { base => 1,
		  current => 1,
		  snap => 1 },
    };

    my ($vtype, $name, $vmid, , undef, undef, $isBase) =
	$class->parse_volname($volname);

    my $key = undef;
    if($snapname){
        $key = 'snap';
    }else{
        $key =  $isBase ? 'base' : 'current';
    }

    return 1 if defined($features->{$feature}->{$key});

    return undef;
}

#sub file_size_info {
#    my ($filename, $timeout) = @_;
#}

sub volume_size_info {
    my ($class, $scfg, $storeid, $volname, $timeout) = @_;
    log_and_die "volume_size_info: args: ".Dumper({class => $class, scfg => $scfg, storeid => $storeid, volname => $volname, timeout => $timeout});
    #my $path = $class->filesystem_path($scfg, $volname);
    
    my $format = "raw";
    my $parent;
    my $size = 0;
    my $used = 0;
    
    my $res = sp_vol_status();
    $size = $res->{"data"}->{"$volname"}->{"size"};
    $used = $res->{"data"}->{"$volname"}->{"storedSize"};
    my $res2;
    if ($volname =~ m/^(vm-|iso-)/) {
	$res2 = sp_vol_info("$volname");
    }else{
	$res2 = sp_snap_info("$volname");
    }
    $parent = $res2->{"data"}[0]->{"parentName"};
    return wantarray ? ($size, $format, $used, $parent) : $size;

}

sub list_volumes {
    my ($class, $storeid, $scfg, $vmid, $content_types) = @_;
    my %ctypes = map { $_ => 1 } @{$content_types};

    my $volStatus = sp_vol_status();
    my $res = [];

    for my $vol (values %{$volStatus->{'data'}}) {
        next unless sp_vol_tag_is($vol, VTAG_VIRT, VTAG_V_PVE) && sp_vol_tag_is($vol, VTAG_CLUSTER, OUR_CLUSTER);
        my $v_type = sp_vol_get_tag($vol, VTAG_TYPE);
        next unless defined($v_type) && exists $ctypes{$v_type};
        my $v_template = $vol->{templateName} // '';
        next unless $v_template eq $storeid;

        my $v_vmid = sp_vol_get_tag($vol, VTAG_VM);
        if (defined $vmid) {
            next unless defined($v_vmid) && $v_vmid eq $vmid;
        }

        my $v_parent = $vol->{parentName};
        my ($parent, $parent_obj);
        if ($v_parent) {
            $parent_obj = $volStatus->{'data'}->{$v_parent};
            if (defined $parent_obj) {
                # Down the rabbit hole...
                my $grandparent_name = $parent_obj->{parentName};
                my $grandparent_obj = $grandparent_name
                    ? $volStatus->{'data'}->{$grandparent_name}
                    : undef;
                $parent = sp_encode_volsnap_from_tags($parent_obj, $grandparent_obj);
            }
        }

        # TODO: pp: apply the rootdir/images fix depending on $v_vmid

        # TODO: pp: figure out whether we ever need to store non-raw data on StorPool
        my $data = {
            volid => "$storeid:".sp_encode_volsnap_from_tags($vol, $parent_obj),
            content => $v_type,
            vmid => $v_vmid,
            size => $vol->{size},
            used => $vol->{storedSize},
            parent => $parent,
            format => 'raw',
        };
        push @{$res}, $data;
    }

    return $res;
}

sub list_images {
    my ($class, $storeid, $scfg, $vmid, $vollist, $cache) = @_;
    log_and_die "list_images: args: ".Dumper({class => $class, storeid => $storeid, scfg => $scfg, vmid => $vmid, vollist => $vollist, cache => $cache});
    # TODO: pp: reimplement this using parts of the list_volumes() code
}

sub create_base {
    my ($class, $storeid, $scfg, $volname) = @_;
    log_and_die "create_base: args: ".Dumper({class => $class, storeid => $storeid, scfg => $scfg, volname => $volname});

    my ($vtype, $name, $vmid, undef, undef, $isBase) =
	$class->parse_volname($volname);
    die "create_base not possible with types other than images. '$vtype' given.\n" if $vtype ne 'images';

    die "create_base not possible with base image\n" if $isBase;
	
    my ($size, $format, $used, $parent) = $class->volume_size_info($scfg, $storeid, $volname, 0);
    die "file_size_info on '$volname' failed\n" if !($format && $size);

    die "volname '$volname' contains wrong information about parent\n"
	if $isBase && !$parent;

    my $newname = $name;
    $newname =~ s/^vm-/base-/;

    sp_vol_rename("$name", "$newname", 0);
    sp_vol_freeze("$newname", 0);

    return $newname;
}

sub clone_image {
    my ($class, $scfg, $storeid, $volname, $vmid, $snap) = @_;
    log_and_die "clone_image: args: ".Dumper({class => $class, scfg => $scfg, storeid => $storeid, volname => $volname, vmid => $vmid, snap => $snap});

    my ($vtype, $basename, $basevmid, undef, undef, $isBase) =
	$class->parse_volname($volname);

    die "clone_image on wrong vtype '$vtype'\n" if $vtype ne 'images';

    die "this storage type does not support clone_image on snapshot\n" if $snap; #TODO investigate what $snap means. Possibly the base contains snapshots, which under normal operation is not possible

    die "clone_image only works on base images\n" if !$isBase;

    my $name;
    my $vols = sp_vol_status();
    
    for (my $i = 1; $i < 100; $i++) {
    	my $tn = "vm-$vmid-disk-$i";
    	if (!defined ($vols->{"data"}->{"$tn"})) {
    		$name = $tn;
    		last;
    	}
    }
    sp_vol_fromSnap("$volname", "$name", 0);

    return $name;
}

sub volume_resize {
    my ($class, $scfg, $storeid, $volname, $size, $running) = @_;
    log_and_die "volume_resize: args: ".Dumper({class => $class, scfg => $scfg, storeid => $storeid, volname => $volname, size => $size, running => $running});


    sp_vol_update("$volname", $size, 0);
    
    return 1;
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    log_and_die "deactivate_storage: args: ".Dumper({class => $class, storeid => $storeid, scfg => $scfg, cache => $cache});

    #TODO this does NOT occur when deleteing a storage
    
}

sub check_connection {
    my ($class, $storeid, $scfg) = @_;
    my $res = sp_services_list();
    die "Could not fetch the StorPool services list\n" if ! defined $res;
    die "Could not fetch the StorPool services list: ".$res->{'error'}."\n" if $res->{'error'};
    return 1;
}

sub volume_snapshot {
    my ($class, $scfg, $storeid, $volname, $snap, $running) = @_;
    log_and_die "volume_snapshot: args: ".Dumper({class => $class, scfg => $scfg, storeid => $storeid, volname => $volname, snap => $snap, running => $running});

    # We don't care if the machine is running, we can still do snapshots
    #return 1 if $running;
    my $snapname = $volname;
    $snapname =~ s/^vm-/snap-/;
    
    my $res = sp_vol_snapshot("$volname", "$snapname-$snap", 0);

    return undef;
}

sub volume_snapshot_delete {
    my ($class, $scfg, $storeid, $volname, $snap, $running) = @_;
    log_and_die "volume_snapshot_delete: args: ".Dumper({class => $class, scfg => $scfg, storeid => $storeid, volname => $volname, snap => $snap, running => $running});

    return 1 if $running;
    my $snapname = $volname;
    $snapname =~ s/^vm-/snap-/;

    my $res = sp_snap_del("$snapname-$snap", 0);
    return undef;
}

sub volume_snapshot_rollback {
    my ($class, $scfg, $storeid, $volname, $snap) = @_;
    log_and_die "volume_snapshot_rollback: args: ".Dumper({class => $class, scfg => $scfg, storeid => $storeid, volname => $volname, snap => $snap});

    my $snapname = $volname;
    $snapname =~ s/^vm-/snap-/;
    
    my $res = sp_vol_del("$volname", 0);
    
    my $res2 = sp_vol_create_from_snap("$volname", $storeid, "$snapname-$snap", 0);
    
    return undef;
}

sub get_subdir {
    my ($class, $scfg, $vtype) = @_;
    log_and_die "get_subdir: args: ".Dumper({class => $class, scfg => $scfg, vtype => $vtype});
	
    return "/dev/storpool";
}

sub delete_store {
	my ($class, $storeid) = @_;
    log_and_die "delete_store: args: ".Dumper({class => $class, storeid => $storeid});
	my $vols_hash = sp_vol_list();
	my $snaps_hash = sp_snap_list();
	my $atts_hash = sp_attach_list();
	
	my $attachments = [];
	
	foreach my $att (@{$atts_hash->{data}}){
		push @$attachments, $att->{volume};
	}

	foreach my $vol (@{$vols_hash->{data}}){
		if ($vol->{templateName} eq $storeid){
			if (first { $_ eq $vol->{name} } @$attachments){
				sp_vol_detach($vol->{name},'all', 0);
			}
			sp_vol_del($vol->{name}, 0);
		}
	}

	foreach my $snap (@{$snaps_hash->{data}}){
		if ($snap->{templateName} eq $storeid){
			if (first { $_ eq $snap->{name} } @$attachments){
				sp_vol_detach($snap->{name},'all', 0);
			}
			sp_snap_del($snap->{name},0);
		}
	}
}

1;
#TODO when creating new storage, fix placementgroups
#TODO detach on normal shutdown (maybe done)
#TODO reattach iso after reboot
#misc TODO
# remove "raw" from interface make storage!   
#full clone (dropped)
#TODO clean sectionconfig.pm
