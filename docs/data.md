<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# Definitions of the formats for serializing/storing StorPool Proxmox VE data

## General remarks

Note that boolean values are encoded as "0" or "1" when represented as strings.

## Object names stored in the Proxmox VE database

The object name is stored as a string resembling a filename, but structured.
The types of objects supported by the StorPool plugin are as follows:

- `vm-<vm_id>-disk-<disk_id>-sp-<global_id>.raw`: volume: a disk attached to a VM
- `base-<vm_id>-disk-<disk_id>-sp-<global_id>.raw`: snapshot: a disk attached to a VM template.
- `snap-<vm_id>-disk-<disk_id>-<snapshot_id>-p-<parent_id>-sp-<global_id>.raw`: snapshot: a Proxmox
  snapshot of a VM disk.
- `snap-<vm_id>-state-<snapshot_id>-sp-<global_id>.raw`: volume: a Proxmox snapshot of
  the current state (RAM, CPU, etc.) of a running VM.
- `img-<id>-sp-<global_id>.raw`: snapshot: a "freestanding" disk image, one not
  attached to any VM, but uploaded to the StorPool-backed storage in some other way.
  This may be e.g. a cloud image to be imported as a VM's root disk.
- `<id>-sp-<global_id>.iso`: snapshot: an ISO image to attach to VMs as a CD/DVD drive.

Some field clarifications:

- The `vm_id` portion must consist of digits only and represent a decimal non-negative
  integer number not less than 100.
- The `disk_id` portion must consist of digits only and represent a decimal non-negative
  integer number.
- The `global_id` portion must be a valid StorPool global ID; it identifies
  the volume or snapshot where the data is stored.
- The `snapshot_id` portion must be in the Proxmox identifier format.
- The `parent_id` portion must be a valid StorPool global ID.
- The `id` portion must be in the Proxmox identifier format.

## Volume and snapshot tags

- `virt`: string: the constant string "pve"
- `pve-loc`: string: the short name ("slug") of the Proxmox VE cluster to distinguish
   volumes defined on it from ones defined for other Proxmox VE clusters sharing the same
   StorPool deployment
- `pve`: string: the storage-id of the Proxmox storage that this volume or snapshot
  belongs to
- `pve-type`: string: the content type of the Proxmox VE object stored in this volume or
  snapshot, e.g. "images", "iso", etc.
- `pve-vm`: integer: the ID of the Proxmox VE virtual machine that this object belongs to
- `pve-fqvmn`: the fully-qualified VM name: the contents of the `pve-loc` and `pve-vm`
  tags, separated by a colon (`:`)
- `pve-disk`: integer: a monotonically increasing "number" of the disk within that VM
- `pve-base`: boolean: is this a base image, e.g. a disk belonging to a VM template as
  opposed to one belonging to an actual VM
- `pve-comment`: string: an optional comment describing e.g. an ISO image or a cloud
  root disk image.
- `pve-snap`: string: the name of the VM snapshot that this disk is part of, if any
- `pve-snap-v`: string: the volume that this disk represents in the VM snapshot, if any
