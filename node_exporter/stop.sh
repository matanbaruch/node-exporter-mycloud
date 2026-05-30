#!/bin/sh
# Disable / shutdown: stop the node_exporter daemon.
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $*" >> /tmp/debug_apkg

# killall matches the process name (comm = "node_exporter"), so it hits only the
# binary -- not the lifecycle shell scripts (comm "sh") or the CGI (comm "python3").
killall node_exporter 2>/dev/null

# Wait for it to actually exit before returning. The WD framework runs stop.sh
# then start.sh on a disable->enable (and our Restart does the same); if we
# returned while node_exporter was still terminating, daemon.sh would see the
# dying process, think it's "already running", skip the relaunch -- and the
# service would end up DOWN. So block until it's gone, escalating to SIGKILL.
#
# The match string is the daemon's *full path* "node_exporter/bin/node_exporter":
# a bare "node_exporter" would also match this script, start.sh and the CGI
# (all live under .../node_exporter/...), making the loop never terminate.
# busybox-friendly ps|grep (pgrep -f isn't always present).
i=0
# shellcheck disable=SC2009
while [ "$i" -lt 10 ] && ps 2>/dev/null | grep -v grep | grep -q 'node_exporter/bin/node_exporter'; do
	sleep 1
	i=$((i + 1))
done
# shellcheck disable=SC2009
if ps 2>/dev/null | grep -v grep | grep -q 'node_exporter/bin/node_exporter'; then
	killall -9 node_exporter 2>/dev/null
	sleep 1
fi
exit 0
