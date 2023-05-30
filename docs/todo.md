<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# To-do list for the StorPool Proxmox VE integration plugin

## Discuss with others, determine priority

- ask Johan whether they want to use the Proxmox VE backup server and, if needed, figure out
  how to integrate it with our StorPool plugin and with StorPool volumecare

## High priority

- `status()`: this should probably be changed, it processes the output of `disk list` now,
  which was the old way of doing things; should we use `template status` in some way instead?
- drop the `/etc/pve/storpool/proxmox.cfg` file handling, get the cluster name from
  the Proxmox cluster's configuration
- drop the `/etc/pve/storpool/api.cfg` file handling, go back to `storpool_confget`
- figure out why the web UI shows a question mark icon next to the storage entry in
  the hierarchy tree

## Medium priority

- create a monitoring/check tool for the qemu/kvm configuration of the running VMs
  (possibly also for the VM configuration?)
- create a trivial Debian package that installs the StorPool plugin and restarts
  the `pvedaemon` and `pveproxy` services

## Low priority

## Not planned immediately

- `list_volumes()`, `sp_encode_volsnap()`, `parse_volname()`, `volume_size_info()`:
  figure out whether we ever need to store non-raw volumes.
  We will need that to store cloud-init files.
- `list_volumes()`: apply the images/rootdir fix
- look into replacing the commands that Proxmox invokes for copying data into StorPool

## Driver functions/methods to reenable/revamp

- `deactivate_storage`
- `get_subdir`
- `delete_store`
