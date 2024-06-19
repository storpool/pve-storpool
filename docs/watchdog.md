<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# StorPool HA watchdog replacement

PVE clusters offer a [High Availability](https://pve.proxmox.com/pve-docs/chapter-ha-manager.html)
feature that automatically migrates virtual machines when their host loses connectivity to
the cluster. As part of this functionality, a watchdog service monitors cluster status on each host,
and fences it by rebooting the host when quorum is lost for a period of time.

Since StorPool relies on its own internal clustering mechanism, it can remain unaffected by
partitions in PVE's cluster, making these reboots undesirable, and potentially harmful with
regards to storage performance and availability. To prevent such issues, we've developed a
replacement watchdog service (`sp-watchdog-mux`), which stops any running virtual machines,
and restarts only select services on the host.

For details on enabling the replacement watchdog service,
see the [Installation instructions](install.md).