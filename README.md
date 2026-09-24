# MaterDE

**Material Desktop Environment** — a Material You desktop environment for Wayland,
targeting a ChromeOS-like experience: bottom shelf, search-driven launcher,
workspace overview, notification toasts; colors dynamically derived from a
wallpaper seed using the HCT color space.

> **Current status: Phase 0 complete ✅** (2026-09-24) — wlr-layer-shell works end to end,
> the embedder was modified and verified on a real compositor, and the Material You
> theme engine passed visual acceptance.
> Design docs live in local `docs/` (not tracked in this repo); see
> `docs/07-implementation-roadmap.md` for the phase plan and
> `docs/08-risk-analysis.md` for risks and Go/No-Go decisions.

## Architecture & code ownership

| Directory | Contents | Ownership / license |
|---|---|---|
| `shell/` | Flutter/Dart shell: Material You theme engine, shelf / launcher / overview… | **Written by us**, BSD-3 |
| `embedder/` | Fork of [sony/flutter-embedded-linux](https://github.com/sony/flutter-embedded-linux) with wlr-layer-shell support added; produces `flutter-client` | Upstream borrow (BSD-3) + **our changes**; diff in `embedder/patches/`, notes in `embedder/LAYER-SHELL-NOTES.md` |
| `protocol/` | Wayland protocol XMLs (layer-shell, xdg-shell; cosmic ones to come) | Upstream spec files, copyright held by the file authors |
| `docs/` | Design documents (kept locally, not tracked) | Written by us |

Runtime composition: **cosmic-comp** (Rust compositor, borrowed as a separate
process — never linked, see `THIRD_PARTY_NOTICES.md` §8) + `flutter-client`
(from `embedder/`) rendering the shell bundle.

Build artifacts (`shell/build/`, `embedder/build/`, `shell/.dart_tool/`, …) are
never committed.

## Requirements

- Linux with a **Wayland session** (dev machine runs KWin; the target session is COSMIC)
- CMake ≥ 3.15, Ninja, a C/C++ compiler; `wayland` dev packages (needs `wayland-scanner`)
- The [`sony/flutter-elinux`](https://github.com/sony/flutter-elinux) CLI
  (bootstraps Flutter **3.29.3** / Dart **3.7.2** / engine `cf56914b32` on first run):

```bash
git clone https://github.com/sony/flutter-elinux.git ~/flutter-elinux
~/flutter-elinux/bin/flutter-elinux --version   # first run bootstraps the toolchain
```

> If engine artifact downloads are blocked, point it at a local zip directory:
> `ELINUX_ENGINE_BASE_LOCAL_DIRECTORY=/path/to/zips ~/flutter-elinux/bin/flutter-elinux build elinux --release`

## Development workflow

### 1. Build the shell bundle (AOT)

```bash
cd shell
~/flutter-elinux/bin/flutter-elinux pub get
~/flutter-elinux/bin/flutter-elinux build elinux --release
# → shell/build/elinux/x64/release/bundle/
#   (materde_shell runner + lib/libapp.so AOT 3.2MB + data/flutter_assets)
```

⚠️ **Flutter commands must run serially**: concurrent runs fight over the startup
lock and corrupt the CMake cache; fix by deleting `shell/build/elinux/x64/*/CMakeFiles`
and re-running.

### 2. Build the embedder (flutter-client)

```bash
cd embedder
cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug \
  -DUSER_PROJECT_PATH=examples/flutter-wayland-client -B build
ninja -C build
```

### 3. Run it as the bottom shelf (layer surface)

```bash
cd embedder
MATERDE_UI=shelf LD_LIBRARY_PATH=build FLUTTER_LOG_LEVELS=INFO \
  ./build/flutter-client \
  -b "$PWD/../shell/build/elinux/x64/release/bundle" \
  --layer-shell -w 0 -h 248 -L 2 -A 14 -e 48 -N materde-shelf -y 0
```

`-b` must be absolute: the client resolves relative paths against its own
executable directory (`embedder/build/`), not your shell's cwd.

`MATERDE_UI=shelf` selects the shelf UI (`MaterdeShelf`); without it the
Phase 0 acceptance page renders (that path still works with `-h 48`).

The surface is `-h 248` = 48px visible bar + a 200px transparent zone above
it where tooltips/context menus render. Only the bottom 48px accepts input
while no menu is open (dynamic input region, `lib/wayland/layer_shell.dart`).

Expected log: `Created the layer surface: layer=2, anchor=14, exclusive_zone=48,
keyboard_interactivity=0` → `configure: 1646x248` (width follows the output's
logical width). Layer `2` (top) is deliberate: panels live on the top layer;
`bottom` gets covered by the COSMIC dock / KDE plasmashell (see docs/04).

Layer-shell flags (added in Phase 0; see `flutter-client --help`):

| Flag | Meaning | Value used here |
|---|---|---|
| `--layer-shell` | Create a layer surface instead of an xdg-shell window | on |
| `-L, --layer` | 0=background 1=bottom 2=top 3=overlay | 2 (top shelf — panels must be top, see docs/04) |
| `-A, --anchor` | Bitmask: top=1 bottom=2 left=4 right=8 | 14 (bottom\|left\|right) |
| `-e, --exclusive-zone` | Reserved zone (logical px) that pushes normal windows away | 48 |
| `-N, --layer-namespace` | Layer surface namespace | materde-shelf |
| `-y, --keyboard-interactive` | 0=none 1=exclusive 2=on_demand | 0 (shelf never grabs the keyboard) |
| `-w` / `-h` | Placeholder size; give 0 on an anchored axis to stretch | 0 / 248 (48px bar + 200px transparent menu/tooltip zone) |

Other common flags: `-b` bundle path, `-t` title, `-a` app-id, `-n` disable cursor,
`-f` fullscreen.

### 4. Static checks & tests

```bash
cd shell
~/flutter-elinux/bin/flutter-elinux analyze   # expect 0 issues
~/flutter-elinux/bin/flutter-elinux test      # expect all tests green
```

### 5. Change the theme seed (Material You dynamic color)

```bash
MATERDE_SEED=#006A6A LD_LIBRARY_PATH=build ./build/flutter-client -b … (as above)
# Recomputes the whole color-role set at startup (primary/buttons/selection all turn teal)
```

Without `MATERDE_SEED`, the default seed is used.

## Debugging cheat sheet (traps we actually hit)

| Symptom | Cause / fix |
|---|---|
| Our own INFO/TRACE logs missing | Log level defaults to WARNING — add `FLUTTER_LOG_LEVELS=INFO` (or TRACE) |
| `pkill -f "build/…"` kills your own shell | The pattern matches the outer shell's command line; use `pkill -x flutter-client` |
| Screenshots show a stale frame / race with rebuilds | Rebuild, launch and screenshot **serially**; check `md5sum libapp.so` first |
| grim can't capture the screen | Under KWin grim isn't supported — use `spectacle -b -n -o out.png` (`mkdir -p` the target dir first). In the current COSMIC session grim works: `grim -o eDP-1 out.png` |
| Shelf/probe hidden under a panel (plasmashell / COSMIC dock) | Panels live on the **top** layer; probe with `-L 2` (or `-L 3` for overlays). The COSMIC dock was disabled for dev: `entries` → `["Panel"]` |
| Weird CMake cache failures | Caused by concurrent flutter commands; delete `build/elinux/x64/*/CMakeFiles` and re-run |

## Syncing with upstream (`embedder/`)

Baseline: `sony/flutter-embedded-linux@1653fa6`; the full diff is frozen in
`embedder/patches/0001-layer-shell-support.patch`. To sync:

```bash
git clone https://github.com/sony/flutter-embedded-linux /tmp/felu
cd /tmp/felu && git checkout <target commit>
# Apply the upstream delta onto embedder/ in this repo, resolve conflicts, verify the build, then:
git diff > embedder/patches/0001-layer-shell-support.patch   # re-freeze the diff
```

## License

Our own code is licensed under the **BSD 3-Clause License**, see [LICENSE](LICENSE);
copyright notices for all third-party components (the embedder fork, rapidjson,
protocol XMLs, runner templates, …) are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
