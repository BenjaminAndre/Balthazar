# Balthazar

An Android app for playing French card games with friends online, made with Godot 4.7 and GDScript. Belote classique comes first, then Coinche, Tarot and others. **[GDD.md](GDD.md) is the reference for the rules and the roadmap**: read the relevant section before changing a rule, and update it when a decision changes.

## Workflow

- Work directly on `main`. Commit each change set, but never push: the author pushes.
- **Bump `config/version` in `project.godot` in every commit**, as semantic versioning. Only the patch number goes up (0.2.x) until the author says otherwise. CI derives the Android `versionCode` from it.
- Each push runs the tests and builds a debug APK and a Windows build (`.github/workflows/build.yml`). On `main` they replace the assets of the rolling `latest` GitHub release, like Brigade; other branches get 7-day artifacts. The APK is signed with the committed debug keystore (`tools/debug.keystore`), so each build installs over the previous one.
- The PC has no Android SDK or JDK: Android builds happen only in CI.

## Commands

`godot` is on the PATH (it wraps the console exe). Run it from PowerShell: Git Bash doesn't resolve `godot.cmd`.

```
godot --headless --path . --import                   # after adding scripts or assets (registers class_names)
godot --headless --path . -s addons/gut/gut_cmdln.gd # all tests (GUT, config in .gutconfig.json)
godot --headless --path . --quit-after 300           # run briefly and check the log for errors
godot --path . --resolution 64x64 -s res://tools/screenshot.gd -- out.png playing   # home, bidding, playing, summary
```

**Never pop a window on the user's monitor.** `tools/screenshot.gd` renders a 1600×720 screen off-screen into a SubViewport (setups listed in the script).

`bash tools/fetch_deps.sh` downloads the git-ignored `addons/` (tube, gut, webrtc_native) at pinned versions. On this machine, set `CURL_EXTRA=--ssl-revoke-best-effort`.

## Architecture

- `core/` is the game-agnostic card engine, as plain `RefCounted` / static classes with no nodes. Cards are ints (`Cards`).
- `games/<game>/` holds one game's rules. It is **pure and deterministic**: one seed and the list of moves replay a whole game. No `Input`, clock, scene tree or global RNG. This is what later lets a referee check ranked games (GDD §6).
  - Rule variants are a `RuleSet`: flags for simple tweaks, swappable strategy objects (bidding, trick legality, announces, scoring) for deeper variants.
- `bots/` pick moves from a seat's view only (never other hands). Levels: `BeloteBot` (Facile), `BeloteBotDifficile` (card memory in `BeloteMemory`, direct calls), `BeloteBotZinzin` (13 readable settings along the axes of card play: power/points, trust in the partner, set up/cash, free suit; trust is a probability from `BeloteMemory.keep_probability`; settings in the generated `zinzin_genome.gd`), and `BeloteBotPimc` (sampling search, only used in the arena for now). `BotArena` compares bots on duplicate hands.
  - `godot --headless --path . -s res://tools/arena.gd -- difficile facile 2000` prints the average lead per hand.
  - `godot --headless --path . -s res://tools/train.gd -- 150 32` (generations, deals per opponent) evolves Zinzin: 50 genomes all play the same deals against Difficile (fixed anchor, weight 6) and against rivals from the previous generation. Work is split across 16 `godot` worker processes (`tools/train_worker.gd`, jobs in `TrainJobs`): GDScript threads barely scale. About 9 s per generation; run it in the background. One line per generation goes to stdout and to `train.log` (git-ignored). It rewrites `bots/zinzin_genome.gd` (a fifth of the first population starts from it) and `docs/zinzin.md`.
- `table/`: `TableHost` runs a table: it owns the state, plays the bots, and sends each human seat packets `{event, view}` with only what that seat may see. The table screen (`ui/table.gd`) only plays those packets, so the same screen works solo, as host and as guest.
- `network/`: `Online` (autoload) holds the TubeClient (WebRTC P2P, sessions shared by code) and a `TableLink`, whose RPCs seat the guests and carry moves and per-seat packets. The host's TableHost lives under the link, so it survives scene changes. **Never run Tube on this PC** (it opens sockets): `tests/network/` drives `TableLink` over in-memory `LoopbackPeer`s instead, and `tools/screenshot.gd lobby` shows the lobby without Tube. The host owns the state and sends each player only what that seat may see. **Tests must never open sockets or ports**: this machine has no firewall rights. Use an in-memory transport.
- `ui/`: the landscape phone table. It only displays the state and turns taps into moves.
  - The look is procedural, with no image files: `felt.gdshader` (mat), `card.gdshader` (light from the top on every card), `CardView` (faces, backs, shadows). The table rebuilds its nodes on each refresh and animates only what is new since the last one (dealt cards, the card just played, the trick swept to its winner).

## Conventions

- Indent with 4 spaces, give functions typed signatures, and add a `##` doc comment on each class and on non-obvious members.
- Organise files by location, not by type. The game must work without the UI.
- In-game text is in French. Never rely on non-Latin glyphs (♠♥ etc.) in on-screen text: they don't render with the default font in exported builds. Draw suits as images instead.
- Don't edit `.godot/`. Commit the `*.uid` files that Godot generates next to new scripts.
- Keep the `Session` autoload free of references to `class_name` scripts (game, table or bot classes): such a dependency made Godot leak at exit, and even crash with a computed property. Other code reaches the profile through `Session.get_raw()`/`set_raw()`.
