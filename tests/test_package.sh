#!/bin/sh
# Post-build integration check: round-trip a produced .bin and confirm it
# unpacks to the expected files with an ARM node_exporter. Run AFTER build.sh.
#
#   sh tests/test_package.sh [packages/MyCloudEX2Ultra_node_exporter_<ver>.bin]
#
# With no argument it picks the first packages/*_node_exporter_*.bin.
#
# A WD .bin is a binary APKG header (magic + metadata + XOR checksum + payload
# length; ~204 bytes for mksapkg v2.0) followed by a gzipped tar. We locate the
# gzip stream by its magic rather than hardcoding the header size.
set -e

BIN="${1:-}"
if [ -z "$BIN" ]; then
	BIN="$(find packages -maxdepth 1 -name '*_node_exporter_*.bin' 2>/dev/null | sort | head -n1)"
fi
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
	echo "usage: $0 <package.bin>  (or run ./build.sh first)" >&2
	exit 1
fi
echo "Inspecting: $BIN"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Locate the gzipped tar payload (first gzip magic 1f 8b 08 in the file).
OFFSET="$(python3 - "$BIN" <<'PY'
import sys
with open(sys.argv[1], "rb") as fh:
    head = fh.read(8192)
print(head.find(b"\x1f\x8b\x08"))
PY
)"
if [ -z "$OFFSET" ] || [ "$OFFSET" -lt 200 ]; then
	echo "FAIL: no gzip payload after an APKG header (offset=$OFFSET)" >&2
	exit 1
fi
echo "PASS: APKG header present; gzip payload starts at byte $OFFSET"

# 2. The payload must list as a tar.
LIST="$TMP/list.txt"
if ! tail -c "+$((OFFSET + 1))" "$BIN" | tar tzf - > "$LIST" 2>/dev/null; then
	echo "FAIL: payload is not a gzip tar" >&2
	exit 1
fi
echo "PASS: payload unpacks as a gzip tar ($(wc -l < "$LIST" | tr -d ' ') entries)"

# 3. All required files must be present.
REQUIRED="apkg.rc install.sh init.sh start.sh stop.sh clean.sh remove.sh \
libexec/daemon.sh cgi-bin/node_exporter.py cgi-bin/nelib.py web/index.html \
web/node_exporter.png bin/node_exporter"
MISSING=0
for entry in $REQUIRED; do
	pat="$(printf '%s' "$entry" | sed 's/\./\\./g')"
	if grep -Eq "(^|/)${pat}\$" "$LIST"; then
		echo "  ok: $entry"
	else
		echo "  MISSING: $entry" >&2
		MISSING=1
	fi
done
if [ "$MISSING" -ne 0 ]; then
	echo "---- tar contents ----" >&2
	cat "$LIST" >&2
	echo "FAIL: required files missing" >&2
	exit 1
fi
echo "PASS: all required files present"

# 4. No build cruft should be packaged.
if grep -Eq "(^|/)__pycache__/" "$LIST"; then
	echo "FAIL: __pycache__ leaked into the package" >&2
	exit 1
fi
echo "PASS: no __pycache__ cruft"

# 5. node_exporter must be an ARM binary (armv7 for the EX2 Ultra).
tail -c "+$((OFFSET + 1))" "$BIN" | tar xzf - -C "$TMP" 2>/dev/null
NE="$(find "$TMP" -type f -name node_exporter | head -n1)"
if [ -z "$NE" ]; then
	echo "FAIL: node_exporter not found after extraction" >&2
	exit 1
fi
DESC="$(file -b "$NE")"
echo "node_exporter: $DESC"
if ! printf '%s' "$DESC" | grep -q "ARM"; then
	echo "FAIL: node_exporter is not an ARM binary" >&2
	exit 1
fi
echo "PASS: node_exporter is an ARM binary"

echo "ALL PACKAGE CHECKS PASSED"
