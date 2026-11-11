# CLAUDE.md -- Subsonic Hi-Fi NAVI-AZ95 (RetroXR mod, id `xenu.subsonic`)

A hi-fi that plays a Subsonic-API server (Navidrome) and online radio (AzuraCast / Icecast).

**Not a Godot project on its own.** It is authored inside a RetroXR checkout through a symlink:
`RetroXR/mods/xenu.subsonic -> /home/xargon/gits/subsonic-hifi` (`RetroXR/mods/` is gitignored there).
**RetroXR itself is never modified by this mod.** Gaps in the mod API go into `docs/upstream-proposal.md`.

Plan: `~/.claude/plans/pasted-content-id-bd2d-subsonic-staged-flurry.md`.

## Rules

- Commits in English, RetroXR's conventional style (`feat(scope): ...`), NO Co-Authored-By trailer.
- Pack every round: `python3 tools/pack.py` -> `~/retroxr/mods/xenu.subsonic.zip`; name the zip to the user.
- Releases and mod.io: a push to `main` runs `.github/workflows/release.yml`, which computes the version from the
  commits (`feat` minor, `fix`/`perf` patch, breaking the major), creates the GitHub release and adds the same zip to
  mod.io via `tools/publish_modio.py`. Never upload to mod.io by hand, and never change the mod's visibility there.
  Repo: `XargonWan/retroxr-subsonic-hifi`; mod.io slug from the repo variable `MODIO_MOD_SLUG`.
- Pushes to `main` only when the user asks for them. A commit that must not release anything gets `[skip ci]`
  (or `chore`/`docs`/`ci`).
- The test server password is never written to a file in this repo (use env vars / `.env.local`, gitignored).
  Store only salt + token; never log a URL with `t=`, `s=` or `p=` in it.
- The supplied NAVI model zips have no licence: proportion reference only, never packed.
- Godot does not run in the Claude sandbox: tests go through `flatpak-spawn --host` (host `/tmp` is not ours).
- Log with `[Subsonic]` tags on every decision and early return.

## Layout

- `scripts/sb_api.gd`, `radio.gd`, `sb_config.gd`, `sb_cache.gd`, `sb_pages.gd` -- pure logic (tests/pure_tests.gd).
- `scripts/sb_client.gd` -- REST + downloads. `scripts/hifi_browser.gd` -- what a press on the screen / the unit's keys does.
- `scripts/subsonic_hifi.gd` -- the object (a `RetroAudioPlayer` with a queue instead of a disc), `hifi_model.gd` its body,
  `hifi_screen.gd` the LCD, `hifi_options_panel.gd` + `hifi_options_2d.gd` the TAB menu.
- Tests: `python3 tests/run_all.py [filter]` (pure, browser, register, hifi); `tests/run_live.py` against the real servers
  (login from `.env.local` / environment; `SB_LIVE_PLAY=1` also plays through the deck); `body_render_probe` and
  `menu_render_probe` are windowed (images to `$OUT`).
- `docs/upstream-proposal.md` -- what the mod API lacked; nothing is sent upstream without the user's go-ahead.

## Rules that bit

- A script constant named `Panel` (or any native class) fails the whole script to parse. `Node` already has `_get`.
- `_enter_tree` runs before the base deck's `@onready` lookups: remove base-scene nodes there, not in `_setup_loader`.
- A first-time server transcode of a long track can take longer than a test's patience: raw is the default quality.
- Never `pkill -f` / `pgrep -f` a pattern that is in your own command line.
