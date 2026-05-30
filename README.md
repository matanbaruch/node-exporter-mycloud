# Prometheus node_exporter for WD My Cloud EX2 Ultra

[![CI](https://github.com/matanbaruch/node-exporter-mycloud/actions/workflows/ci.yml/badge.svg)](https://github.com/matanbaruch/node-exporter-mycloud/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/matanbaruch/node-exporter-mycloud?sort=semver)](https://github.com/matanbaruch/node-exporter-mycloud/releases/latest)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](LICENSE)

A **[Prometheus node_exporter](https://prometheus.io/docs/guides/node-exporter/)** app for the
**Western Digital My Cloud EX2 Ultra** (firmware OS 5). Install it the normal WD way — upload a `.bin`
from the dashboard's **Apps → Install Manually** page — then set the listen port and collectors from a
built-in web page. The exporter publishes the NAS's hardware and OS metrics over HTTP so a Prometheus
server can scrape them.

> **Status:** confirmed working on a physical My Cloud EX2 Ultra (firmware 5.33.102, kernel
> `4.14.22-armada`, ARMv7) — installed from the dashboard and serving metrics on `:9100` for Prometheus
> to scrape. Every change is also round-trip-verified in CI (APKG header, armv7 `node_exporter`, expected
> files). Built off the same packaging approach as
> [tailscale-mycloud](https://github.com/matanbaruch/tailscale-mycloud).

---

## What you get

A web page inside the My Cloud dashboard (**Apps → Node Exporter**) with:

- **Listen port** — which port node_exporter serves `/metrics` on (default `9100`).
- Capability toggles:
  - **Processes collector** (`--collector.processes`)
  - **systemd collector** (`--collector.systemd`)
  - **Textfile collector** (`--collector.textfile.directory=…`) for custom `*.prom` metrics
- **Save & restart** — persists the config and restarts the exporter so new flags take effect.
- **Start / Stop / Restart** controls.
- **Live status** — running state, `node_exporter --version`, the configured port, and a sample of the
  metrics currently being served.

The configuration is stored on the **persistent data volume**, so it survives reboots and the exporter
comes back up on its own with your settings.

## Install (on the NAS)

1. Download the latest `MyCloudEX2Ultra_node_exporter_*.bin` from the
   [**Releases**](https://github.com/matanbaruch/node-exporter-mycloud/releases/latest) page.
2. In the My Cloud dashboard go to **Apps**, click **Install an app manually** (per
   [WD's OS5 manual-install guide](https://support-en.wd.com/app/answers/detailweb/a_id/29960)),
   and choose the `.bin`.
3. Open **Apps → Node Exporter**, set the listen port (default `9100`), pick any collectors,
   and click **Save & restart**.
4. Point a Prometheus scrape job at `http://<nas-ip>:<port>/metrics`:
   ```yaml
   scrape_configs:
     - job_name: mycloud-ex2
       static_configs:
         - targets: ["<nas-ip>:9100"]
   ```

### Upgrading / reinstalling

The configuration lives in the state dir on the persistent volume. A **reboot keeps it** —
node_exporter restarts on its own with the same flags. An **uninstall does not**: `remove.sh`
stops the daemon and deletes the config/state dir. When you install a newer `.bin`:

- **If the dashboard upgrades in place**, your config is kept.
- **If it makes you uninstall first**, you'll start from defaults (`:9100`, no extra collectors) and
  can re-enter your settings on the config page. To preserve them, SSH in and back up the config
  **before** reinstalling:
  ```sh
  cp -a /mnt/HD/HD_a2/.systemfile/node_exporter/config /mnt/HD/HD_a2/node_exporter.config.bak
  ```

## Build from source

Requires **Docker** (the WD packaging tool `mksapkg-OS5` is Linux x86-64 and runs inside the build image).

```sh
./build.sh
# → packages/MyCloudEX2Ultra_node_exporter_<version>.bin
```

The bundled node_exporter version is the single source of truth in [`node_exporter/apkg.rc`](node_exporter/apkg.rc)
(`Version:`). `build.sh` downloads the official static `linux-armv7` build for that version from the
[prometheus/node_exporter GitHub Releases](https://github.com/prometheus/node_exporter/releases),
**verifies its SHA-256** against the release's `sha256sums.txt`, packs it, and emits the `.bin`.

### Run the tests

```sh
pip install pytest && pytest        # unit tests for the CGI logic (port validation + arg/config building)
sh tests/test_package.sh packages/MyCloudEX2Ultra_node_exporter_<version>.bin   # post-build round-trip
```

## How it works

WD My Cloud apps are `.bin` files: a **~200-byte APKG header** (product/model IDs + self-signature)
followed by a **gzipped tar**. The header is produced by WD's `mksapkg` tool — we use the real one
([`mksapkg-OS5`](mksapkg-OS5), vendored from [WDCommunity/wdpksrc](https://github.com/WDCommunity/wdpksrc),
BSD-3) inside Docker rather than reimplementing the header (a single wrong ID = "incompatible device").

| Path on device | Purpose |
| --- | --- |
| `/mnt/HD/HD_a2/Nas_Prog/node_exporter/` | installed app (binary + scripts) — persistent |
| `/mnt/HD/HD_a2/.systemfile/node_exporter/config` | rendered flag line read by `daemon.sh` — persistent |
| `/mnt/HD/HD_a2/.systemfile/node_exporter/textfile/` | textfile collector input dir |
| `/mnt/HD/HD_a2/.systemfile/node_exporter/node_exporter.log` | daemon log |
| `/var/www/apps/node_exporter/`, `/var/www/cgi-bin/node_exporter.py` | the dashboard UI (symlinked by `init.sh`) |

node_exporter is stateless — every setting is a command-line flag — so the config page renders the
exact flag line into the config file (the single source of truth, built and unit-tested in
[`nelib.py`](node_exporter/cgi-bin/nelib.py)) and `daemon.sh` runs it verbatim. The package lifecycle
scripts (`install/init/start/stop/clean/remove`) follow the WD app convention, and the exporter
**auto-starts on boot** with your saved config.

## Troubleshooting

- **Enable SSH** on the NAS (Settings → Network → SSH), then SSH in as `root`/`sshd`.
- Turn on script tracing: `touch /tmp/debug_apkg` (the lifecycle scripts log to it).
- Daemon log: `cat /mnt/HD/HD_a2/.systemfile/node_exporter/node_exporter.log`
- Check it locally: `wget -qO- http://127.0.0.1:9100/metrics | head`
- A collector that can't run on this kernel/OS (e.g. `systemd` if the OS isn't systemd-based) **degrades
  gracefully** — it reports `node_scrape_collector_success{collector="…"} 0` instead of crashing the exporter.

## Caveats & security

- **The metrics endpoint is unauthenticated and binds all interfaces** (`--web.listen-address=:<port>`).
  Anyone who can reach the port can read system metrics (hostnames, filesystems, network counters, etc.).
  Restrict access at the network layer: keep the NAS off the public internet, firewall the port to your
  Prometheus host, or expose it only over a private overlay (e.g. pair it with
  [tailscale-mycloud](https://github.com/matanbaruch/tailscale-mycloud) and scrape over the tailnet).
- The exporter ships **no authentication or TLS** in this build; node_exporter's `--web.config.file`
  (basic auth / TLS) is not yet wired into the config page.
- **Uninstalling deletes the saved config** (a fresh install starts from defaults).
- Only the **EX2 Ultra** artifact (linux-armv7) is shipped; other models use different mount paths/arches.

## License

[BSD-3-Clause](LICENSE). Third-party attributions in [NOTICE](NOTICE) — node_exporter itself is
Apache-2.0 and is downloaded at build time, not vendored. Not affiliated with the Prometheus project
or Western Digital.
