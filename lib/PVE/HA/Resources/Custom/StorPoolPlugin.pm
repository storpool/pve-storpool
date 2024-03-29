# SPDX-FileCopyrightText: StorPool <support@storpool.com>
# SPDX-License-Identifier: BSD-2-Clause

package PVE::HA::Resources::Custom::StorPoolPlugin;

use strict;
use warnings;

use PVE::Cluster;

use PVE::HA::Tools;

use base qw(PVE::HA::Resources);

sub type {
    return 'storpool';
}

sub verify_name {
    my ($class, $name) = @_;

    die ref($class)."->verify_name(name='$name') should not be invoked\n"
}

sub options {
    return {}
}

sub config_file {
    my ($class, $vmid, $nodename) = @_;

    die ref($class)."->config_file(vmid=$vmid, nodename='$nodename') should not be invoked\n"
}

sub exists {
    my ($class, $vmid, $noerr) = @_;

    die ref($class)."->exists(vmid=$vmid, noerr=$noerr) should not be invoked\n"
}

sub start {
    my ($class, $haenv, $id) = @_;

    die ref($class)."->start(haenv=..., id=$id) should not be invoked\n"
}

sub shutdown {
    my ($class, $haenv, $id, $timeout) = @_;

    die ref($class)."->shutdown(haenv=..., id=$id, timeout=$timeout) should not be invoked\n"
}

sub migrate {
    my ($class, $haenv, $id, $target, $online) = @_;

    die ref($class)."->migrate(haenv=..., id=$id, target='$target', online=$online) should not be invoked\n"
}

sub check_running {
    my ($class, $haenv, $vmid) = @_;

    die ref($class)."->check_running(haenv=..., vmid=$vmid) should not be invoked\n"
}

sub remove_locks {
    my ($self, $haenv, $id, $locks, $service_node) = @_;

    die ref($class)."->remove_locks(haenv=..., id=$id, locks=..., service_node='$service_node') should not be invoked\n"
}

sub get_static_stats {
    my ($class, $haenv, $id, $service_node) = @_;

    die ref($class)."->get_static_stats(haenv=..., id=$id, service_node='$service_node') should not be invoked\n"
}

1;
