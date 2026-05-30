"""Pure, importable helpers for the node_exporter My Cloud CGI.

This module contains no CGI plumbing and no subprocess side effects, so it can
be unit-tested off-device. ``node_exporter.py`` imports from it. It uses only the
standard library so it runs identically on the NAS's Python 3 and on a
developer/CI machine.

node_exporter is stateless -- every setting is a command-line flag. So this
module is the single source of truth for turning the dashboard form into the
exact flag line the daemon runs. ``render_config`` serializes that line into the
persistent config file; ``daemon.sh`` reads it straight back (it does no flag
building of its own), which keeps the boot path and the UI path identical.
"""

DEFAULT_PORT = 9100

# Fixed on-device location the textfile collector reads custom *.prom metrics from.
TEXTFILE_DIR = "/mnt/HD/HD_a2/.systemfile/node_exporter/textfile"

TRUTHY = ("1", "true", "on", "yes")

# UI toggle -> the node_exporter flag it adds. An allowlist: only these fixed,
# argument-free flags can ever reach the command line, so a form value can never
# inject an arbitrary flag. The textfile collector is handled separately because
# it needs a (fixed, non-user) directory argument.
COLLECTOR_FLAGS = {
    "collector_processes": "--collector.processes",
    "collector_systemd": "--collector.systemd",
}


class ValidationError(ValueError):
    """Raised when user-supplied input fails validation."""


def _truthy(value):
    """Interpret form-style values (checkbox 'on', '1', bool) as a boolean."""
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in TRUTHY


def validate_port(value):
    """Return the listen port as an int in 1..65535, else raise.

    Accepts the default when the field is blank. Rejects anything that is not a
    plain decimal integer (no spaces, signs, separators) so the value is always
    safe to drop into ``--web.listen-address=:<port>``.
    """
    raw = str(value if value is not None else "").strip()
    if raw == "":
        return DEFAULT_PORT
    if not raw.isdigit():
        raise ValidationError("Port must be a whole number between 1 and 65535.")
    port = int(raw)
    if not (1 <= port <= 65535):
        raise ValidationError("Port must be between 1 and 65535.")
    return port


def build_args(params, textfile_dir=TEXTFILE_DIR):
    """Build the node_exporter flag list from validated UI params.

    Recognized ``params`` keys:
      - ``port`` (optional; defaults to 9100)
      - ``collector_processes``, ``collector_systemd`` (bools)
      - ``collector_textfile`` (bool; enables the textfile collector at
        ``textfile_dir``)

    Returns a list of flags (no binary path). The first flag is always the
    listen address so the rest of the app can rely on its position. Only fixed,
    allowlisted flags are emitted -- never a value taken verbatim from the form.
    """
    port = validate_port(params.get("port"))
    args = [f"--web.listen-address=:{port}"]

    for key, flag in COLLECTOR_FLAGS.items():
        if _truthy(params.get(key)):
            args.append(flag)

    if _truthy(params.get("collector_textfile")):
        args.append(f"--collector.textfile.directory={textfile_dir}")

    return args


def render_config(params, textfile_dir=TEXTFILE_DIR):
    """Serialize validated params to the on-device config file contents.

    Stores both the human-readable port and the fully rendered ``ARGS`` line that
    ``daemon.sh`` runs verbatim. Raises ValidationError on bad input so a bad
    Save never overwrites a good config.
    """
    port = validate_port(params.get("port"))
    args = build_args(params, textfile_dir=textfile_dir)
    lines = [
        "# node_exporter config (managed by the My Cloud dashboard app)",
        f"PORT={port}",
        "ARGS=" + " ".join(args),
        "",
    ]
    return "\n".join(lines)


def parse_config(text):
    """Parse the on-device config file into a dict of KEY -> value (strings).

    Ignores blank lines and ``#`` comments. The value keeps everything after the
    first ``=`` (so the space-separated ARGS line survives intact).
    """
    config = {}
    for line in (text or "").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        config[key.strip()] = value
    return config
