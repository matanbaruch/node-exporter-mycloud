#!/bin/sh
# Revert the init step (remove dashboard symlinks). Config/state untouched.
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $*" >> /tmp/debug_apkg

rm -f /var/www/cgi-bin/node_exporter.py
rm -rf /var/www/apps/node_exporter
exit 0
