#!/bin/sh
# Disable / shutdown: stop the node_exporter daemon.
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $*" >> /tmp/debug_apkg

# killall matches the process name (comm = "node_exporter"), so it hits only the
# binary -- not the lifecycle shell scripts (comm "sh") or the CGI (comm "python3").
killall node_exporter 2>/dev/null

# True if the node_exporter binary is still running. We match comm exactly via
# /proc rather than `ps | grep node_exporter`: the install dir, this script and
# the CGI all contain "node_exporter", so a loose grep would never terminate the
# loop -- and it would depend on whether the device's `ps` prints the full
# command line. comm is exactly "node_exporter" for the binary only.
ne_running() {
	for c in /proc/[0-9]*/comm; do
		[ -r "$c" ] || continue
		[ "$(cat "$c" 2>/dev/null)" = node_exporter ] && return 0
	done
	return 1
}

# Wait for it to actually exit before returning. The WD framework runs stop.sh
# then start.sh on a disable->enable (and our Restart does the same); if we
# returned while node_exporter was still terminating, daemon.sh would see the
# dying process, think it's "already running", skip the relaunch -- and the
# service would end up DOWN. So block until it's gone, escalating to SIGKILL.
i=0
while [ "$i" -lt 10 ] && ne_running; do
	sleep 1
	i=$((i + 1))
done
if ne_running; then
	killall -9 node_exporter 2>/dev/null
	sleep 1
fi
exit 0
