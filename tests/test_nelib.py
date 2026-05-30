"""Unit tests for the pure CGI logic (nelib).

These run off-device: no NAS, no subprocess, no network. They exercise the
input validation, the node_exporter flag construction, and the config
serialize/parse round-trip.
"""

import nelib  # provided on sys.path via pyproject's [tool.pytest.ini_options].pythonpath
import pytest


# --------------------------------------------------------------------------- #
# validate_port
# --------------------------------------------------------------------------- #
def test_port_blank_is_default():
    assert nelib.validate_port("") == nelib.DEFAULT_PORT
    assert nelib.validate_port(None) == nelib.DEFAULT_PORT
    assert nelib.validate_port("   ") == nelib.DEFAULT_PORT


@pytest.mark.parametrize(
    "value,expected",
    [("9100", 9100), ("1", 1), ("65535", 65535), ("  8080  ", 8080)],
)
def test_port_valid(value, expected):
    assert nelib.validate_port(value) == expected


@pytest.mark.parametrize(
    "value",
    ["0", "65536", "-1", "abc", "99 99", "12;rm -rf /", "1.5", "0x1f90", "+80", "8_0"],
)
def test_port_invalid(value):
    with pytest.raises(nelib.ValidationError):
        nelib.validate_port(value)


# --------------------------------------------------------------------------- #
# build_args
# --------------------------------------------------------------------------- #
def test_args_minimal_defaults():
    args = nelib.build_args({})
    assert args == ["--web.listen-address=:9100"]


def test_args_listen_address_first_with_custom_port():
    args = nelib.build_args({"port": "8080"})
    assert args[0] == "--web.listen-address=:8080"


def test_args_all_collectors():
    args = nelib.build_args(
        {
            "port": "9100",
            "collector_processes": "on",
            "collector_systemd": "on",
            "collector_textfile": "on",
        },
        textfile_dir="/data/textfile",
    )
    assert "--collector.processes" in args
    assert "--collector.systemd" in args
    assert "--collector.textfile.directory=/data/textfile" in args


def test_args_unchecked_collectors_absent():
    args = nelib.build_args({"port": "9100"})
    assert not any(a.startswith("--collector.") for a in args)


def test_args_only_allowlisted_flags():
    # A smuggled-in field name must never become a flag.
    args = nelib.build_args({"collector_evil": "on", "extra_flag": "--config.file=/etc/passwd"})
    assert args == ["--web.listen-address=:9100"]


def test_args_invalid_port_raises():
    with pytest.raises(nelib.ValidationError):
        nelib.build_args({"port": "not-a-port"})


# --------------------------------------------------------------------------- #
# render_config / parse_config
# --------------------------------------------------------------------------- #
def test_render_config_has_port_and_args():
    text = nelib.render_config({"port": "9100", "collector_processes": "on"})
    config = nelib.parse_config(text)
    assert config["PORT"] == "9100"
    assert config["ARGS"] == "--web.listen-address=:9100 --collector.processes"


def test_render_config_default_port():
    config = nelib.parse_config(nelib.render_config({}))
    assert config["PORT"] == "9100"
    assert config["ARGS"] == "--web.listen-address=:9100"


def test_render_config_invalid_port_raises():
    with pytest.raises(nelib.ValidationError):
        nelib.render_config({"port": "99999"})


def test_parse_config_ignores_comments_and_blanks():
    config = nelib.parse_config("# a comment\n\nPORT=9100\n   \nARGS=--web.listen-address=:9100\n")
    assert config == {"PORT": "9100", "ARGS": "--web.listen-address=:9100"}


def test_parse_config_keeps_equals_in_value():
    # The ARGS line contains '=' inside flags; only the first '=' splits key/value.
    config = nelib.parse_config("ARGS=--web.listen-address=:9100 --collector.textfile.directory=/x")
    assert config["ARGS"] == "--web.listen-address=:9100 --collector.textfile.directory=/x"


def test_render_parse_args_match_build_args():
    # The persisted ARGS must be exactly what build_args produced (single source of truth).
    params = {"port": "8443", "collector_systemd": "on"}
    expected = " ".join(nelib.build_args(params))
    config = nelib.parse_config(nelib.render_config(params))
    assert config["ARGS"] == expected
