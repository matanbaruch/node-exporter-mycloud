#!/bin/sh
# Install the package payload into the persistent Nas_Prog location.
# $1 = extracted package path, $2 = Nas_Prog destination (per WD app convention).
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $*" >> /tmp/debug_apkg

INSTALL_DIR=$(readlink -f "$1")
NAS_PROG=$(readlink -f "$2")

cp -rf "${INSTALL_DIR}" "${NAS_PROG}"
exit 0
