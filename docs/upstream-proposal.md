# What this mod hit in the RetroXR mod API (for the RetroXR developer)

Written while building the Subsonic Hi-Fi (`xenu.subsonic`) on RetroXR master `00256b3f`. The mod changes nothing in
RetroXR; everything below is a place where it carries its own copy of something that could live once in the game.
Each item says what the mod does today, where, and the smallest change that would let it stop.

## 1. Rows in an object's menu (the new `menu_rows()` stops at machines)

`RetroSystemModel.menu_rows()` / `set_menu_row()` (`00256b3f`) is exactly the shape this mod needs, but it exists
only for consoles and handhelds. A deck (`RetroAudioPlayer`) gets `AudioOptions2D`: a float toggle and a Debug tab.
So the mod has its own panel, `scripts/hifi_options_panel.gd` + `hifi_options_2d.gd` (about 300 lines, a clone of the
Jellyfin mod's), for four tabs: Server, Radio, Cache, Unit.

- Smallest change: give `RetroAudioPlayer` the same two overrides, rendered by `AudioOptions2D` with the code
  `core_options_2d.gd` already has (lift `_build_model_rows` into a shared widget so the two menus do not fork).
- Row kinds the mod needs beyond the current table: **`"text"` as an input** (server address, user, a station's name
  and URL; today `"text"` is read-only), a **`"list"`** with add / remove / play per item (radio stations), a
  **`"stepper"`** for discrete values (cache 10 MB .. 2 GB), and a **secret** text field (`LineEdit.secret`).
- Without these the mod could not drop its panel, so they are the part worth designing with the mod open.

## 2. A deck with no medium

`RetroAudioPlayer._ready()` resolves `$MediaSlot`, `$NameLabel`, `$PlayButton`, `$PauseButton`, `$StopButton` with
`@onready` (hard `$`), then calls `_setup_loader()`. A deck whose "album" is a queue (a streaming client, a jukebox)
has no slot. The mod works around it in `scripts/subsonic_hifi.gd`: it inherits `cd_player.tscn`, disables the snap
zone, and frees the tray-era buttons in `_enter_tree()` (before the `@onready` lookups run).

- Smallest change: `get_node_or_null` for `MediaSlot` and `NameLabel`, and a documented "queue deck" mode.
- Related: `_tracks` is a list of file paths, so a remote track has to be downloaded first. A station's URL plays
  only because `ProjectSettings.globalize_path()` happens to leave a `scheme://` string alone (`audio_player.gd`
  `play()`): that is accidental. A `_track_source(idx)` hook (or saying in the doc that a URL is allowed) would make it
  a contract, and would let a mod stream a library track without caching it first when it chooses to.
- The base `play()` is the one gate every path goes through (PLAY, NEXT, advance), which is what made the cache-first
  approach cheap: the mod overrides `play()` to fetch and re-enters. That is worth keeping as documented behaviour.
- Netplay: `_net_push_state` assumes a seated disc or tape. The mod does not wire it (a peer has an empty queue and the
  base ignores the host's track change); a "this deck is not replicated" flag would say so honestly.

Measured while building the streaming start: `VlcPlayer.Open` passes a `scheme://` address straight through (its code says
so), and it has an `error` signal the base deck never listens to, so a deck whose stream cannot be opened never says so. The
mod connects it itself (`_on_vlc_error`). Worth connecting in the base deck as well.

## 3. Per-mod settings and a place for secrets

`api.store()` gives a folder. The Jellyfin mod (`jf_config.gd`) and this one (`sb_config.gd`) are the same file: a JSON
under `user://mods/<id>/` through `JsonStore`, an environment override for tests, keys cleaned on load. A typed
`api.settings()` (with defaults) and a documented rule for credentials (kept apart from the room save, never the password)
would remove two copies. This mod keeps only a salt + token (Subsonic's `t = md5(password + salt)`), never the password.

## 4. HTTP with a size-capped file cache

`sb_client.gd` (REST with per-call `HTTPRequest`, reachability logged on change, 200-with-a-JSON-error treated as a
failure, secrets redacted from logs) and `sb_cache.gd` (a folder under a byte cap, least recently used out, protected
names, partial downloads dropped at open, recency in `index.json`) are written to be mod-independent. The Jellyfin mod has
its own REST client. A shared `ModHttp` / `ModFileCache` would serve both and anything after them.

## 5. A pointable screen on an object

`scripts/hifi_screen.gd` is a 640 x 320 `Control` shown through an `XRToolsViewport2DIn3D` on the unit's face
(`subsonic_hifi.gd` `_build_screen`). It works (laser and click press its Buttons). Two rough edges:
the viewport's page appears a frame after the node does, with no signal, so the mod polls for it
(`_bind_screen`, up to 6 s); and `UPDATE_THROTTLED` is the right mode for an always-visible screen but is easy to miss.
A small "screen on an object" helper (instantiate, size, throttle, `ready` signal, optional fingertip press) would
serve any mod device. `VfdDisplay` is draw-only, so it was not an option.

## 6. Smaller things met on the way

- A mod's tests need the game's class cache fresh: `--editor --quit` regenerates it and **dirties tracked `.import`
  files** (the TV, AV switch and cassette GLBs are Git LFS pointers in a plain checkout). Every suite prints
  base-game "referenced non-existent resource" errors for them, which the mod's runner has to filter.
- `static var` caches of materials in a mod script live until the process ends; fine, but `ModApi.withdraw` has no hook
  for a mod to drop such state when it is unloaded in place.
- No optical (Toslink) or S-Link connector id exists, so the CDP-CX300's digital and control jacks that inspired the
  unit are not modelled. Not needed now.
- Naming: a mod script constant called `Panel` shadows a native class and the whole script fails to parse with a message
  that does not say which constant. Worth a line in `docs/modding.md`.

## What I would send first

(1) and (2), together, as one change on its own branch: `menu_rows` on `RetroAudioPlayer` with the `text` / `list` /
`stepper` kinds, and the `MediaSlot` / `NameLabel` tolerance. It is the smallest piece that lets this mod and the
Jellyfin one delete their panels, and it makes a record, cassette or CD deck configurable the same way a console is.
Nothing is sent until the developer says they want it.
