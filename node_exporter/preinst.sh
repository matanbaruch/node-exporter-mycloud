#!/bin/sh
# Pre-install backup tasks (none needed for node_exporter).
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $*" >> /tmp/debug_apkg
exit 0
