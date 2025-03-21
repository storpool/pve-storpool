# SPDX-FileCopyrightText: StorPool <support@storpool.com>
# SPDX-License-Identifier: BSD-2-Clause

PVE_MODULES= \
		PVE/HA/Resources/Custom/StorPoolPlugin.pm \
		PVE/Storage/Custom/StorPoolPlugin.pm \


PREFIX?=	   /usr
SHAREDIR?=	   ${PREFIX}/share
PVE_PERL?=	   ${SHAREDIR}/perl5
LIB_SP?=       ${PREFIX}/lib/storpool

BINOWN?=	root
BINGRP?=	root
BINMODE?=	755

SHAREOWN?=	${BINOWN}
SHAREGRP?=	${BINGRP}
SHAREMODE?=	644

INSTALL?=	install
INSTALL_PROGRAM?=	${INSTALL} -o ${BINOWN} -g ${BINGRP} -m ${BINMODE}
INSTALL_DATA?=	${INSTALL} -o ${SHAREOWN} -g ${SHAREGRP} -m ${SHAREMODE}

MKDIR_P?=	mkdir -p -m 755

all:
		# Nothing to do here

install: all
		{ \
			set -e; \
			for relpath in ${PVE_MODULES}; do \
				${MKDIR_P} -- "${DESTDIR}$$(dirname -- "${PVE_PERL}/$$relpath")"; \
				${INSTALL_DATA} -- "lib/$$relpath" "${DESTDIR}${PVE_PERL}/$$relpath"; \
			done; \
			\
		}

clean:
		# Nothing to do here
test:
	prove -l -Itlib/ t/
.PHONY:		all install clean
