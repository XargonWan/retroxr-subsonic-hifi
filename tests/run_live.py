#!/usr/bin/env python3
"""Run tests/live_probe.tscn against real servers. The login is read from the environment or from
.env.local (gitignored) in the repo root, lines of KEY=VALUE:

    SB_LIVE_URL=https://audio.example.org
    SB_LIVE_USER=...
    SB_LIVE_PASS=...
    SB_LIVE_RADIO=https://radio.example.org/public/station

The password is only handed to Godot through its environment; it is never printed and never written to a log
(the log is scanned for it and the run fails if it is there).
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64"))
PROJECT = os.environ.get("RETROXR_PROJECT", os.path.expanduser("~/gits/RetroXR-xargon/RetroXR"))
OUT = os.path.expanduser("~/.cache/sb-run")


def main() -> int:
    env = dict(os.environ)
    envfile = os.path.join(ROOT, ".env.local")
    if os.path.exists(envfile):
        for line in open(envfile):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip())
    if not env.get("SB_LIVE_URL") and not env.get("SB_LIVE_RADIO"):
        sys.exit("set SB_LIVE_URL/USER/PASS and/or SB_LIVE_RADIO (environment or .env.local)")
    os.makedirs(OUT, exist_ok=True)
    log = os.path.join(OUT, "live_probe.log")
    host = os.environ.get("HOST", "1") == "1"
    pass_through = ["SB_LIVE_URL", "SB_LIVE_USER", "SB_LIVE_PASS", "SB_LIVE_RADIO", "SB_LIVE_PLAY"]
    cmd = []
    if host:
        # flatpak-spawn only forwards what --env= names.
        cmd = ["flatpak-spawn", "--host"] + ["--env=%s=%s" % (k, env[k]) for k in pass_through if env.get(k)]
    cmd += [GODOT, "--headless", "--path", PROJECT, "res://mods/xenu.subsonic/tests/live_probe.tscn"]
    with open(log, "w") as f:
        rc = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=env, timeout=300).returncode
    text = open(log, errors="replace").read()
    secret = env.get("SB_LIVE_PASS", "")
    leaked = bool(secret) and secret in text
    for line in text.splitlines():
        if "[sb-live]" in line or "[Subsonic]" in line:
            print(line.replace(secret, "***") if secret else line)
    if leaked:
        print("FAIL: the password is in the log")
        os.remove(log)
        return 1
    return rc


sys.exit(main())
