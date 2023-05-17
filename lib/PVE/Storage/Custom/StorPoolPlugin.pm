package PVE::Storage::Custom::StorPoolPlugin;

use strict;
use warnings;

use File::Path;
use PVE::Storage::Plugin;
use PVE::JSONSchema qw(get_standard_option);
use Sys::Hostname;
use List::Util qw'first';

use JSON;
use LWP::UserAgent;
use LWP::Simple;

use base qw(PVE::Storage::Plugin);
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

sub sp_vol_create($$$$){
	my ($name, $size, $template, $ignoreError) = @_;
	
	my $req = { 'template' => $template, 'name' => $name, 'size' => $size };
	my $res = sp_post("VolumeCreate", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_vol_create_from_snap($$$$){
	my ($name, $template, $snap, $ignoreError) = @_;
	
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
	my ($volname, $spid, $perms, $ignoreError) = @_;
	
	my $res;
	if ($spid eq "all") {
		#Storpool does not support "all" in attach, hence the difference from detach
		my $req = [{ 'volume' => $volname, $perms => \@SP_IDS, 'force' => JSON::false }];
		$res = sp_post("VolumesReassign", $req);
	}else{
		my $req = [{ 'volume' => $volname, $perms => [$spid], 'force' => JSON::false }];
		$res = sp_post("VolumesReassign", $req);
	}
	
	die "Storpool: $volname, $spid, $perms, $ignoreError: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	
	
	return $res
}

sub sp_vol_detach($$$) {
	my ($volname, $spid, $ignoreError) = @_;
	
	my $req;
	if ($spid eq "all"){
		$req = [{ 'volume' => $volname, "detach" => $spid, 'force' => JSON::false }];
	}else{
		$req = [{ 'volume' => $volname, "detach" => [$spid], 'force' => JSON::false }];
	}
	my $res = sp_post("VolumesReassign", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_snap_detach($$$) {
	my ($snapname, $spid, $ignoreError) = @_;
	
	my $req;
	if ($spid eq "all"){
		$req = [{ 'snapshot' => $snapname, "detach" => $spid, 'force' => JSON::false }];
	}else{
		$req = [{ 'snapshot' => $snapname, "detach" => [$spid], 'force' => JSON::false }];
	}
	my $res = sp_post("VolumesReassign", $req);
	
	die "Storpool: ".$res->{'error'}->{'descr'} if (!$ignoreError && $res->{'error'});
	return $res
}

sub sp_vol_del($$) {
	my ($volname, $ignoreError) = @_;
	
	my $req = {};
	my $res = sp_post("VolumeDelete/$volname", $req);
	
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
	my ($snap, $ignoreError) = @_;
	
	my $req = { };
	my $res = sp_post("SnapshotDelete/$snap", $req);
	
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

# Configuration

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

    $config->{path} = "/dev/storpool" if $create && !$config->{path};

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
    
    #TODO should I check if already created rather than ignoring the error?
    sp_temp_create($storeid, $replication, "hdd", "hdd", 1);
}

# Create the volume
sub alloc_image {
	my ($class, $storeid, $scfg, $vmid, $fmt, $name, $size) = @_;
	
	# One of the few places where size is in K
	$size *= 1024;
	die "unsupported format '$fmt'" if $fmt ne 'raw';
	
	die "illegal name '$name' - sould be 'vm-$vmid-*'\n" 
		if  $name && $name !~ m/^vm-$vmid-/;
	
	# Search for a name that is not taken
	if (!$name) {
		my $vols = sp_vol_status();
		
		for (my $i = 1; $i < 100; $i++) {
			my $tn = "vm-$vmid-disk-$i";
			if (!defined ($vols->{"data"}->{"$tn"})) {
				$name = $tn;
				last;
			}
		}
	}
	
	my $res = sp_vol_create("$name", $size, $storeid, 0);
	
	return $name
}

# Status of the space of the storage
sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
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
    my $res2;
    if ($volname =~ m/^(vm-|iso-)[^@]*$/) {
	$res2 = sp_vol_info("$volname");
    }else{
	$res2 = sp_snap_info("$volname");
    }
    my $basename = $res2->{"data"}[0]->{"parentName"};
    my $basevmid = undef;
    if ($basename) {
	$basevmid = $basename;
	$basevmid =~ s/^(base-(\d+)-\S+-\d+)$/$2/;
    }else{
	$basename = undef;
    };    
    if ($volname =~ m/^(vm-(\d+)-\S+-\S+(\.\S+)?)$/) {
	return ('images', $1, $2, $basename, $basevmid, 0);
    } elsif ($volname =~ m/^(base-(\d+)-\S+-\d+)$/) {
	return ('images', $1, $2, $basename, $basevmid, 1);
    } elsif ($volname =~ m/^(snap-(\d+)-\S+-\d+-(\S+))$/) {
	return ('images', $1, $2, $basename, $basevmid, 1);
    } elsif ($volname =~ m/^(iso-(\S+))$/) {
	return ('iso', $1);
    }
    
    die "unable to parse storpool volume name '$volname'\n";
}

sub filesystem_path {
    my ($class, $scfg, $volname, $storeid) = @_;

    my ($vtype, $name, $vmid) = $class->parse_volname("$volname");
    
    my $path = "/dev/storpool/$name";

    return wantarray ? ($path, $vmid, $vtype) : $path;
}

sub activate_volume {
    my ($class, $storeid, $scfg, $volname, $exclusive, $cache) = @_;
	
    # Exclusive attaching is not yet supported.
    
    return if ($volname =~ m/^(base-(\d+)-\S+)$/);
	
    my $path = $class->path($scfg, $volname, $storeid);

    my $host = hostname();
    my $perms = "rw";
    
    sp_vol_attach("$volname", $SP_NODES->{$host}, $perms, 0);
    die "Waiting for storpool volume timed out" if system ("/usr/bin/ssh", $host, "for ((i=0;i<30; i++)); do /usr/bin/test -e /dev/storpool/$volname && exit 0; sleep .1; done; exit 1");
}

sub deactivate_volume {
    my ($class, $storeid, $scfg, $volname, $cache) = @_;
    
    my $path = $class->path($scfg, $volname, $storeid);
    
    return if ! -b $path;

    my $host = hostname();
    
    #We do not want to detach iso files because they will not be displayed on the interface.
    unless ($volname =~ m/^iso-/) {
	my $res = sp_vol_detach("$volname", $SP_NODES->{$host}, 0);
    }
    
}

sub free_image {
    my ($class, $storeid, $scfg, $volname, $isBase) = @_;
    my $isSnap = 0;
    $isSnap = 1 if grep { $_->{"name"} eq "$volname" } @{ sp_snap_list()->{"data"} };
    if ($isSnap) {
	sp_snap_del("$volname", 0)
    }else{
	# Volume could already be detached, we do not care about errors
	sp_vol_detach("$volname", "all", 1);
	sp_vol_del("$volname", 0);
	sp_clean_snaps($volname);
    }
    
    
	

    return undef;
}

sub volume_has_feature {
    my ($class, $scfg, $feature, $storeid, $volname, $snapname, $running) = @_;

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

sub list_images {
    my ($class, $storeid, $scfg, $vmid, $vollist, $cache) = @_;

    #TODO maybe use caches here
    
    #my $vgname = $scfg->{vgname};

    #$cache->{lvs} = lvm_lvs() if !$cache->{lvs};
    my $volStatus = sp_vol_status();
    my $volInfo;
    my $return = [];
    
	foreach my $fullname (keys $volStatus->{"data"}) {
	    my $info = {};
	    
	    next if $fullname =~ /\@\d+$/;
	    
	    my (undef, $volname, $id, undef, undef, $type) = $class->parse_volname($fullname);
	    next if !$vollist && defined($vmid) && ($id ne $vmid);
	    
	    if ($volname =~ m/^(vm-|iso-)/) {
		$volInfo = sp_vol_info("$volname");
	    }else{
		$volInfo = sp_snap_info("$volname");
	    }
	    my $volstor = $volInfo->{"data"}[0]->{"templateName"};
	    
	    next if (!$volstor or $volstor ne $storeid or $type != 0);
		
	    $info->{volid} = "$storeid:$volname";
	    $info->{size} = $volStatus->{"data"}->{$fullname}->{"size"};
	    $info->{used} = $volStatus->{"data"}->{$fullname}->{"storedSize"};
	    $info->{vmid} = $id;
	    my $parent = $volInfo->{"data"}[0]->{"parentName"};
	    if ($parent) {
		$info->{parent} = $parent;
	    }else{
		$info->{parent} = undef;
	    }
	    
	    if ($volname =~ m/^iso-/) {
		$info->{format} = 'iso';
	    }else{
		$info->{format} = 'raw';
	    }
	    
	    push @$return, $info;
	}
    return $return;
}

sub create_base {
    my ($class, $storeid, $scfg, $volname) = @_;

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


    sp_vol_update("$volname", $size, 0);
    
    return 1;
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;

    #TODO this does NOT occur when deleteing a storage
    
}

sub check_connection {
    my ($class, $storeid, $scfg) = @_;
    my $res = sp_services_list();
    return undef if ! defined $res;
    return undef if $res->{"error"};
    return 1;
}

sub volume_snapshot {
    my ($class, $scfg, $storeid, $volname, $snap, $running) = @_;

    # We don't care if the machine is running, we can still do snapshots
    #return 1 if $running;
    my $snapname = $volname;
    $snapname =~ s/^vm-/snap-/;
    
    my $res = sp_vol_snapshot("$volname", "$snapname-$snap", 0);

    return undef;
}

sub volume_snapshot_delete {
    my ($class, $scfg, $storeid, $volname, $snap, $running) = @_;

    return 1 if $running;
    my $snapname = $volname;
    $snapname =~ s/^vm-/snap-/;

    my $res = sp_snap_del("$snapname-$snap", 0);
    return undef;
}

sub volume_snapshot_rollback {
    my ($class, $scfg, $storeid, $volname, $snap) = @_;

    my $snapname = $volname;
    $snapname =~ s/^vm-/snap-/;
    
    my $res = sp_vol_del("$volname", 0);
    
    my $res2 = sp_vol_create_from_snap("$volname", $storeid, "$snapname-$snap", 0);
    
    return undef;
}

sub get_subdir {
    my ($class, $scfg, $vtype) = @_;
	
    return "/dev/storpool";
}

sub delete_store {
	my ($class, $storeid) = @_;
	my $vols_hash = sp_vol_list();
	my $snaps_hash = sp_snap_list();
	my $atts_hash = sp_attach_list();
	
	my $attachments = [];
	
	foreach my $att (@{$atts_hash->{data}}){
		push @$attachments, $att->{volume};
	}

	foreach my $vol (@{$vols_hash->{data}}){
		if ($vol->{templateName} eq $storeid){
			if (first { $vol->{name} eq $_ } @$attachments){
				sp_vol_detach($vol->{name},'all', 0);
			}
			sp_vol_del($vol->{name}, 0);
		}
	}

	foreach my $snap (@{$snaps_hash->{data}}){
		if ($snap->{templateName} eq $storeid){
			if (first { $snap->{name} eq $_ } @$attachments){
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
