# UCFGS Port Roadmap

This is the durable, authoritative plan for migrating UCFSS13 (DM/BYOND) to
UCFGS (GodotStation, Godot 4.7, C#/GDScript hybrid). **This file is the
source of truth** — not a Claude Code plan file (those are ephemeral and can
be silently overwritten by a later, unrelated planning session reusing the
same file path — this happened once already, on 2026-09-13, losing a fully
detailed version of this roadmap), and not a memory note (those are
condensed summaries, not full detail). Update this file directly as work
happens. Commit it. If a plan file ever contains a fuller version of a phase
than what's here, copy that detail into this file in the same turn, before
doing anything else.

## Why this migration, and why not SS14

The user's long-term successor to UCFSS13 is a full migration to a
from-scratch Godot reimplementation they already started (UCFGS), plus its
companion apps (GS-Nebula launcher, GSN-backend). An earlier idea of
migrating to SS14 (RobustToolbox/C#) was explicitly discussed and abandoned
in favor of this — the user wants full ownership/control (their own engine,
backend, DNS, infra) rather than joining or forking someone else's SS14
project.

## Working discipline: one system to 100% before the next

Each phase below must reach real feature parity with its DM source and be
demonstrated working live before moving to the next phase. Not "the
architecture supports it," not "compiles," not "a representative slice
works." The user's own prior "M2" pass on this project is the anti-pattern
to avoid: it built a little of everything at once (2 turf types instead of
the full set, a `CombatResolver` that only partially resolves grabs, a
`DoAfter` with its progress bar deferred) and nothing was ever actually
usable. A system that's 20% done everywhere is worse than finishing systems
in sequence.

## Fidelity vs. freedom: one-to-one port now, Godot-native features later

**The port itself must be nearly one-to-one with UCFSS13's actual feature
set and behavior.** Every phase's job is to reproduce what the DM source
already does, not to redesign or expand it — no new gameplay mechanics, no
"while I'm here" feature additions, no behavior that isn't traceable to a
real DM system, no matter how easy Godot makes it to add something extra.

**Implementation technique is a separate axis, and there the door is open.**
Godot has real engine capabilities BYOND never had - threading, a genuine
2D dynamic lighting/shadow system, a proper Control-node UI/theming engine
- and phases should use these well where they naturally fit the
*implementation* of a DM-equivalent feature (e.g. rendering DM's existing
lit/dark room behavior through Godot's real Light2D system instead of
faking it, building the ported UI with proper theming instead of imitating
BYOND's clunky skin.dmf look, using threading where it makes an existing
system faster or more robust). The test is: does the *player-visible
behavior* still match what DM does? If yes, build it the modern, idiomatic
Godot way. If the temptation is to make the behavior itself do something
DM never did, that's out of scope for the port - defer it.

**All of that deferred "Godot-native feature" work happens as its own
pass, only after the full one-to-one port (all 17 phases) is complete.**
Once UCFGS has real, demonstrated parity with UCFSS13, a separate planning
pass decides what to actually build using Godot's unique strengths beyond
what BYOND could ever do. Don't pull that work forward into the port phases
themselves, and don't let "we could do this so much better in Godot" become
scope creep on a phase that's supposed to be reproducing existing behavior.

## Repo locations (local disk — GitHub is stale, do not trust it for state)

- **Game:** `C:\Users\HIDga\Documents\UCFGS` — Godot 4.7, C#(.NET 8)/GDScript hybrid.
- **Launcher:** `C:\Users\HIDga\Documents\GS-Nebula` — Electron desktop app. Tags: v0.1.0, v0.1.2, v0.2.0.
- **Backend, live:** `C:\Users\HIDga\Documents\GSN-backend` — not a git repo, a live deployment folder, actually serving `api.godotstation.online`.
- **Backend, stale:** `C:\Users\HIDga\Documents\GS-backend` — Feb-2026 snapshot, superseded, points at a dead domain. Archive (rename aside), don't delete, only with explicit confirmation.
- **Old prototype history:** git branch `origin/archive/pre-m2-history` in the UCFGS repo (~1 year, 111 commits) — not an ancestor of current HEAD, kept for potential salvage-mining only.

## Current real state (verified 2026-09-13 / 2026-09-14 by direct code audit, not assumed)

### UCFGS (the game)

- Last commit: `b6ebd350`, 2026-07-21. Dormant since.
- Real architecture: `Atom`/`IGameSubsystem` pattern mirroring DM's `/atom` + `SSxxx` design. Exactly **4 subsystems exist**: `TimerSubsystem`, `GarbageSubsystem`, `TickerSubsystem` (`Scripts/Core/Subsystems/`), and `LifeSubsystem` (`Scripts/Game/Mobs/`), orchestrated by `SubsystemManager.cs` (221 lines).
- **Networking is mob-centric only — this is Phase 1's real scope.** `Scripts/Game/Mobs/PlayerMob.cs` (885 lines) is the only heavily-networked class: ~20+ client-request RPCs (`[Rpc(MultiplayerApi.RpcMode.AnyPeer)]`, called via `RpcId(1, ...)`) for movement, pickup/drop, attack, equip, examine, throw, grab, etc., matched by server-authority broadcast RPCs (`[Rpc(MultiplayerApi.RpcMode.Authority)]`) for position/facing/HUD-health/HUD-hands/HUD-intent/equipment-visuals. Four other files have narrow single-purpose RPCs: `GameRoot.cs` (round/spawn flow), `ChatManager.cs` (chat), `StateController.cs` (posture toggle), `LateJoinLobbyUI.cs` (job assignment). **`Atom.cs` (44 lines, the base class for every world object) has zero RPC/authority code.** `MultiplayerSynchronizer` has zero matches anywhere in the project. Turfs, dropped items, and structures either don't replicate at all or only change as a side effect of a mob RPC.
- **Turfs:** only 2 concrete types exist (`FloorTurf` 14 lines, `WallTurf` 23 lines) atop a real abstract hierarchy (`Turf` 60, `OpenTurf` 13, `ClosedTurf` 13) added in the most recent architecture pass.
- **Doors/airlocks do not exist as classes at all** — zero matches for door/airlock anywhere in `Scripts/`.
- **Combat:** `CombatResolver.cs` (91 lines) exists but `ResolveGrab()` is an explicit stub per its own code comment. `PlayerInteractionSystem.cs` (267 lines) handles the click/grab layer.
- **DoAfter:** `DoAfterComponent.cs` (91 lines) is functionally complete — timer, move-distance cancel, incapacitation cancel, `GetProgress()` — but its progress-bar visual is confirmed still unwired. Its own code comment explains the old hardcoded-uid animation was dropped (pointed at a deleted asset) and never replaced; `DoAfterStarted`/`Completed`/`Cancelled` signals exist as the hook for whenever a real visual gets built.
- **Health/limb/fire/inventory:** `HealthSystem.cs` (460 lines), `LimbSystem.cs` (189), `MobStateSystem.cs` (147, has a flagged placeholder rotation visual), `FireSystem.cs` (135), `Inventory.cs` (219, real 16-slot system), `ItemData.cs` (40) all exist and look substantial, but have **not** been audited line-by-line against DM's actual behavior — don't assume parity, verify when each phase comes up.
- **`MobAppearance.cs`** (137 lines): the 22-layer DMI-based renderer, reuses converted BYOND `.dmi` sprites via `Tools/dmi_convert.py` (existing UCFSS13 art does not need to be redrawn). Has one flagged placeholder: the prone-pose visual.
- **The "Communications" UI shell** (`Scripts/UI/Communications.gd`, 578 lines, restored in the last commit) is now the **real, permanent post-menu game frame** — `MainMenu.gd` points `GAME_ROOT_SCENE` at it. It's a side panel with chat log + tab bar (Status/Debug/IC/OOC/Object/Tickets/Options — most intentionally left as stub tabs) wrapped around two `SubViewport`s (lobby screensaver ↔ live `GameRoot.tscn`), owning round-start/lobby-timer UI, late-join UI, and admin tool popups (falls back to a "WIP" label if a given tool isn't restored). Wired to `ChatManager`, `TickerSubsystem`, `JobManager`. **This is not a blank slate for Phase 15** — the main frame already exists; remaining UI work is the stubbed tabs and whatever else isn't covered.
- **Stale uncommitted WIP was present as of 2026-09-13** (new USCM item scenes, edits to `MobAppearance.cs`/`PlayerMob.cs`/`MovementController.cs`/`PreferenceMenu.gd`, new `Fonts/Shaders/Themes` folders) — confirmed stale by the user, discarded before this roadmap was finalized. Verify `git status` is clean before trusting this.

### GS-Nebula (launcher)

- Clean tree, dormant since 2026-07-14. Tags v0.1.0 → v0.1.2 → **v0.2.0** (previously undocumented).
- **v0.2.0** (`571a366` + `bb06dd8`) added: a full **"GameMaker" companion tool** — a second Electron window for editing game content, with a DMI sprite-sheet parser/exporter (`gamemaker/dmi-parser.js`, IPC handlers `gamemaker:dmi:parse`/`dmi:getStateFrames`/`dmi:exportState`) and a mini file manager (list/mkdir/rename/delete/reveal/read/write), using new `codemirror`+`jimp` deps; and **local-server-hosting from the launcher UI** (`hostLocally()`/`stopHosting()` in `renderer/app.js`, `game:launch` now accepts `hostMode`/`hostPort` and passes `--host --port <n>` to the game process) — ties directly into the backend's server-registry endpoints below. Also **removed admin mode** entirely (`STATE.isAdmin`, `applyAdminMode()`, admin badge UI, `start:admin` script all deleted). No bug-fix commits in this range — pure feature/infra work, including migrating the backend domain to `api.godotstation.online` and adding a real `package-lock.json` for CI.

### GSN-backend (live deployment)

- Not a git repo — a live deployment folder mirroring what's actually deployed. `server.js` (Express+`pg`+`ws`, 1,382 lines) is real and fully wired, not scaffolding:
  - **Auth:** Discord OAuth (Passport) + JWT/bcrypt, `/api/auth/{discord,exchange,register,login,me}`.
  - **Server registry/matchmaking:** `/api/servers/{register,list,heartbeat,deregister,unregister}` — what GS-Nebula's new local-hosting feature talks to.
  - **Friends:** request/respond/pending/list/delete.
  - **Chat:** REST history/upload/send + a live WebSocket server for realtime delivery.
  - **Moderation** (`moderation.js`, real): ban/mute/warn/unban/unmute/role/log/reports, staff/admin-gated.
  - **GDPR** (`gdpr-compliance.js`, real but bare-bones): only `my-data` and `delete-account`.
  - **`panel/`** is a separate, genuinely functioning ops app (1,825 lines, own Express instance, session auth) that starts/stops/restarts the dedicated server process, manages logs/roles/scripts/audit log — this is what actually drives the `GodotStationServer.x86_64`/`.pck` binaries sitting in the folder.
  - **`schema.sql`**: `users`, `friendships`, `messages` (with optional E2E fields), `servers`, `token_blacklist`, `moderation_actions`, `message_reports`.

### DM source scope for the next 4 roadmap phases (verified by direct survey)

- **Turfs** (`code/game/turfs/`, 22 files/~14,900 lines): base contract is density/opacity + `directional_opacity` (partial per-direction vision blocking), a `baseturfs` list (multi-layer excavation stack — e.g. floor → plating → space), and a canonical `ChangeTurf()` replace-in-place proc used everywhere from explosions to construction. Wall destructibility is the one real logic subsystem: HP pool, `attackby()`-driven welding/nailgun repair (percentage-based, material-typed), `dismantle_wall()` (girder + debris), `ex_act()` explosion-severity shrapnel, reinforced variant with higher HP, mineral walls that spawn ore. The ~180 leaf turf subtypes across the tree are overwhelmingly per-biome/per-map icon_state reskins — asset work, not logic work.
- **Doors/airlocks** (`code/game/machinery/doors/`, 17 files/~5,550 lines): base `door.dm` (316 lines) gives open/close/bump-to-open/autoclose/multi-tile support. `airlock.dm` (922 lines) is the full-parity target and the single biggest near-term chunk of work: ID-based access control (`allowed()`/`req_access`), a hackable multi-wire panel (bolts/main power/backup power, each independently sabotageable via cut/mend/pulse), dual independent power rails with auto-regain timers, electrification, HP/damage leading to forced-open/destroyed states, and tool interactions (weld shut/open, crowbar-force when unpowered, screwdriver exposes wires, multitool hacks). ~184 airlock subtypes are cosmetic/access-requirement only. Related but distinct: firedoors (atmos/fire-alarm triggered), poddoors/shutters (blast doors, no ID logic), windowdoors (breakable independent of lock state), railings (vaultable, partial vision block).
- **Click/combat** (`code/_onclick/click.dm` 481 lines + `code/modules/mob/living/`): `client/Click()` → adjacency check → dispatch to `attackby()`/`afterattack()`/`attack_hand()`/`UnarmedAttack()`, with click-rate throttling and signal interception points. A 4-bitflag intent system (Help/Disarm/Grab/Harm). Resolution is intent-branched, not a universal to-hit roll: HELP does CPR/help-pickup (do_after-gated), GRAB starts a separate stateful pull/escalation system (passive→aggressive→carry→choke, resolved per life-tick, choke applies oxy damage), HARM picks a species unarmed-attack type and always lands (random weighted hit-zone, armor-reduced brute damage — misses only happen in ranged combat), DISARM is a skill-modified percentage check (knockdown+stun / break-grab-or-drop-item / total miss, plus a chance to discharge a held gun).
- **DoAfter** (`code/__HELPERS/unsorted.dm`, `/proc/do_after`, ~150 lines): a single global proc, not a class — tick loop (default 5 chunks via `sleep()`) with an optional busy-icon overlay (`icons/mob/do_afters.dmi`) and a large bitflag set of interrupt conditions checked every tick for user and target independently (moved, unconscious, knocked down/stunned/dazed, resisting, changed body zone, out of range, lost/gained required item, clicked during wait), plus an arbitrary custom-callback escape hatch. UCFGS's `DoAfterComponent.cs` already covers most of the logic; the real gap is the visual and full interrupt-flag parity.

## The 17 phases, in order

Each phase is one system, taken to full DM-parity completion and demonstrated working live before the next starts.

1. **Networking / replication** — generalize the proven `PlayerMob.cs` client-request/server-authority-broadcast pattern so turfs, dropped items, and (once they exist) doors replicate to every client, not just the player's own mob's state. This is extending a working pattern, not building networking from scratch. **Status: item ground-state replication done (2026-09-14) — see below. Turf-mutation replication deliberately deferred until Phase 2/3 build an actual turf-mutation feature to wire it into (no untested plumbing with zero callers).**

   **Done (2026-09-14):** `Item.PlaceInWorld`/`RemoveFromWorld` (drop/pickup-from-ground) now broadcast via `SyncPlaceInWorld`/`SyncRemoveFromWorld` (`[Rpc(Authority, CallLocal = false)]`, mirroring `PlayerMob.SyncPosition`'s exact convention), plus late-join catch-up (`Item.ReplayGroundStateTo`, called from `GameRoot.OnPeerConnected` via a new `WorldGrid.GetAllOccupants()`) so a peer joining mid-round sees items that have already moved, not just their scene-authored defaults. **No new network-ID/registry system was needed or added** — Godot's `Rpc()` targets nodes by matching `NodePath`, and this codebase's existing deterministic scene-authoring + broadcast-spawn convention already guarantees identical paths across peers, so `item.Rpc(...)` already finds the right node everywhere. **Explicit scope boundary:** an item currently *held in an inventory* (not on the ground) at the moment of late-join is NOT replayed — that's Phase 8 (Inventory mechanics) territory, not this pass's job.

   **Live-tested (2026-09-14):** ran two real, independent Godot processes headless (`godot --headless --path <dir> -- --host` / `-- --join-server 127.0.0.1:8910`, launched via PowerShell to avoid Git Bash's `--` argument mangling) and confirmed actual ENet connectivity end-to-end: host logs `Peer connected: <id>`, client logs `Connected to server.` + `Peer connected: 1`. **This also surfaced and fixed a real, previously-unverified bug**: `MainMenu._parse_args()` used `OS.get_cmdline_args()`, which returns empty in this exact invocation shape — `OS.get_cmdline_user_args()` is the correct API and now used instead. Without this fix, `--host`/`--join-server` never actually parsed, meaning GS-Nebula's local-hosting feature (which launches the game the same way, per the v0.2.0 audit above) may never have worked either.

   **Automated test harness built, but blocked on a real environmental issue (2026-09-14):** built `Tools/multiplayer_tests/phase1_item_replication.ps1` plus real cmdline-driven test hooks (`TestHarnessConfig.cs`, `--auto-start-round`, `--auto-drop-delay`, permanent `[Item] placed/removed` logging in `Item.cs`) — not a throwaway script, real committed infrastructure meant to serve every future phase's verification. Extensive direct testing found a genuine, unresolved blocker: the moment a host and client actually establish a network connection, one or both processes intermittently show a resurrected "Rapier2D extension" error and a resurrected AudioManager parse error — both bugs that are correctly fixed in the source and confirmed fine in isolation. Ruled out one at a time, each with a real test: shared vs. fully isolated per-instance project copies (no shared files at all - still happens), two concurrent bare instances with no networking (fine), two concurrent hosts with no successful join (fine), read-only-locking the resource cache, multi-second settle delays, avoiding `--quit-after`, a from-scratch C# rebuild. The trigger is narrowly "two Godot-Mono processes on this machine establish a real connection to each other," which persisted even with zero shared filesystem state - pointing at something environmental (.NET diagnostics/IPC, antivirus interference with cross-process sockets, or a genuine Godot engine issue on this exact version/platform), not a defect in `Item.cs`/`GameRoot.cs`/`PlayerMob.cs`. Not chased further past this point - see [[feedback_full_system_completion_before_next]]'s corollary on honest reporting over indefinite guessing.

   **Manually verified working (2026-09-14), and a new verification convention adopted going forward:** two real windows via Godot's own "Run Multiple Instances" (not two separate full editor windows, which hits an unrelated editor project-lock conflict) connected, hosted, and joined successfully, with real gameplay interaction happening (item pickups logged). This also caught and fixed two real, unrelated bugs found along the way: `PlayerInterface.gd`'s Pull button was declared as a `Sprite2D` in the scene but the code called `.gui_input` on it (only `Control` nodes have that signal) - now a `TextureButton`, matching its sibling "Run" button's existing convention; and `TextInput.gd` had an implicit int-to-enum assignment warning, now explicitly cast. Going forward, manual play-verification doesn't require narrating every event back over chat: **`RoundLogger`** (`Scripts/Core/Diagnostics/RoundLogger.cs`, autoloaded) now records connections, map loads, spawns, and item state changes to `user://round_logs/round_<timestamp>.log` when a round ends - read that file instead. Add a `RoundLogger.Log(category, message)` call at the point of change whenever a new system lands (matches `Item.cs`'s own convention already). The automated headless harness (`Tools/multiplayer_tests/phase1_item_replication.ps1`) is kept as real infrastructure but is blocked on an unresolved environmental issue specific to concurrent Godot-Mono processes on this dev machine (see the entry above) - not pursued further past that point in favor of this more direct, sustainable manual-plus-log-file approach.
2. **Turfs** — full `OpenTurf`/`ClosedTurf` contract (opacity incl. directional, baseturfs stack, `ChangeTurf`-equivalent) plus wall destructibility/repair. Reskin variety is asset work, sequence last within this phase. **Status: architecture exists (2 types), full contract + destructibility not started.**
3. **Doors/airlocks** — brand new system: base door class, then full airlock parity (wire panel, dual power rails, bolts, damage/forced-entry, tool interactions). Largest near-term phase by DM line count (~5,550 lines of source behavior). **Status: not started, zero classes exist.**
4. **Click / combat interaction** — adjacency dispatch + 4-intent system + per-intent resolution (no-roll harm, probability-based disarm, stateful grab/pull/choke escalation). **Status: `PlayerInteractionSystem.cs` and `CombatResolver.cs` exist as a starting frame; `ResolveGrab()` is an explicit stub.**
5. **DoAfter** — wire a real progress-bar visual to `DoAfterComponent`'s existing signals; verify interrupt-condition coverage against DM's full flag set. **Status: logic complete, visual missing.**
6. **Health / limb / fire system** — audit `HealthSystem`/`LimbSystem`/`MobStateSystem`/`FireSystem` against DM's damage-type/organ/shock model; finish the flagged placeholder visuals (rotation, prone pose). **Status: substantial code exists, unaudited against DM parity.**
7. **Species / body customization** — character creation, species selection, body/appearance customization. **Status: not started.**
8. **Inventory mechanics** — audit `Inventory.cs`/`ItemData.cs` against DM's storage-container and equip-restriction behavior; extend as needed. **Status: base 16-slot system exists, unaudited for full parity.**
9. **USCM core content** — the primary playable faction's full item/weapon/clothing/job roster. **Status: not started** — do not resurrect the discarded stale WIP item scenes as-is; re-derive from DM source when this phase starts.
10. **Remaining ~14 factions, one at a time** — same one-system-to-100% discipline applies within this phase. **Status: not started.**
11. **Vehicles** — full vehicle system port. **Status: not started.**
12. **Map import pipeline** — tooling to bring DM `.dmm` maps into Godot. **Status: not started.**
13. **All 21 maps** — import and verify every map via the phase-12 pipeline. **Status: not started.**
14. **Xenomorph system** — castes, abilities, AI controller. Deliberately last — most complex single system, depends on combat/health/click being solid first. **Status: not started.**
15. **Remaining UI** — `Communications.gd` already covers the main game frame (chat, round/lobby UI, late-join, admin popups); scope here is its intentionally-stubbed tabs (Status/Debug/IC/OOC/Object/Tickets/Options) and anything not covered elsewhere. **Status: main frame done, stub tabs remain.**
16. **Launcher / backend feature parity** — GS-Nebula (GameMaker tool, local hosting) and the backend (auth/registry/chat/moderation) are already substantially real; scope here is wiring the finished game to actually use them end-to-end, plus the bare-bones GDPR/staff-tooling gaps. **Status: launcher/backend both real and ahead of the game in places — verify end-to-end wiring when this phase comes up, don't assume it needs building from scratch.**
17. **Playtesting / polish** — final pass once all systems are complete. **Status: not started.**

## Next step

Phase 1's detailed implementation plan (how exactly to generalize replication onto `Atom` — e.g. a per-atom authority-broadcast convention matching `PlayerMob`'s existing style vs. Godot's built-in `MultiplayerSynchronizer`) is a dedicated planning pass of its own, not summarized here.
