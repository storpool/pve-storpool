<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# To-do list for the StorPool Proxmox VE integration plugin

## Discuss with others, determine priority

- figure out how to integrate the Proxmox backup server with our StorPool plugin and
  with StorPool volumecare

## High priority

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
