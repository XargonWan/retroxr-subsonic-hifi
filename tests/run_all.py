#!/usr/bin/env python3
"""Every test of the mod, in order. Exit code 0 only if all pass.

    python3 tests/run_all.py            # Godot through flatpak-spawn --host (HOST=0 to run it directly)

Output goes to a file under ~/.cache (a pipe straight into grep hangs under flatpak-spawn; the host's /tmp is
not the sandbox's). Lines tagged [sb-...] are printed, and any SCRIPT ERROR / Parse Error fails the run.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64"))
PROJECT = os.environ.get("RETROXR_PROJECT", os.path.expanduser("~/gits/RetroXR-xargon/RetroXR"))
OUT = os.path.expanduser("~/.cache/sb-run")
MOD = "res://mods/xenu.subsonic/"

# (path under the mod, extra args). A .gd runs as --script, a .tscn as a scene.
SUITES = [
    ("tests/pure_tests.gd", []),
    ("tests/register_tests.tscn", []),
    ("tests/hifi_tests.tscn", []),
]


def run(path: str, extra: list) -> int:
    os.makedirs(OUT, exist_ok=True)
    log = os.path.join(OUT, os.path.basename(path) + ".log")
    host = os.environ.get("HOST", "1") == "1"
    target = ["--script", MOD + path] if path.endswith(".gd") else [MOD + path]
    cmd = (["flatpak-spawn", "--host"] if host else []) + [GODOT, "--headless", "--path", PROJECT] + target
    if extra:
        cmd += ["--"] + extra
    with open(log, "w") as f:
        rc = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=150).returncode
    text = open(log, errors="replace").read()
    for line in text.splitlines():
        if re.search(r"\[sb-[a-z]+\]", line):
            print(line)
    bad = [l for l in text.splitlines() if re.search(r"SCRIPT ERROR|Parse Error|SHADER ERROR|Failed to load script", l)]
    # This checkout holds some of the game's GLBs as Git LFS pointers (TV, AV switch, cassette deck): scenes of
    # the BASE game that name them fail to parse here and have nothing to do with the mod.
    lfs = [l for l in bad if "referenced non-existent resource at: res://imported-assets/" in l]
    bad = [l for l in bad if l not in lfs]
    if lfs:
        print("  (%d base-game errors from GLBs that are Git LFS pointers in this checkout, ignored)" % len(lfs))
    for l in bad[:10]:
        print("  !!", l)
    return rc or (1 if bad else 0)


def main() -> int:
    results = [(p, run(p, e)) for p, e in SUITES]
    print()
    for name, rc in results:
        print("%-32s %s" % (name, "ok" if rc == 0 else "FAILED (%d)" % rc))
    return 0 if all(rc == 0 for _, rc in results) else 1


sys.exit(main())
