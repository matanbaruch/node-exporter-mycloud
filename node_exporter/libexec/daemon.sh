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

mkdir -p "$STATE_DIR"
# Always present so the textfile collector has somewhere to read from when enabled.
mkdir -p "$TEXTFILE_DIR"

# Read the pre-rendered flag line written by the CGI. Default to :9100 if unset.
ARGS=""
if [ -f "$CONFIG" ]; then
	ARGS="$(sed -n 's/^ARGS=//p' "$CONFIG" | head -n1)"
fi
[ -n "$ARGS" ] || ARGS="--web.listen-address=:9100"

# Already running? Match the daemon's full binary path, not a bare "node_exporter"
# -- the install dir, this script and the CGI all contain "node_exporter", so a
# loose match would always be true and the binary would never actually launch.
# busybox-friendly ps|grep (pgrep -f isn't always present).
# shellcheck disable=SC2009
if ps 2>/dev/null | grep -v grep | grep -q 'node_exporter/bin/node_exporter'; then
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
# shellcheck disable=SC2009
while [ "$i" -lt 10 ] && ! ps 2>/dev/null | grep -v grep | grep -q 'node_exporter/bin/node_exporter'; do
	sleep 1
	i=$((i + 1))
done
# shellcheck disable=SC2009
if ps 2>/dev/null | grep -v grep | grep -q 'node_exporter/bin/node_exporter'; then
	echo "node_exporter started ($ARGS)"
else
	echo "WARNING: node_exporter did not stay up; see $STATE_DIR/node_exporter.log"
fi
exit 0
