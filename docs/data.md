<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# Definitions of the formats for serializing/storing StorPool Proxmox VE data

## General remarks

Note that boolean values are encoded as "0" or "1" when represented as strings.

## Object names stored in the Proxmox VE database

The object name is stored as a list of dash-separated key/value pairs.
The key is a single character.
If the value is an empty string, it either denotes a null value or an empty string
depending on whether the property is marked as nullable.

- `V` or `S`: integer: the object name format version, the constant integer 0.
  If the key is `V`, the data is stored in a StorPool volume; `S` denotes a snapshot.
- `g`: string: the StorPool global ID of the volume or snapshot
- `t`: string: the Proxmox VE content type of the object, e.g. "images", "iso", etc.
- `v`: integer, nullable: the Proxmox VM that this object belongs to, if any
- `p`: string, nullable: the StorPool global ID of the object's parent, if any.
  A parser may need to send a StorPool `Volume` or `Snapshot` API query to obtain
  more information needed to build a full object name for the parent.
- `B`: boolean, nullable: is this a base image, e.g. a disk belonging to a VM template as
  opposed to one belonging to an actual VM
- `c`: string, nullable: an optional comment describing e.g. an ISO image or a cloud
  root disk image.
  For the moment this string may not contain whitespace or dashes.

## Volume and snapshot tags

- `virt`: string: the constant string "pve"
- `pve-cluster`: string: the short name ("slug") of the Proxmox VE cluster to distinguish
   volumes defined on it from ones defined for other Proxmox VE clusters sharing the same
   StorPool deployment
- `pve-type`: string: the content type of the Proxmox VE object stored in this volume or
  snapshot, e.g. "images", "iso", etc.
- `pve-vm`: integer: the ID of the Proxmox VE virtual machine that this object belongs to
- `pve-base`: boolean: is this a base image, e.g. a disk belonging to a VM template as
  opposed to one belonging to an actual VM
- `pve-comment`: string: an optional comment describing e.g. an ISO image or a cloud
  root disk image.
  For the moment this string may not contain whitespace or dashes.
