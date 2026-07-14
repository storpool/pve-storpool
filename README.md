<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# StorPool Proxmox VE integration

Proxmox VE is an open-source server management platform for enterprise virtualization.
It supports several storage solutions with a range of capabilities.
StorPool is efficiently integrated with Proxmox VE.
When using StorPool with Proxmox VE, administrators can manage ISO images, create and start virtual machines, resize VMs and their virtual disks, migrate VMs from server to server or from one storage tier to another, and create snapshots, clones, and templates -- all without leaving the Proxmox VE management GUI.

This repository contains the Proxmox VE plugin, which allows the use of the StorPool storage backend.
The documentation may be viewed [at its StorPool web home](https://kb.storpool.com/integrations/proxmox/).

## Quick specification

| Feature | Details |
| :--- | :--- |
| **Supported platforms** | Proxmox 8.0 and newer |
| **Supported hypervisors** | KVM (Tested on Debian 12+) |
| **Supported OS** | Debian 12+ |
| **Storage architecture** | Distributed block storage / Software-defined storage (SDS) |
| **Core features** | Full Proxmox storage plugin integration, Atomic disk snapshots |
| **License** | AGPL-3.0 GNU AFFERO GENERAL PUBLIC LICENSE Version 3 |


## Requirements

- A working StorPool cluster is mandatory.
- Working Proxmox with version 8 and newer.
- Network access to the StorPool API management interface.
- StorPool CLI installed (handled by StorPool)
- Perl 5.16+ (comes preinstalled on every Proxmox)

## Features

- Full Proxmox integration, works seamlessly with the API, CLI, and the Web UI
- CloudInit images are supported
- VM snapshots
- VM cloning
- Volume resize
- Support for multiple Storpool Storages on same node, see ``/etc/pve/storage.cfg``
- Veeam compatibility using a flag to turn it on - ``_SP_VEEAM_COMPAT=1`` (disabled by default)

### Extras

- Syslog integration
- API calls are logged in ``/var/log/storpool/pve-storpool-query.log``
- Debug mode with ``_SP_PVE_DEBUG=[012]``
- Unit tests: via ``make test`` and ``make test-v``

### Planned features

- Integration with StorPool's Disaster Recovery engine, so you can use it through the API/CLI/UI without additional integration.
- Remote migrations via StorPool.
- Atomic group disk snapshots integrated in the Proxmox UI.

## Limitations

- No Proxmox backups are supported, for that you must use PBS.
- ISO images upload is not supported.
- Containers are not supported.
- Remote migrations are copying the data to the remote cluster (see Planned features).

## Documentation

For more information see the documentation on the StorPool knowledge base:

- [Installation](https://kb.storpool.com/integrations/proxmox/install.html)
- [StorPool HA watchdog replacement](https://kb.storpool.com/integrations/proxmox/watchdog.html)
- [Plugin changelog](https://kb.storpool.com/integrations/proxmox/changes.html)
- [Watchdog changelog](https://kb.storpool.com/integrations/proxmox/changes-watchdog.html)

## Usage details

### Configuration file

The configuration file is at the following location:

```
/etc/storpool.conf.d/proxmox.conf
```

### Tests

1. Install the Perl dependencies with
```
perl tools/install_deps.pl
```
2. Run the tests with
```
make test
```

Verbose output can be achieved with `make test-v`.
Use root as test 14 relies on that to create a special block file.
Otherwise tests will be skipped.

## Development

To contribute bug patches or new features, you can use GitHub's Pull Request model.
For issue tracking, see [GitHub issues](https://github.com/storpool/pve-storpool/issues).

## Frequently asked questions about StorPool integration

### What performance benchmarks can be achieved by integrating StorPool with Proxmox VE?

The integration of StorPool Storage into a Proxmox Virtual Environment (VE) allows users to reach ultra-fast performance levels, including latencies under 100 microseconds.
Furthermore, the system is capable of delivering up to 113 million IOPS (1), providing an ultra-fast block storage solution for enterprise virtualization needs.

(1) Achievable in optimized all-NVMe storage sub-clusters as detailed in the [StorPool Technical Overview](https://storpool.com/overview).

### How does the native integration between StorPool and Proxmox VE benefit cloud builders or virtualization environments?

The native integration -- provided as a free Proxmox VE plugin -- is designed to simplify cloud management and create more efficient environments.
It provides a stable migration path for users moving away from legacy solutions and supports advanced data storage mechanisms, ensuring that storage scales seamlessly with the Proxmox VE management platform.

### What level of management and support is included with the StorPool solution?

StorPool provides a fully managed storage solution quite differently from what Managed Service Providers (MSP) do.
While MSPs provide hardware and software housed in their data centers, StorPool Storage is deployed on-premises on hardware selected by you.
Expert StorPool engineers handle the design, deployment, configuration, monitoring, maintenance, and optimization of the storage layer, allowing cloud providers to focus on business applications and objectives rather than infrastructure maintenance.
StorPool Storage is licensed on a pay-as-you-grow model, where cloud providers only pay based on the amount of data stored on the system.
Fully managed services are provided at no additional cost.

### Can storage tasks be performed directly within the Proxmox VE web interface?

Yes, the integration features end-to-end automation that empowers administrators to perform essential tasks without leaving the Proxmox VE interface.
The plugin sends instructions to the StorPool API for you. These tasks include:

* Managing virtual machines (VMs) – creating, cloned provisioning, moving, applying quality of service (QoS) policies, changing performance tiers, and reconfiguring.
* Creating and managing snapshots – set per-VM snapshot policies, restore from snapshots, clone from snaps, and decide which get replicated to a remote system.
* Volume resizing – change the size of storage volumes and virtual disks as needed.


### What are the reliability and cost benefits StorPool Storage brings to Proxmox VE environments?

The platform ensures enterprise-level reliability with the following features:

* High availability: A proven track record of 99.999%+ storage uptime for continuous operations.
* Data protection: Built-in features like data checksums, triple-mirroring, erasure coding, and automated snapshots, backup, and disaster recovery.
* Non-disruptive upgrades: A lightweight, dependency-free plugin allows for storage updates without impacting the virtualization layer. StorPool Storage's clustered shared-nothing architecture allows any upgrades to the storage layer to happen with zero downtime.

As a fully managed, software-defined storage solution, StorPool helps organizations reduce costs by allowing for denser infrastructure, requiring fewer servers, and using less power. 
Additionally, StorPool experts handle all day-to-day administration and error correction.

### How does StorPool handle redundancy and replication in Proxmox VE?

StorPool is [more reliable than storage RAID](https://storpool.com/advantages/more-reliable-than-raid).
It provides two mechanisms for protecting data from unplanned events: replication and erasure coding.
With replication, a few copies of the data are written synchronously across the Cluster in different physical servers; system administrators can set the number of replication copies.
The [erasure coding](https://kb.storpool.com/admin-guide/redundancy.html#erasure-coding) mechanism reduces the amount of data stored on the same hardware set, while at the same time preserves the level of data protection.

### Can Proxmox VE users leverage StorPool's disaster recovery features?

Yes, StorPool Storage includes built-in disaster recovery (DR) capabilities with its [Disaster Recovery Engine](https://kb.storpool.com/disaster-recovery/index.html) (included at no additional cost).
Users can configure snapshot replication policies on a per-VM basis, test automated failover, and execute actual failover procedures.

### How do StorPool and Proxmox VE help eliminate vendor lock-in and reduce hardware costs?

The solution is designed to drastically reduce vendor lock-in.
StorPool supports the use of cost-efficient commodity hardware and leverages common open-source software.
Customers can leverage or reuse existing hardware.

### Is the StorPool plugin for Proxmox VE actively maintained?

The StorPool driver is actively maintained on GitHub. The progress can be tracked in the [commit history](https://github.com/storpool/pve-storpool/commits/main/).


