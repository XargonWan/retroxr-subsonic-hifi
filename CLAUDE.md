# CLAUDE.md -- Subsonic Hi-Fi NAVI-AZ95 (RetroXR mod, id `xenu.subsonic`)

A hi-fi that plays a Subsonic-API server (Navidrome) and online radio (AzuraCast / Icecast).

**Not a Godot project on its own.** It is authored inside a RetroXR checkout through a symlink:
`RetroXR/mods/xenu.subsonic -> /home/xargon/gits/subsonic-hifi` (`RetroXR/mods/` is gitignored there).
**RetroXR itself is never modified by this mod.** Gaps in the mod API go into `docs/upstream-proposal.md`.

Plan: `~/.claude/plans/pasted-content-id-bd2d-subsonic-staged-flurry.md`.

## Rules

- Commits in English, RetroXR's conventional style (`feat(scope): ...`), NO Co-Authored-By trailer.
- Pack every round: `python3 tools/pack.py` -> `~/retroxr/mods/xenu.subsonic.zip`; name the zip to the user. Never mod.io.
- The test server password is never written to a file in this repo (use env vars / `.env.local`, gitignored).
  Store only salt + token; never log a URL with `t=`, `s=` or `p=` in it.
- The supplied NAVI model zips have no licence: proportion reference only, never packed.
- Godot does not run in the Claude sandbox: tests go through `flatpak-spawn --host` (host `/tmp` is not ours).
- Log with `[Subsonic]` tags on every decision and early return.
