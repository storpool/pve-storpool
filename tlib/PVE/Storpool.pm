package PVE::Storpool;
# Tests helper
use v5.16;
use strict;
use warnings;
use JSON; # decode_json encode_json
use HTTP::Response;
use Data::Dumper; # TODO remove
use Carp;
use Scalar::Util qw/tainted/;
use Unix::Mknod qw/:all/;
use File::stat;
use Fcntl qw(:mode);
use Exporter 'import';

our @EXPORT = qw/storpool_confget_data config_location write_config mock_confget mock_sp_cfg mock_lwp_request 
truncate_http_log slurp_http_log make_http_request taint not_tainted bless_plugin create_block_file/;

# Control the behavior of the storpool_confget cli
sub config_location { '/tmp/storpool_confget_data' }

# Used only in 1 test, for the other tests we will mock the config data
sub write_config {
    my $opts      = { @_ };
    my $exit_code = $opts->{exit_code} || 0;
    my $data      = $opts->{data};
    my $path      = config_location();

    my $json    = encode_json({ exit_code => $exit_code, data => $data });

    open( my $fh, ">", $path ) or die "Failed to open for writing config file '$path': '$!'";

    print $fh $json or die "Failed to write to $path";
    close $fh or die "Failed to flush write to $path";
}

sub read_config {
    my $path = config_location();

    return {} if !-f $path; # we expect to be missing

    open( my $fh, "<", $path ) or die "Failed to read $path: '$!'";
    local $/;

    my $data = <$fh>;

    my $res = eval { decode_json( $data ) } // {};
    close $fh;

    return $res;
}

sub storpool_confget_data {
    my $config = read_config();

    return $config if scalar keys %$config;
    return { data => 'test_var=test', exit_code => 1 }
}

sub mock_confget {
    my %data = @_;
    no warnings qw/redefine prototype/;
    taint(%data) if ${^TAINT};
   *PVE::Storage::Custom::StorPoolPlugin::sp_confget = sub {
        %data
    };
}

sub mock_sp_cfg {
    no warnings qw/redefine prototype/;
   *PVE::Storage::Custom::StorPoolPlugin::sp_cfg = sub {
        {
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
    };
}

sub mock_lwp_request {
    no warnings 'redefine';
    my $params  = { @_ };
    my $data    = $params->{data};
    my $test    = $params->{test};
    my $restore = $params->{restore};
    state $orig = \&LWP::UserAgent::request;

    if( $data && ref($data) eq 'HASH' ){
        $data = HTTP::Response->new( $data->{code} // 200, $data->{msg}, $data->{header}, $data->{content} );
    }
    if( $data && ref($data) ne 'HTTP::Response' ) {
        die "You must provide a object of type HTTP::Response for LWP mock to work";
    }

    if( $restore ) {
        *LWP::UserAgent::request = $orig;
    } else {
        *LWP::UserAgent::request = sub {
            my $class   = shift;
            my $request = shift;

            if( $test && ref($test) eq 'CODE' ) {
                $data = $test->($class, $request);
                die "Missing response Hash" if !$data;
                taint($data->{content}) if ${^TAINT};
                $data = HTTP::Response->new( $data->{code} // 200, $data->{msg}, $data->{header}, $data->{content} );
            }
            return $data;
        }
    }
}

sub truncate_http_log {
    my $http_log_path = &PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG;
    open(my $fh, '>', $http_log_path);
    close $fh;
}

sub slurp_http_log { # --> Str
    my $http_log_path = &PVE::Storage::Custom::StorPoolPlugin::SP_PVE_Q_LOG;
    local $/;
    open(my $fh, '<', $http_log_path) or return undef;
    my $data = <$fh>;
    close($fh);
    return $data;
}

sub make_http_request {
    my $params = { @_ };
    my $method = $params->{method}  || 'GET';
    my $path   = $params->{path}    || die "Missing path";
    my $request= $params->{request};

    mock_sp_cfg();
    PVE::Storage::Custom::StorPoolPlugin::sp_request(
        PVE::Storage::Custom::StorPoolPlugin::sp_cfg(1,2),
        $method,
        $path,
        $request
    );
}


# Taint
sub taint {
    state $TAINT_BIT = substr("$0$^X", 0, 0);
    state $TAINT_NUM = 0 + "0$TAINT_BIT";

    carp("Taint not enabled!") if !${^TAINT};

    foreach my $var ( @_ ) { # Work with the argument references, so DO NOT change this
        my $obj = tied $var; # blessed obj
        if( defined $obj && $obj->can('TAINT') ){
            $obj->TAINT(1);
            next;
        }
        eval {
            if( not $var & '00' | '00' ) {
                $var += $TAINT_NUM;
            } else {
                $var .= $TAINT_BIT;
            }
        };
        if ($@ && $@ =~ /read-only/) {
            carp("Cannot taint read-only value");
        } elsif ($@) {
            carp("Taint failed: $@");
        }
    }
    return
}

# Returns values if not tainted
sub not_tainted {
    grep { !tainted($_) } @_
}

sub bless_plugin {
    *PVE::Storage::Custom::StorPoolPlugin::new = sub {
        my $class = shift;
        my $data  = { test => 1 };

        return bless $data, $class;
    }
}

# returns
# 0 success
# -1 error: see $!
# 1 already exists
sub create_block_file {
    my $file    = shift // die "Missing file to create block device";
    my $st      = stat('/dev/null');
    my $major   = major($st->rdev);
    my $minor   = minor($st->rdev);

    if( -e $file ) {
        die "File exists but is not a block file" if !-b $file;
        return 1;
    }

    my $result = mknod($file, S_IFBLK|0600, makedev($major,$minor+1));
    warn "Failed to create block file '$file'. Error: " . $! if $result == -1;
    return $result
}

package PVE::Cluster;

    sub get_clinfo {
        { cluster => { name => 'storpool' } }
    }
'o_0';
