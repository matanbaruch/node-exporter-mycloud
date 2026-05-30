#!/bin/sh
# Build the WD My Cloud .bin for the node_exporter app. Runs INSIDE the Docker
# image (needs mksapkg-OS5 + glibc/libxml2/openssl). Driven by ../build.sh.
#
#   - reads the bundled node_exporter version from apkg.rc (single source of truth)
#   - downloads the official static linux-armv7 build and verifies its SHA-256
#   - packs everything into MyCloudEX2Ultra_node_exporter_<ver>.bin
#
# The EX2 Ultra is a Marvell Armada 385 (Cortex-A9, ARMv7), so we ship the
# linux-armv7 release; it is a statically linked Go binary with no libc needs.
set -e

cd "$(dirname "$0")"            # -> node_exporter/
APP_NAME="node_exporter"
MODELS="${MODELS:-MyCloudEX2Ultra}"
MKSAPKG="${MKSAPKG:-mksapkg-OS5}"
NE_VERSION="$(awk '/^Version:/{print $2}' apkg.rc)"

if [ -z "$NE_VERSION" ]; then
	echo "ERROR: could not read Version from apkg.rc" >&2
	exit 1
fi
echo "==> node_exporter version: $NE_VERSION"

# 1. Download + verify the official static linux-armv7 build.
TARBALL="node_exporter-${NE_VERSION}.linux-armv7.tar.gz"
BASE="https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}"
echo "==> Downloading ${BASE}/${TARBALL}"
wget -q "${BASE}/${TARBALL}" -O "/tmp/${TARBALL}"
wget -q "${BASE}/sha256sums.txt" -O "/tmp/sha256sums.txt"

EXPECTED="$(awk -v f="$TARBALL" '$2==f{print $1}' /tmp/sha256sums.txt)"
if [ -z "$EXPECTED" ]; then
	echo "ERROR: no checksum for ${TARBALL} in sha256sums.txt" >&2
	exit 1
fi
ACTUAL="$(sha256sum "/tmp/${TARBALL}" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
	echo "ERROR: SHA-256 mismatch" >&2
	echo "  expected: $EXPECTED" >&2
	echo "  actual:   $ACTUAL" >&2
	exit 1
fi
echo "==> Checksum OK: $ACTUAL"

# 2. Extract the single binary we ship (tarball is <name>/{node_exporter,LICENSE,NOTICE}).
rm -rf bin /tmp/ne-extract
mkdir -p bin /tmp/ne-extract
tar -xzf "/tmp/${TARBALL}" -C /tmp/ne-extract --strip-components=1
cp /tmp/ne-extract/node_exporter bin/
chmod +x bin/node_exporter
echo "==> Bundled: $(cd bin && echo *)"

# 3. Make sure the icon exists.
[ -f web/node_exporter.png ] || python3 web/make_icon.py web/node_exporter.png

# 4. Ensure all package scripts are executable (mksapkg preserves modes).
chmod +x ./*.sh libexec/*.sh cgi-bin/*.py 2>/dev/null || true

# Strip build cruft so it never lands in the package tar.
find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
rm -f apkg.xml apkg.sign

# 5. Pack with the real WD tool. -E = auto-enable after install, -s = self-sign.
for model in $MODELS; do
	echo "==> Packaging for ${model}"
	"$MKSAPKG" -E -s -m "$model"
done

# 6. Collect output. mksapkg writes "<MODEL>_<pkg>_<ver>.bin(MMDDYYYY)" into
#    the parent of this dir (the repo root); rename to drop the date suffix.
RELEASE_DIR="../packages"
mkdir -p "$RELEASE_DIR"
found=0
for f in ../*_"${APP_NAME}"_*.bin*; do
	[ -e "$f" ] || continue
	base="$(basename "$f")"
	clean="${base%.bin*}.bin"
	mv "$f" "${RELEASE_DIR}/${clean}"
	echo "==> ${RELEASE_DIR}/${clean}"
	found=1
done
if [ "$found" -ne 1 ]; then
	echo "ERROR: no .bin produced by mksapkg" >&2
	exit 1
fi

# 7. Hand artifacts back to the host user (container runs as root).
if [ -n "$HOST_UID" ]; then
	chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$RELEASE_DIR" bin 2>/dev/null || true
fi

echo "==> Build complete."
