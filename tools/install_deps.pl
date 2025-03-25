#!/usr/bin/env perl
use v5.16;
use strict;
use warnings;
use Config;
use CPAN;

die "Only Linux is supported" if $^O ne 'linux';

my $distro = lc( $Config{cf_by} || '' );

# Overwrite distro
$distro = lc($ARGV[0]) if @ARGV;

die "Missing distro\nUse ARGV[0] to provide one - ./install_deps.pl ubuntu" if !$distro;

if( !-t STDIN ){
    print STDERR "This script is intended to be used only by a user with tty!\n";
    print STDERR "It can block at the initial CPAN configuration\n";
    exit(1);
}

# Mint is Ubuntu
my $DEPS = {
    'Config::IniFiles'  => { debian => 'libconfig-inifiles-perl',                ubuntu => 'libconfig-inifiles-perl' },
    'JSON'              => { debian => 'libjson-perl',                           ubuntu => 'libjson-perl' },
    'LWP::UserAgent'    => { debian => 'libwww-perl liblwp-protocol-https-perl', ubuntu => 'libwww-perl' },
# Test depends
    'unconstant'        => {}, # Disables constant inlining
};


foreach my $pkg ( keys %$DEPS ) {
    next if test_dep_use( $pkg );

    say "Trying to install $pkg";

    my $cfg         = $DEPS->{ $pkg } || {};
    my $os_packet   = $cfg->{ $distro };

    if( $os_packet ){
        say "Install OS packet $os_packet";
        install_os_packet( $distro, $os_packet );
    } else {
        say "Trying to install via CPAN";
        install_cpan_module( $pkg );
    }
}

sub test_dep_use {
    my $mod = shift || die "Missing module to test";

    $mod =~ s{::}{/}g;

    my $res = eval { require "$mod.pm" };

    return if $@;
    return 1;
}

sub install_os_packet {
    my $distro = shift || die "Missing distro to install";
    my $packet = shift || die "Missing os packet to install";

    state $cli = {
        debian => 'apt install --assume-yes ',
        ubuntu => 'apt install --assume-yes ',
    };
    my $cmd = $cli->{$distro};

    die "Don't know how to install OS packet for $distro" if !$cmd;


    print qx/$cmd $packet/;
}

sub install_cpan_module {
    my $module = shift || die "Missing module";

    CPAN::Shell->install( $module );
}
