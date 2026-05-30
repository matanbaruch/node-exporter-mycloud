#!/bin/sh
# Uninstall: stop the daemon, then purge binaries, config/state and dashboard
# symlinks. $1 = installed app path.
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $*" >> /tmp/debug_apkg

INSTALL_DIR="${1:-/mnt/HD/HD_a2/Nas_Prog/node_exporter}"
STATE_DIR="/mnt/HD/HD_a2/.systemfile/node_exporter"

# killall matches the binary's process name only (not the shell scripts / CGI).
killall node_exporter 2>/dev/null

rm -rf "$INSTALL_DIR"
rm -rf "$STATE_DIR"
rm -f /var/www/cgi-bin/node_exporter.py
rm -rf /var/www/apps/node_exporter
exit 0
