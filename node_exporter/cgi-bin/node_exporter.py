#!/usr/bin/env python3
"""Dashboard CGI for the Prometheus node_exporter My Cloud app.

GET  -> live status (text/plain): running?, version, listen port, a sample of
        the metrics the exporter is currently serving.
POST -> an ``action``: save / start / stop / restart.

All commands run via argument lists (no shell), so form input cannot inject
extra commands; the configurable flags come from a fixed allowlist in ``nelib``.
We deliberately do NOT use ``cgitb`` -- the dispatcher catches everything and
prints a short message so a stray traceback never lands in the HTTP response.
"""

import cgi
import os
import subprocess
import sys
from urllib.error import URLError
from urllib.request import urlopen

# Resolve symlinks: this file is symlinked into /var/www/cgi-bin/, but nelib.py
# lives next to the real file in the install dir. realpath finds it there.
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import nelib  # noqa: E402

INSTALL_DIR = "/mnt/HD/HD_a2/Nas_Prog/node_exporter"
STATE_DIR = "/mnt/HD/HD_a2/.systemfile/node_exporter"
CONFIG = STATE_DIR + "/config"
BIN_DIR = INSTALL_DIR + "/bin"
NODE_EXPORTER = BIN_DIR + "/node_exporter"
DAEMON = INSTALL_DIR + "/libexec/daemon.sh"
STOP = INSTALL_DIR + "/stop.sh"

os.environ["PATH"] = BIN_DIR + os.pathsep + os.environ.get("PATH", "")

SAVE_FIELDS = (
    "port",
    "collector_processes",
    "collector_systemd",
    "collector_textfile",
)

# Metric families worth surfacing on the status page (a readable "it works" view,
# not the full /metrics dump). One sample line each.
HIGHLIGHT_METRICS = (
    "node_exporter_build_info",
    "node_boot_time_seconds",
    "node_time_seconds",
    "node_load1",
    "node_memory_MemAvailable_bytes",
    "node_filesystem_avail_bytes",
)


def emit_headers():
    print("Content-type: text/plain; charset=utf-8")
    print("")


def out(text=""):
    print(text)


def run(cmd, timeout=120):
    """Run a command; return (returncode, combined stdout+stderr)."""
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return 124, "command timed out\n"
    except OSError as exc:
        return 127, f"could not run {cmd[0]}: {exc.strerror or exc.errno}\n"


def read_text(path):
    try:
        with open(path) as fh:
            return fh.read()
    except OSError:
        return ""


def configured_port():
    config = nelib.parse_config(read_text(CONFIG))
    try:
        return nelib.validate_port(config.get("PORT"))
    except nelib.ValidationError:
        return nelib.DEFAULT_PORT


def daemon_running():
    rc, _ = run(
        ["sh", "-c", "ps 2>/dev/null | grep -v grep | grep -q 'node_exporter/bin/node_exporter'"],
        timeout=10,
    )
    return rc == 0


def ensure_daemon():
    return run([DAEMON, INSTALL_DIR], timeout=30)


def restart_daemon():
    # node_exporter is stateless, so new flags only take effect on a fresh
    # process: stop (waits for exit) then start.
    run([STOP], timeout=30)
    return ensure_daemon()


def fetch_metrics(port, timeout=8):
    """Fetch /metrics from the local exporter. Returns (ok, text_or_error)."""
    url = f"http://127.0.0.1:{port}/metrics"
    try:
        with urlopen(url, timeout=timeout) as resp:  # noqa: S310 (fixed localhost URL)
            return True, resp.read().decode("utf-8", "replace")
    except URLError as exc:
        return False, str(getattr(exc, "reason", exc))
    except OSError as exc:
        return False, exc.strerror or str(exc)


def show_status():
    port = configured_port()
    out("=== Prometheus node_exporter on WD My Cloud EX2 Ultra ===")
    out(f"daemon_running: {'yes' if daemon_running() else 'no'}")
    out(f"listen_port: {port}  (scrape http://<nas-ip>:{port}/metrics)")

    _, ver = run([NODE_EXPORTER, "--version"], timeout=15)
    out("\n--- version ---")
    out(ver.strip() or "(node_exporter --version produced no output)")

    ok, body = fetch_metrics(port)
    out("\n--- metrics endpoint ---")
    if not ok:
        out(f"(could not reach http://127.0.0.1:{port}/metrics: {body})")
        return

    samples = [ln for ln in body.splitlines() if ln and not ln.startswith("#")]
    out(f"serving {len(samples)} metric samples")

    out("\n--- sample ---")
    shown = 0
    for name in HIGHLIGHT_METRICS:
        for ln in samples:
            head = ln.split("{", 1)[0].split(" ", 1)[0]
            if head == name:
                out(ln)
                shown += 1
                break
    if shown == 0:
        out("(no highlight metrics matched; the endpoint is up — see full /metrics)")


def handle_save(form):
    params = {k: form.getfirst(k, "") for k in SAVE_FIELDS}
    try:
        contents = nelib.render_config(params)
    except nelib.ValidationError as exc:
        out(f"ERROR: {exc}")
        return

    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        with open(CONFIG, "w") as fh:
            fh.write(contents)
    except OSError as exc:
        out(f"ERROR: could not write config: {exc.strerror or exc}")
        return
    out("Saved configuration:")
    out(contents.strip())

    out("\nRestarting node_exporter…")
    _, output = restart_daemon()
    out(output.strip() or "(restarted)")


def dispatch():
    method = os.environ.get("REQUEST_METHOD", "GET").upper()
    form = cgi.FieldStorage()

    if method != "POST":
        show_status()
        return

    action = form.getfirst("action", "")
    if action == "save":
        handle_save(form)
    elif action == "start":
        _, o = ensure_daemon()
        out(o.strip() or "Start requested.")
    elif action == "stop":
        run([STOP], timeout=30)
        out("node_exporter stopped." if not daemon_running() else "Stop requested.")
    elif action == "restart":
        _, o = restart_daemon()
        out(o.strip() or "Service restart requested.")
    else:
        out(f"unknown action: {action!r}")


def main():
    # Headers first so a later error still produces a valid CGI response.
    emit_headers()
    try:
        dispatch()
    except Exception as exc:  # noqa: BLE001 -- never dump a traceback into the response
        out(f"error: {type(exc).__name__}: {exc}")


if __name__ == "__main__":
    main()
