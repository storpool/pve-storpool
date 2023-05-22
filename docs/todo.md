<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# To-do list for the StorPool Proxmox VE integration plugin

## Discuss with others, determine priority

- getting the cluster name from the storage configuration: who will make sure that
  all the definitions within the same Proxmox VE cluster actually have the same cluster name?
- ask Johan whether they want to use the Proxmox VE backup server and, if needed, figure out
  how to integrate it with our StorPool plugin and with StorPool volumecare

## High priority

- `activate_storage()`: require that the template already exists instead of trying to create it
- get the test cluster name from the storage configuration or use the StorPool
  cluster ID or something

## Medium priority

- `status()`: this should probably be changed, it processes the output of `disk list` now,
  which was the old way of doing things; should we use `template status` in some way instead?
- `sp_clean_snaps()`: figure out how to do that with global IDs and tags.
  It ought to be straightforward.

## Low priority

- `sp_temp_create()`: only ignore "this template already exists" errors
  (this may go away if `activate_storage()` is changed to only check for
  a preexisting template)
- `list_volumes()`, `sp_encode_volsnap()`, `parse_volname()`, `volume_size_info()`:
  figure out whether we ever need to store non-raw volumes.
  Either we will need that to store cloud-init files, or we will need to figure out
  what kind of capability (feature) we are missing so we can store raw cloud-init
  files onto StorPool volumes.
- `list_volumes()`: apply the images/rootdir fix

## Driver functions/methods to reenable/revamp

- `volume_resize`
- `sp_vol_create_from_snap`
- `deactivate_storage`
- `volume_snapshot`
- `volume_snapshot_delete`
- `volume_snapshot_rollback`
- `get_subdir`
- `delete_store`
