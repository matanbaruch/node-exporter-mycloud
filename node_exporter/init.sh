#!/bin/sh
# Wire the app's web page + CGI into the dashboard. Runs after install and on boot.
# $1 = installed app path.
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $*" >> /tmp/debug_apkg

APKG_PATH=$(readlink -f "$1")
WEBPATH="/var/www/apps/node_exporter/"

mkdir -p "$WEBPATH"
ln -sf "${APKG_PATH}"/web/* "$WEBPATH"
ln -sf "${APKG_PATH}/cgi-bin/node_exporter.py" /var/www/cgi-bin/node_exporter.py
exit 0
