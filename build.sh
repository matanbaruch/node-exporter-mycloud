#!/usr/bin/env bash
# Host entry point: build the WD My Cloud node_exporter .bin via Docker.
#
#   ./build.sh                # build for MyCloudEX2Ultra
#   MODELS="MyCloudEX2Ultra" ./build.sh
#
# Output: packages/MyCloudEX2Ultra_node_exporter_<version>.bin
set -euo pipefail

cd "$(dirname "$0")"
IMAGE="node-exporter-mycloud-build"
# mksapkg-OS5 is x86-64; force amd64 (emulated on Apple Silicon, native on CI).
PLATFORM="linux/amd64"

if ! command -v docker >/dev/null 2>&1; then
	echo "ERROR: docker is required (mksapkg-OS5 is a Linux binary)." >&2
	exit 1
fi

echo "==> Building Docker image: ${IMAGE}"
docker build --platform="${PLATFORM}" -t "${IMAGE}" .

echo "==> Running package build"
docker run --rm --platform="${PLATFORM}" \
	-v "${PWD}:/src" -w /src \
	-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
	${MODELS:+-e MODELS="${MODELS}"} \
	"${IMAGE}" node_exporter/package-build.sh

echo
echo "==> Artifacts:"
ls -la packages/ 2>/dev/null || echo "(none)"
