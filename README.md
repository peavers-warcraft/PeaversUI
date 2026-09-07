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
4. **Graphics.** A baseline preset, and a plan for switching between presets by content. The one screen that changes the game rather than the interface, so it gets a screen of its own and an explicit yes.
5. **A summary you have to agree to.**

### Running it again

Re-running the installer gives you the clean result, not a merge onto whatever you have accumulated. Each module you keep is reset to its own defaults first, then the layout goes on top.

That matters because a layout only names the settings it cares about. Without the reset, everything it stays quiet about survives — a font size changed in March, a stray key from a version two releases back, a diagnostic mode left switched on — and the result looks like the installer half-worked.

Two deliberate limits. A module you switch **off** is not reset: turning something off means stop drawing it, not throw away how you had it set up. And it is a checkbox on the summary screen, not a rule, because it is the one genuinely destructive thing in here — settings you made outside the pack go too.

**Backing out changes nothing.** The module and graphics screens only edit a plan. The layout screen does change your interface as you click — that is the point of it — but closing the installer without finishing puts every one of those settings back exactly. Either way, walking away leaves the game as it was found.

### Trying a layout on

Click one and your interface becomes it. Immediately, on your own screen, at your own resolution, with your own addons around it.

That is the whole of the feature, and it is deliberate. The first version of this screen drew a neat little schematic of where each layout put its frames — and a picture of a layout, however good, answers a question nobody actually has. What people want to know is whether *their* screen looks right, and the only thing that answers that is their screen.

There is a **Hide the installer and look** button, because a 760-pixel window sits on top of exactly the frames a layout just moved. It leaves a small strip with **Back to installer** and **Undo**, so you can click through all four and compare.

This means the layout screen writes settings before you have pressed Install, which is worth being explicit about. It is handled carefully:

- **Closing the installer without finishing puts everything back.** Backing out has to mean backing out. Keeping a layout is a decision, and it has its own button — Install.
- The undo is built by walking the layout's own override table and recording the current value at every key it is about to write, so it cannot miss a key the layout touched or invent one it did not.
- **A key that did not exist before is recorded as absent, not skipped.** Undoing removes what a layout created as well as restoring what it changed; otherwise a layout you rejected leaves pieces of itself behind.
- Clicking through all four never compounds: each one puts the previous back before it records anything, so every snapshot is taken against the settings you walked in with.
- The undo is written to disk *before* the first change. If the game crashes mid-try, the next login says so and offers `/pui undo` — it does not silently rearrange your UI while you are reading the login screen.
- Graphics are never applied this way. The effect is invisible standing in a city, and applying a preset can want a graphics restart — not something to do to somebody who clicked a card to look at it.
- In combat the click still selects the layout but does not apply it, and says so, rather than refusing silently.

`/pui preview raid`, `/pui undo` and `/pui keep` do the same thing without the wizard.
### Graphics that follow the content

This is the part that a pile of frame positions does not give you.

A graphics preset you pick once is a compromise: high enough that the open world still looks like the game you bought, low enough that a twenty-man pull does not drop you to fifteen frames. It is the wrong setting in both places, all the time.

So the installer asks for two things instead of one. A **baseline**, applied now — and a **plan**, which says what happens when you zone:

| Where you are | Standard | Raid | Cinematic |
|---|---|---|---|
| Raid | Quality | Performance | Balanced |
| Mythic+ | Performance | Performance | Performance |
| Dungeon | back to your own settings | Performance | no change |
| Open world | back to your own settings | back to your own settings | no change |

Every context can also be set to **No change**, which leaves it alone entirely, or **My original settings**, which puts back the console variables you had before any preset was applied.

The switching itself is PeaversPerformance''s, not this pack''s — it snapshots every CVar before it writes one, defers to after combat when it has to, and announces every switch in chat so nothing happens silently. What the pack adds is the part people never get round to: a plan that is already filled in, on a screen you were going to look at anyway.

Two rules keep it honest. Choosing **Leave my graphics settings alone** as the baseline switches auto-switching off too — alone means alone. And `/pui apply <layout>`, which never asks the graphics question, never touches any of it: changing your mind about frame positions will not quietly undo a plan you set up weeks ago.

## More stuff

The pack deliberately leaves several things alone — group frames, nameplates, action bars, boss timers — because each of them deserves a specialist, and there are good ones already. The **More stuff** page lists what the author runs alongside this, whether you already have it, and why it is there.

Where a profile has been shared, a button copies a string to paste into that addon's own import box.

**The pack never writes into another addon's saved variables.** That is the obvious implementation and it is the wrong one: it means reaching into a file another author owns, against a schema that changes without notice, before that addon has loaded and read it — and there is no undo. A string pasted into the addon's own import box goes through that addon's validation and migration, and fails safely and legibly when it is out of date. One extra paste, better in every other way.

**Capturing profiles.** Every string offered here comes from that addon's *own* export function — `DandersFrames_Export()`, `Details:ExportCurrentProfile()`, `PlaterAPI:ExportProfile()` — so it is correct by construction and in exactly the format that addon's import expects. If they change the format, their exporter changes with it and this keeps working.

`/pui share`, or the **Capture my settings** button on the page, asks every addon that can be asked and stores what comes back. Anything absent, moved, throwing or returning a stub is skipped with a reason rather than leaving a button that hands you nothing.

That is also how the shipped strings are made: `/pui share lua` gives the exact block to paste into `src/Core/Extras.lua`. A profile you captured yourself always wins over a shipped one, so capturing your own settings never appears to do nothing.

Generating these offline from the saved variables on disk was considered and rejected. It is possible in principle — the compression is LibDeflate and AceSerializer, both pure Lua — but it means reimplementing each addon's profile assembly against a format with no compatibility promise, with no way to test the result short of importing it and looking. A malformed string that imports and is subtly wrong is worse than no button.

Open it with `/pui extras`, or from the Peavers settings window.

## Measured performance

An installer is an odd thing to publish a performance budget for, which is exactly why it has one. The claim is narrow and easy to state: **this addon does its work once and then stops existing.** It draws nothing until you open the installer, installs no `OnUpdate`, starts no ticker, and registers no combat events. After the install it is Lua sitting still.

Negative claims rot quietly, so it is measured rather than asserted. The table below is regenerated on every push by the [Ultra Performance harness](https://github.com/peavers-code/peavers-warcraft-workflows/tree/master/perf-harness), which loads the real Config, Modules, Layouts and Installer into a Lua VM, wires five stand-in module addons in front of them, and drives complete installs of every layout. If any number goes outside `perf/budget.json`, the build fails.

<!-- perf:begin -->

> Measured on every push by the Ultra Performance harness. The build fails if any number here exceeds the budget in `perf/budget.json`.

| Check | Measured | Budget | |
|---|---:|---:|:--:|
| Packaged size | 185.4 KB | 200 KB | pass |
| Bundled libraries | 0 | 0 | pass |
| Widget calls per frame | 0 | 0 | pass |
| Widget calls per second while idle | 0 | 0 | pass |

Scenarios driven against the real addon source, outside the game:

| Scenario | Calls/frame | Notes |
|---|---:|---|
| installing the pack, four modules and a graphics preset | 0.00 | 30 calls into the module addons for the whole install, 0 frames created; happens once |
| idle, after installing | 0.00 | no OnUpdate, no ticker, no combat events: the pack does nothing at all once the installer has closed |
| layout data checked against the module settings | 0.00 | 4 layouts, 226 module blocks verified key by key |
| extras list checked | 0.00 | 11 recommended addons, 0 with a shared profile string |
| live preview applied and undone | 0.00 | every setting restored exactly, including keys the layout created that did not exist before |
| settings pages laid out | 0.00 | 3 pages on 3 shared columns: each sizes its own scroll child, nothing overlaps in the left column, and no widget runs off the panel |

<sub>4,772 lines of Lua · 185.4 KB packaged · no bundled libraries</sub>

<!-- perf:end -->

The same case doubles as the engine's integration test, which is the only kind available for an addon whose real behaviour is "write settings into five other addons". Six of its assertions are load bearing:

- **Ordering.** Module toggles run before layout overrides, because switching unit frames on resets every frame's `enabled` flag. The Cinematic layout turns target-of-target off, so if that order ever flips the build fails rather than a player noticing a frame they asked to be gone.
- **Deep merge.** A layout naming `units.player.x` must not blow away `units.player.height`.
- **Skipping.** A module that is not running is reported, never written to.
- **Off means off.** An unticked module gets its toggle and none of the layout.
- **Trying a layout round-trips exactly.** One is applied, then undone, and every setting across four modules is compared key by key against a fingerprint taken beforehand — including a sub-table key the layout creates that did not exist before, which is the one a naive restore leaves behind.
- **Auto-switch is config, not a guess.** The plan is written into PeaversPerformance's own keys and evaluated with `force`, so the context you are standing in is acted on immediately rather than at the next loading screen — and a layout-only apply is asserted to touch none of it.

The layout data is checked too: every key any layout writes has to be a setting the module actually has. That catches a typo here — a layout writing `zoneText` when the addon reads `zoneTextMode` — which is invisible in game. It cannot catch a module renaming one of its own settings; nothing outside that module's repository can.

## Features

<!-- peavers:features -->
- A five-screen installer that sets up the whole Peavers interface in one pass
- Nothing is written until the final screen, so backing out changes nothing
- Click a layout and your interface becomes it on the spot - no screenshots, no mockups, your own screen
- Every layout you try is undone exactly if you back out, with the undo written to disk first in case the game crashes
- Four layouts — Standard, Compact, Cinematic and Raid — covering the usual reasons people rearrange a UI
- Per-module on/off, with anything you switch off handed straight back to Blizzard
- Graphics presets applied through PeaversPerformance, which snapshots every CVar before it touches one
- A graphics preset per context — raid, Mythic+, dungeon, open world — pre-filled by the layout you picked, so the settings follow what you are actually doing
- Standard is a real interface, transcribed from a live install, not four plausible-looking numbers
- Honest about what is missing: modules that are absent, or installed but not enabled, are named rather than silently skipped
- Switch layouts later with one command, without touching your module choices or your graphics settings
- Everything it writes is an ordinary setting in the module's own page afterwards
- Does nothing at all once the installer has closed — no ticker, no per-frame work, no combat events
<!-- /peavers:features -->

## Usage

<!-- peavers:usage -->
The installer opens by itself the first time you log in after installing the pack, a few seconds after the loading screen, and only once. On the layout screen, clicking a layout applies it to your interface straight away so you can see it; closing the installer without finishing puts everything back. If you close it with **Not now** it will not ask again — `/pui` reopens it whenever you are ready.

After that, the pack lives in the Peavers settings window under **UI Pack**, alongside every module it installed.

### Slash Commands

- `/pui` - Open the installer
- `/pui settings` - Open the Peavers UI settings page
- `/pui apply <standard|compact|cinematic|raid>` - Switch layouts without the wizard
- `/pui preview <layout>` - Try a layout on without the wizard
- `/pui undo` - Put your settings back after a preview
- `/pui keep` - Stop treating a tried-on layout as temporary
- `/pui extras` - Addons this pack works alongside, and shared profiles for them
- `/pui share` - Capture your own profiles from those addons
- `/pui share lua` - Those profiles as Lua, ready to paste into Extras.lua
- `/pui status` - What is installed, and what is switched on
- `/pui reset` - Offer the installer again at your next login
<!-- /peavers:usage -->

### What it deliberately does not do

**It does not touch your keybinds, action bars or Edit Mode layout.** Those are the settings people have spent years arranging, and they are also the ones a UI pack is most tempted to overwrite. Everything the installer writes belongs to a Peavers module and can be undone from that module's own page.

**It does not back your settings up.** There is nothing to restore from, because there is nothing being destroyed: each module keeps its own settings, its own profiles and its own reset. The one exception is graphics, where PeaversPerformance snapshots every CVar before it writes one and `/pperf restore` puts all of it back.

**It does not install anything.** It is a WoW addon, so it cannot download the modules it configures. It works with what it finds and names what it does not.

## Installation

### Recommended: PeaversUpdater

Download and install [PeaversUpdater](https://github.com/peavers-warcraft/PeaversUpdater/releases/latest), the desktop updater for the whole Peavers collection. It installs PeaversUI together with every module in the pack, and delivers updates before they reach CurseForge — which for a pack of eight addons is the difference between updating once and waiting on eight separate approvals.

### Alternative: CurseForge

1. Download [PeaversUI](https://www.curseforge.com/wow/addons/peaversui) — every module in the pack comes with it
2. Enable them on the character selection screen, and log in — the installer opens by itself

The pack lists all eight addons as dependencies, so one download brings the
whole suite. Any module you would rather not run can be switched off on the
installer's second step, or disabled at the character screen — the pack copes
with a module being absent and says so on its welcome screen.

---

*Part of the [Peavers](https://peavers.io) addon collection · [Report an issue](https://github.com/peavers-warcraft/PeaversUI/issues) · [Support development on Patreon](https://www.patreon.com/Peavers)*
