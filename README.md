<!--
SPDX-FileCopyrightText: StorPool <support@storpool.com>
SPDX-License-Identifier: BSD-2-Clause
-->

# StorPool Proxmox VE integration

This repository contains the Proxmox VE plugin that allows the use of
the StorPool storage backend.
The documentation may be viewed [at its StorPool web home][repo].

## Tests
1. Install the Perl dependencies with
```
perl tools/install_deps.pl
```
2. Run the tests with
```
make test
```

> Verbose output can be achieved with `make test-v`
> Use root as test 14 relies on that to create a special block file. Tests will be skipped else.


[repo]: https://kb.storpool.com/storpool_integrations/proxmox/index.html "The documentation at StorPool"
