# Balthazar

An Android app for playing French card games with friends online, made with Godot 4.7 and GDScript. Belote classique comes first, then Coinche, Tarot and others. **[GDD.md](GDD.md) is the reference for the rules and the roadmap**: read the relevant section before changing a rule, and update it when a decision changes.

## Workflow

- Work directly on `main`. Commit each change set, but never push: the author pushes.
- **Bump `config/version` in `project.godot` in every commit**, as semantic versioning. Only the patch number goes up (0.1.x) until the author says otherwise. CI derives the Android `versionCode` from it.
- Each push runs the tests and builds a debug APK and a Windows build (`.github/workflows/build.yml`), uploaded as artifacts kept 7 days. The APK is signed with the committed debug keystore (`tools/debug.keystore`), so each build installs over the previous one.
- The PC has no Android SDK or JDK: Android builds happen only in CI.

## Commands

`godot` is on the PATH (it wraps the console exe). Run it from PowerShell: Git Bash doesn't resolve `godot.cmd`.

```
godot --headless --path . --import                   # after adding scripts or assets (registers class_names)
godot --headless --path . -s addons/gut/gut_cmdln.gd # all tests (GUT, config in .gutconfig.json)
godot --headless --path . --quit-after 300           # run briefly and check the log for errors
```

**Never pop a window on the user's monitor** (see double-cooked's `tools/screenshot.gd` for the off-screen technique).

`bash tools/fetch_deps.sh` downloads the git-ignored `addons/` (tube, gut, webrtc_native) at pinned versions. On this machine, set `CURL_EXTRA=--ssl-revoke-best-effort`.

## Architecture

- `core/` is the game-agnostic card engine, as plain `RefCounted` / static classes with no nodes. Cards are ints (`Cards`).
- `games/<game>/` holds one game's rules. It is **pure and deterministic**: one seed and the list of moves replay a whole game. No `Input`, clock, scene tree or global RNG. This is what later lets a referee check ranked games (GDD §6).
  - Rule variants are a `RuleSet`: flags for simple tweaks, swappable strategy objects (bidding, trick legality, announces, scoring) for deeper variants.
- `bots/` pick moves from the legal moves. They fill empty seats, and headless bot games are the main test of the rules.
- `network/`: Tube (WebRTC P2P, sessions shared by code). The host owns the state and sends each player only what that seat may see. **Tests must never open sockets or ports**: this machine has no firewall rights. Use an in-memory transport.
- `ui/`: the landscape phone table. It only displays the state and turns taps into moves.

## Conventions

- Indent with 4 spaces, give functions typed signatures, and add a `##` doc comment on each class and on non-obvious members.
- Organise files by location, not by type. The game must work without the UI.
- In-game text is in French. Never rely on non-Latin glyphs (♠♥ etc.) in on-screen text: they don't render with the default font in exported builds. Draw suits as images instead.
- Don't edit `.godot/`. Commit the `*.uid` files that Godot generates next to new scripts.
