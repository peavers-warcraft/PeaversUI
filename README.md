# PeaversUI

[![Ultra Performance](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/peavers-warcraft/PeaversUI/master/.github/badges/perf.json)](https://github.com/peavers-warcraft/PeaversUI/actions/workflows/perf.yml)
[![AddonSentry](https://addonsentry.io/api/public/repos/peavers-warcraft/PeaversUI/badge.svg)](https://addonsentry.io/dashboard/peavers-warcraft/PeaversUI)

The Peavers UI pack: eight addons that replace most of the World of Warcraft interface, and an installer that sets all of them up in one pass.

Part of the **Peavers Ultra Performance** family: addons that hold themselves to a published budget, measured on every push.

## What is in the pack

| Module | What it replaces |
|---|---|
| [PeaversUnitFrames](https://github.com/peavers-warcraft/PeaversUnitFrames) | Player, target, target of target and focus, with cast bars and auras |
| [PeaversMiniMap](https://github.com/peavers-warcraft/PeaversMiniMap) | The minimap — squared, cornered, with every addon button in one grid |
| [PeaversChat](https://github.com/peavers-warcraft/PeaversChat) | The chat window — flat, text tabs, clickable links, a copy button |
| [PeaversToolTip](https://github.com/peavers-warcraft/PeaversToolTip) | Tooltips — a flat box whose border carries item quality or unit reaction |
| [PeaversSystemBars](https://github.com/peavers-warcraft/PeaversSystemBars) | FPS and latency, as bars rather than a number in a menu |
| [PeaversPerformance](https://github.com/peavers-warcraft/PeaversPerformance) | Graphics settings — five presets, every CVar snapshotted before it is touched |
| [PeaversCommons](https://github.com/peavers-warcraft/PeaversCommons) | The shared library the rest are built on |
| [PeaversConfig](https://github.com/peavers-warcraft/PeaversConfig) | One settings window for the whole collection |

PeaversCommons and PeaversConfig are required. The other six are optional dependencies, and the installer configures whichever of them it finds — so a pack with three modules installed works, and says so on its first screen rather than refusing to load.

That is deliberate. A hard dependency on all eight would mean the pack stops loading the moment somebody disables one of them, and the installer's second screen is a list of modules you are allowed to turn off.

## The installer

Runs once, on your first login after installing, and never again unless you ask for it. Five screens:

1. **What you have.** Every module in the pack, and whether it is running, installed but not enabled at the character screen, or absent. Three different problems needing three different answers.
2. **Which parts you want.** Everything on by default. Unticking a module switches it off and hands that piece of the interface back to Blizzard — it does not uninstall anything, and each module's own settings turn it back on.
3. **How it should look.** Four layouts, below.
4. **Graphics.** The one screen that changes the game rather than the interface, so it gets a screen of its own and an explicit yes.
5. **A summary you have to agree to.**

**Nothing is written until you press Install.** Ticking boxes and picking layouts only edits a plan, so backing out at any point up to that button leaves the game exactly as it was found. That is the difference between an installer and a settings panel, and it is why the summary screen can promise anything at all.

Everything the installer writes lands in each module's own saved settings, where that module's own page can edit it afterwards. There is no separate pack-owned copy of your configuration, and nothing you change later gets overwritten behind your back.

### Layouts

| Layout | For |
|---|---|
| **Standard** | The suite as it ships. Frames flanking the centre, minimap squared into the top-right, tooltips on the cursor. |
| **Compact** | Everything drawn smaller and pulled in towards the middle. Suits high resolutions, where the default spread means taking your eyes off your character to read your own health. |
| **Cinematic** | Chrome out of the way. Chat faded back, addon buttons hidden until you point at them, tooltips parked in a corner instead of following the mouse, target-of-target off. |
| **Raid** | Information dense. Larger frames, longer aura rows, health in numbers and percent, a 2,000 line chat buffer, and unit tooltips suppressed in combat so nothing sits over the boss. |

Every value a layout sets is an ordinary setting afterwards. `/pui apply cinematic` switches between them without walking the wizard again, and it deliberately leaves your module choices and your graphics settings alone — those are decisions about what you have installed and what your machine can do, and neither changes because you fancied a different arrangement of frames.

## Measured performance

An installer is an odd thing to publish a performance budget for, which is exactly why it has one. The claim is narrow and easy to state: **this addon does its work once and then stops existing.** It draws nothing until you open the installer, installs no `OnUpdate`, starts no ticker, and registers no combat events. After the install it is Lua sitting still.

Negative claims rot quietly, so it is measured rather than asserted. The table below is regenerated on every push by the [Ultra Performance harness](https://github.com/peavers-code/peavers-warcraft-workflows/tree/master/perf-harness), which loads the real Config, Modules, Layouts and Installer into a Lua VM, wires five stand-in module addons in front of them, and drives complete installs of every layout. If any number goes outside `perf/budget.json`, the build fails.

<!-- perf:begin -->

> Measured on every push by the Ultra Performance harness. The build fails if any number here exceeds the budget in `perf/budget.json`.

| Check | Measured | Budget | |
|---|---:|---:|:--:|
| Packaged size | 98.3 KB | 120 KB | pass |
| Bundled libraries | 0 | 0 | pass |
| Widget calls per frame | 0 | 0 | pass |
| Widget calls per second while idle | 0 | 0 | pass |

Scenarios driven against the real addon source, outside the game:

| Scenario | Calls/frame | Notes |
|---|---:|---|
| installing the pack, four modules and a graphics preset | 0.00 | 24 calls into the module addons for the whole install, 0 frames created; happens once |
| idle, after installing | 0.00 | no OnUpdate, no ticker, no combat events: the pack does nothing at all once the installer has closed |
| layout data checked against the module settings | 0.00 | 4 layouts, 143 module blocks verified key by key |

<sub>2,611 lines of Lua · 98.3 KB packaged · no bundled libraries</sub>

<!-- perf:end -->

The same case doubles as the engine's integration test, which is the only kind available for an addon whose real behaviour is "write settings into five other addons". Four of its assertions are load bearing:

- **Ordering.** Module toggles run before layout overrides, because switching unit frames on resets every frame's `enabled` flag. The Cinematic layout turns target-of-target off, so if that order ever flips the build fails rather than a player noticing a frame they asked to be gone.
- **Deep merge.** A layout naming `units.player.x` must not blow away `units.player.height`.
- **Skipping.** A module that is not running is reported, never written to.
- **Off means off.** An unticked module gets its toggle and none of the layout.

The layout data is checked too: every key any layout writes has to be a setting the module actually has. That catches a typo here — a layout writing `zoneText` when the addon reads `zoneTextMode` — which is invisible in game. It cannot catch a module renaming one of its own settings; nothing outside that module's repository can.

## Features

<!-- peavers:features -->
- A five-screen installer that sets up the whole Peavers interface in one pass
- Nothing is written until the final screen, so backing out changes nothing
- Four layouts — Standard, Compact, Cinematic and Raid — covering the usual reasons people rearrange a UI
- Per-module on/off, with anything you switch off handed straight back to Blizzard
- Graphics presets applied through PeaversPerformance, which snapshots every CVar before it touches one
- Honest about what is missing: modules that are absent, or installed but not enabled, are named rather than silently skipped
- Switch layouts later with one command, without touching your module choices or your graphics settings
- Everything it writes is an ordinary setting in the module's own page afterwards
- Does nothing at all once the installer has closed — no ticker, no per-frame work, no combat events
<!-- /peavers:features -->

## Usage

<!-- peavers:usage -->
The installer opens by itself the first time you log in after installing the pack, a few seconds after the loading screen, and only once. If you close it with **Not now** it will not ask again — `/pui` reopens it whenever you are ready.

After that, the pack lives in the Peavers settings window under **UI Pack**, alongside every module it installed.

### Slash Commands

- `/pui` - Open the installer
- `/pui settings` - Open the Peavers UI settings page
- `/pui apply <standard|compact|cinematic|raid>` - Switch layouts without the wizard
- `/pui status` - What is installed, and what is switched on
- `/pui reset` - Offer the installer again at your next login
<!-- /peavers:usage -->

### What it deliberately does not do

**It does not touch your keybinds, action bars or Edit Mode layout.** Those are the settings people have spent years arranging, and they are also the ones a UI pack is most tempted to overwrite. Everything the installer writes belongs to a Peavers module and can be undone from that module's own page.

**It does not back your settings up.** There is nothing to restore from, because there is nothing being destroyed: each module keeps its own settings, its own profiles and its own reset. The one exception is graphics, where PeaversPerformance snapshots every CVar before it writes one and `/pperf restore` puts all of it back.

**It does not install anything.** It is a WoW addon, so it cannot download the modules it configures. It works with what it finds and names what it does not.

## Installation

### Recommended: PeaversUpdater

Download and install [PeaversUpdater](https://github.com/peavers-warcraft/PeaversUpdater/releases/latest), the desktop updater for the whole Peavers collection. It installs PeaversUI together with every module in the pack, and delivers updates before they reach CurseForge. For a UI pack this is by some distance the easier route — one download rather than eight.

### Alternative: CurseForge

1. Install [PeaversCommons](https://www.curseforge.com/wow/addons/peaverscommons) and [PeaversConfig](https://www.curseforge.com/wow/addons/peaversconfig) — both required
2. Install whichever modules you want: PeaversUnitFrames, PeaversMiniMap, PeaversChat, PeaversToolTip, PeaversSystemBars, PeaversPerformance
3. Install PeaversUI
4. Enable them on the character selection screen, and log in — the installer opens by itself

---

*Part of the [Peavers](https://peavers.io) addon collection · [Report an issue](https://github.com/peavers-warcraft/PeaversUI/issues) · [Support development on Patreon](https://www.patreon.com/Peavers)*
