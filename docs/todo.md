<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# To-do list for the StorPool Proxmox VE integration plugin

## Discuss with others, determine priority

- ask Johan whether they want to use the Proxmox VE backup server and, if needed, figure out
  how to integrate it with our StorPool plugin and with StorPool volumecare

## High priority

- figure out why the web UI shows a question mark icon next to the storage entry in
  the hierarchy tree
- look into replacing the commands that Proxmox invokes for copying data into StorPool

## Medium priority

- `status()`: this should probably be changed, it processes the output of `disk list` now,
  which was the old way of doing things; should we use `template status` in some way instead?

## Low priority

- `list_volumes()`, `sp_encode_volsnap()`, `parse_volname()`, `volume_size_info()`:
  figure out whether we ever need to store non-raw volumes.
  We will need that to store cloud-init files.
- `list_volumes()`: apply the images/rootdir fix

## Driver functions/methods to reenable/revamp

- `deactivate_storage`
- `get_subdir`
- `delete_store`
