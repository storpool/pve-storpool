<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# Changelog

All notable changes to the pve-storpool project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixes

- plugin:
    - fix a race when resizing a locally-attached volume

### Additions

- config validator:
    - add an experimental Rust tool, not distributed yet, for validating
      the current configuration of StorPool volumes attached to Proxmox
      virtual machines

### Other changes

- documentation:
    - installation instructions:
        - note that the `pvedaemon`, `pveproxy`, and `pvestatd` services need to be
          restarted after installing the StorPool plugin's Perl source file
        - provide installation instructions for the Debian package of the StorPool
          Proxmox plugin
        - drop some sections that did not really serve a useful purpose
    - drop the to-do list, it is tracked elsewhere at StorPool

## [0.2.0] - 2023-06-01

### Incompatible changes

- plugin:
    - do not declare support for OpenVZ templates (the `vztmpl` content type)
    - use the StorPool `VolumeTemplatesStatus` (`template status`) API query to
      determine the amount of used and free disk space for each storage
    - use the Proxmox cluster name (as returned by the `pvesh get /cluster/status`
      command) as the value for the `pve-loc` StorPool volume and snapshot tag;
      no longer look at the `/etc/pve/storpool/proxmox.cfg` file
    - use the configuration of the StorPool block client (as obtained by
      the `storpool_confget` command) for access to the StorPool API;
      no longer look at the `/etc/pve/storpool/api.cfg` file
    - remove (and do not automatically set) the `path` property of the storage;
      this changes the way Proxmox invokes the plugin's methods in several ways,
      among them the correct operation of backing a VM up and restoring it

### Additions

- plugin:
    - partially implement the `list_images()` plugin method so that e.g.
      unreferenced disk images may be found when destroying a VM
- documentation:
    - add this changelog file

### Fixes

- plugin:
    - use the `name` field of the StorPool volumes instead of their `globalId`
      field, since the latter may change when the volume is reverted to
      a snapshot
    - when reverting a volume to a snapshot, always detach it from all the hosts
      it is currently attached to; Proxmox does not do that beforehand for
      a currently running VM
    - validate ("untaint" in Perl-speak) the total size and stored size of
      a volume so that it may be used when migrating a volume to a different
      storage from the web UI
    - do not try to parse the internal value "state" for the `pve-disk` tag when
      looking for an available number to use as a VM disk "ID"

### Other changes

- documentation:
    - installation instructions:
        - remove the mention of the `vztmpl` content type
    - update the to-do list

## [0.1.0] - 2023-05-28

### Started

- Initial pre-release

[Unreleased]: https://github.com/storpool/pve-storpool/compare/release/0.2.0...main
[0.2.0]: https://github.com/storpool/pve-storpool/compare/release/0.1.0...release%2F0.2.0
[0.1.0]: https://github.com/storpool/pve-storpool/releases/tag/release%2F0.1.0
