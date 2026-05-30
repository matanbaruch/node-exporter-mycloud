#!/bin/sh
# Ensure node_exporter is running with the configured flags.
# Shared by start.sh (boot/enable) and the CGI (Start/Restart/Save).
# Usage: daemon.sh [install_dir]
#
# node_exporter is stateless: all settings are command-line flags. The dashboard
# CGI renders the full flag line into CONFIG (single source of truth, built by
# nelib.render_config) on every Save; this script just reads it back and runs it.
# With no config yet (fresh install) it falls back to the default listen address.
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $* $PWD" >> /tmp/debug_apkg

INSTALL_DIR="${1:-/mnt/HD/HD_a2/Nas_Prog/node_exporter}"
STATE_DIR="/mnt/HD/HD_a2/.systemfile/node_exporter"
CONFIG="$STATE_DIR/config"
TEXTFILE_DIR="$STATE_DIR/textfile"
NODE_EXPORTER="${INSTALL_DIR}/bin/node_exporter"

# True if the node_exporter binary is running. We match the process *name*
# (/proc/<pid>/comm == "node_exporter") rather than grepping `ps`, because the
# binary, this script's dir and the CGI all share the string "node_exporter":
# a loose `ps | grep node_exporter` would match the scripts/CGI too (so the
# "already running" guard would always be true and the binary would never
# launch), and it would also depend on whether the device's `ps` prints the
# full command line. comm is exactly "node_exporter" for the binary and "sh" /
# "python3" for the scripts and CGI, so the match is unambiguous under any `ps`.
ne_running() {
	for c in /proc/[0-9]*/comm; do
		[ -r "$c" ] || continue
		[ "$(cat "$c" 2>/dev/null)" = node_exporter ] && return 0
	done
	return 1
}

mkdir -p "$STATE_DIR"
# Always present so the textfile collector has somewhere to read from when enabled.
mkdir -p "$TEXTFILE_DIR"

# Read the pre-rendered flag line written by the CGI. Default to :9100 if unset.
ARGS=""
if [ -f "$CONFIG" ]; then
	ARGS="$(sed -n 's/^ARGS=//p' "$CONFIG" | head -n1)"
fi
[ -n "$ARGS" ] || ARGS="--web.listen-address=:9100"

if ne_running; then
	echo "node_exporter already running"
	exit 0
fi

if [ ! -x "$NODE_EXPORTER" ]; then
	echo "ERROR: node_exporter not found at $NODE_EXPORTER"
	exit 1
fi

# shellcheck disable=SC2086  # ARGS must word-split into separate flags
nohup "$NODE_EXPORTER" $ARGS \
	>> "$STATE_DIR/node_exporter.log" 2>&1 &

# Give it a moment to bind so a status fetch right after this doesn't race startup.
i=0
while [ "$i" -lt 10 ] && ! ne_running; do
	sleep 1
	i=$((i + 1))
done
if ne_running; then
	echo "node_exporter started ($ARGS)"
else
	echo "WARNING: node_exporter did not stay up; see $STATE_DIR/node_exporter.log"
fi
exit 0
