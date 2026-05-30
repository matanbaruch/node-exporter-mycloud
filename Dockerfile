# Build image for the WD My Cloud node_exporter package.
#
# mksapkg-OS5 is a prebuilt Linux x86-64 binary from WDCommunity/wdpksrc, built
# in the Debian buster era (links libxml2.so.2 + libssl/libcrypto 1.1). We pin
# buster so those sonames match exactly. Buster is archived, so we point apt at
# archive.debian.org and skip the expired-Release check.
#
# Pin linux/amd64: mksapkg-OS5 is an x86-64 binary. On an Apple Silicon host
# Docker Desktop emulates amd64 (qemu/Rosetta); on amd64 CI runners this is
# native. Without the pin, an arm64 host builds an arm64 rootfs that lacks the
# x86-64 loader and mksapkg can't run.
FROM --platform=linux/amd64 debian:buster

ENV LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g; /buster-updates/d' /etc/apt/sources.list; \
    apt-get -o Acquire::Check-Valid-Until=false update; \
    apt-get install -y --no-install-recommends \
        ca-certificates wget tar gzip openssl libxml2 python3 file; \
    rm -rf /var/lib/apt/lists/*

COPY mksapkg-OS5 /usr/bin/mksapkg-OS5
RUN chmod +x /usr/bin/mksapkg-OS5

WORKDIR /src
