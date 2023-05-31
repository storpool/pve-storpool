<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# Installing the StorPool Proxmox integration

## Install the StorPool storage plugin file

Note: these steps will soon be replaced by installing a Debian package.

- Locate the Perl library tree where the Proxmox VE files are installed;
  in a typical setup that should be the `/usr/share/perl5/` tree.
  Make sure the is a `PVE/Storage/` directory within it.
- If necessary, create the `PVE/Storage/Custom/` subdirectory in that tree:
  ``` sh
  install -d -o root -g root -m 755 /usr/share/perl5/PVE/Storage/Custom
  ```
- Copy the `StorPoolPlugin.pm` file into the `PVE/Storage/Custom/` subdirectory:
  ``` sh
  install -o root -g root -m 644 StorPoolPlugin.pm /usr/share/perl5/PVE/Storage/Custom/
  ```
- Perform these steps on all the Proxmox VE hosts which will need to access
  StorPool-backed volumes and snapshots.

## Check the status of the StorPool and Proxmox installation

- Make sure the StorPool client (the `storpool_block` service) is operational:
  ``` sh
  systemctl status storpool_block.service
  ```
- Make sure the StorPool configuration includes the API access variables:
  ``` sh
  storpool_confshow -e SP_API_HTTP_HOST SP_API_HTTP_PORT SP_AUTH_TOKEN SP_OURID
  ```
- Make sure the StorPool cluster sees this client as operational:
  ```
  storpool service list
  storpool client status
  ```
- Make sure the Proxmox cluster is operational and has a sensible name configured:
  ``` sh
  pvesh get /cluster/status
  pvesh get /cluster/status -output-format json | jq -r '.[] | select(.id == "cluster") | .name'
  ```

## Create a StorPool-backed Proxmox VE storage

Note: this part may be partly automated by a command-line helper tool.

- Choose a StorPool template to use for the storage entry:
  ``` sh
  storpool template list
  ```
- Create a storage entry, specifying the StorPool template to use and
  some additional tags to set on each StorPool volume and snapshot, e.g.
  specifying a QoS tier:
  ``` sh
  pvesm add \
    'storpool' \
    'sp-nvme' \
    -shared true \
    -content 'images,iso' \
    -extra-tags 'tier=high' \
    -template 'nvme'
  ```
- Make sure Proxmox VE can query the status of the created storage:
  ``` sh
  pvesm status
  ```

## Pre-populate the Proxmox storage with some volumes and snapshots

This step is optional.
At present there is not much benefit in keeping raw disk images
(e.g. cloud images for various Linux distributions and other OS's) on
StorPool-backed storage, since Proxmox VE will still insist on making
a full clone of the disks.
However, CD/DVD ISO 9660 images may be kept on StorPool-backed storage so that
they may easily be attached to any VM started anywhere.

Note: the process of copying the data into the StorPool volumes and snapshots is
not shown here.
It will soon be partly automated by a command-line helper tool.

- Create a StorPool snapshot that contains a CD/DVD ISO 9660 image.
  Set the appropriate tags so that the StorPool Proxmox VE plugin will be
  able to recognize it as one of its own:
  ``` sh
  storpool snapshot '~kr.b.f' \
  tag virt='pve' \
  tag pve-loc='pmox-test' \
  tag pve='sp-nvme' \
  tag pve-type='iso' \
  tag pve-comment='debian-11.7.0-amd64-DVD-1'
  ```
- Make sure Proxmox VE can see this DVD ISO 9660 image; look for
  a `sp-nvme:debian-11.7.0-amd64-DVD-1-sp-kr.b.f.iso` "iso" image:
  ``` sh
  pvesm list sp-nvme
  ```
- Create a StorPool snapshot that contains a Debian cloud image.
  Set the appropriate tags so that the StorPool Proxmox VE plugin will be
  able to recognize it as one of its own:
  ``` sh
  storpool snapshot '~kr.b.8' \
  tag virt='pve' \
  tag pve-loc='pmox-test' \
  tag pve='sp-nvme' \
  tag pve-type='images' \
  tag pve-comment='debian-11-nocloud-amd64-20230515'
  ```
- Make sure Proxmox VE can see this DVD ISO 9660 image; look for
  a `sp-nvme:img-debian-11-nocloud-amd64-20230515-sp-kr.b.8.raw` "images" image:
  ``` sh
  pvesm list sp-nvme
  ```

## Create a Proxmox VE virtual machine from the cloud image

- Create a Proxmox VE virtual machine, importing the Debian cloud image as
  its root disk (Proxmox VE will still make a full copy though):
  ``` sh
  qm create 616 \
  -boot order='scsi0' \
  -cores 1 \
  -name 'sp-pp-test-deb-1' \
  -ostype 'l26' \
  -scsi0 'sp-nvme:0,discard=on,format=raw,import-from=sp-nvme:img-debian-11-nocloud-amd64-20230515-sp-kr.b.8.raw,iothread=1,size=2G' \
  -scsihw 'virtio-scsi-single' \
  -smbios1 'uuid=c95cb298-fe70-4b53-84dd-fb3b525fff41' \
  -storage 'sp-nvme' \
  -ciuser 'jrl' \
  -cipassword 'mellon' \
  -scsi2 'local:cloudinit,media=cdrom' \
  -serial0 'socket'
  ```
- Add a network interface to the VM before starting it:
  ``` sh
  qm set 616 -net0 'model=virtio,bridge=vmbr0,firewall=1'
  ```
- Start the VM:
  ``` sh
  qm start 616
  ```
