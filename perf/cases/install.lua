--------------------------------------------------------------------------------
-- Ultra Performance case: what PeaversUI costs while you play.
--
-- The claim being tested is unusually simple, and worth stating before the
-- numbers: **this addon does its work once and then stops existing.** It draws
-- no frames until somebody opens the installer, installs no OnUpdate, starts no
-- ticker, and registers no combat events. After the install it is a pile of
-- Lua sitting still.
--
-- That is a negative claim, and negative claims rot quietly, so the case
-- measures it rather than asserting it: it loads the real Config, Modules,
-- Layouts and Installer, wires five stand-in module addons in front of them,
-- drives a complete install of every layout, and counts what happened. If a
-- ticker ever appears, or the install starts creating frames, these numbers
-- stop being zero.
--
-- The case doubles as the engine's integration test, which is the only kind
-- available for an addon whose real behaviour is "write settings into five other
-- addons". The assertions below are load bearing:
--
--   * Ordering. Module toggles have to run before layout overrides, because
--     switching unit frames on resets every frame's `enabled` flag. Cinematic
--     turns target-of-target off, so if the order ever flips, that assertion
--     fails rather than a player noticing a frame they asked to be gone.
--   * Deep merge. A layout naming units.player.x must not blow away
--     units.player.height, and must not detach a sub-table it writes into.
--   * Skipping. A module that is not running must be reported, not written to.
--   * Off means off. An unticked module gets its toggle and none of the layout.
--   * Auto-switch is written through PeaversPerformance's own config keys and
--     evaluated with force, so the context you are standing in is acted on now
--     rather than at the next loading screen.
--   * A "none" baseline switches auto-switch off, because leave-my-graphics-
--     alone has to mean alone - but a layout-only apply, which never asked the
--     question, must not touch any of it.
--   * Re-running gives a clean result. Each kept module is reset to its own
--     defaults before the layout goes on, so nothing from an earlier setup
--     survives - and a module being switched off is NOT reset, because that
--     would throw away settings on the way out.
--   * The live preview round-trips exactly. Undo has to restore every setting
--     the layout wrote AND remove the ones it created, or a preview somebody
--     rejected leaves pieces of itself behind.
--
-- The UI files are deliberately not loaded: Wizard and Steps are built out of
-- PeaversCommons.Widgets, which is a different addon, and stubbing a widget
-- library well enough to draw against would measure the stub. What they cost is
-- covered by the fact that neither is touched until somebody opens the window.
--
-- Not addon code: this runs in the harness's fengari VM (Lua 5.3), outside WoW,
-- against globals the runner injects. Linting it as a WoW addon is a category
-- error - HARNESS_LIB and ADDON_DIR come from the runner, and the case
-- overwrites globals on purpose to drive the code under test.
---@diagnostic disable: undefined-global, deprecated, duplicate-set-field

local Stubs = dofile(HARNESS_LIB .. "/wow-stubs.lua").Install()

-- fengari is Lua 5.3; the addon is written against WoW's Lua 5.1, where unpack
-- is a global.
_G.unpack = _G.unpack or table.unpack

--------------------------------------------------------------------------------
-- Frame accounting
--
-- The headline claim is that installing creates no frames at all, so
-- CreateFrame is wrapped rather than trusted. Everything the harness's own
-- stubs would have counted is beside the point here: this addon's engine never
-- touches a widget, and the number that matters is how many it made.
--------------------------------------------------------------------------------
local framesCreated = 0
local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function(...)
    framesCreated = framesCreated + 1
    return realCreateFrame(...)
end

-- Every hop from the pack into a module addon, counted. This is the honest unit
-- for an installer: not calls per frame, but how much it asks of the rest of the
-- collection on the one occasion it runs.
local hops = 0
local function Hop() hops = hops + 1 end

--------------------------------------------------------------------------------
-- Globals the addon reads at load time
--------------------------------------------------------------------------------

_G.C_AddOns.GetAddOnInfo = function(name)
    -- Everything in the manifest is "installed" except the one module the case
    -- deliberately leaves out, so the skip path gets exercised.
    if name == "PeaversChat" then return nil end
    return name, name, "", true, nil, "SECURE"
end

_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Testrealm" end
_G.InCombatLockdown = function() return false end

--------------------------------------------------------------------------------
-- A minimal PeaversCommons
--
-- Only the two pieces the engine actually reaches for: the flat ConfigManager
-- variant PeaversUI's own config is built on, and the registry Modules:Ref
-- prefers over _G. Everything else in Commons is UI, which this case does not
-- load.
--------------------------------------------------------------------------------

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end

local registered = {}

_G.PeaversCommons = {
    ConfigManager = {
        New = function(_, addon, defaults, options)
            local config = DeepCopy(defaults or {})
            config.addon = addon
            config.defaults = DeepCopy(defaults or {})
            config.dbName = (options and options.savedVariablesName) or "DB"
            config.saves = 0
            function config:Save() self.saves = self.saves + 1 return true end
            function config:Load() return true end
            function config:Initialize() return true end
            return config
        end,
    },
    ConfigRegistry = {
        GetAddon = function(_, name) return registered[name] end,
        Register = function(_, info) registered[info.name] = info return true end,
    },
}

--------------------------------------------------------------------------------
-- Stand-in module addons
--
-- Each one carries the settings its real counterpart carries, and the methods
-- Modules.lua actually calls. The defaults are transcribed from each module's
-- own Config.lua.
--
-- What that buys, and what it does not: the KEYS assertion below catches a typo
-- in Layouts.lua - a layout writing `zoneText` when the addon reads
-- `zoneTextMode` - which is the mistake that is easy to make here and invisible
-- in game. It does NOT catch a module renaming one of its own settings; nothing
-- outside that module's repository can. Treat it as a spell-check on this
-- addon's data, not as a contract between two addons.
--------------------------------------------------------------------------------

-- ConfigManager.CommonDefaults, transcribed. Every Peavers config is the module's
-- own defaults merged over this, so a layout is free to write `bgAlpha` into a
-- module whose own defaults never mention it - and the key check has to know
-- that, or it rejects a setting the module really does have.
local COMMON_DEFAULTS = {
    frameWidth = 200, frameHeight = 100, framePoint = "CENTER",
    frameX = 0, frameY = 0, lockPosition = false,
    barHeight = 20, barSpacing = 2, barBgAlpha = 0.5, barAlpha = 1.0,
    textAlpha = 1.0, barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
    fontFace = "Fonts\\FRIZQT__.TTF", fontSize = 9,
    fontOutline = "OUTLINE", fontShadow = false,
    bgAlpha = 0.8, bgColor = { r = 0, g = 0, b = 0 },
    showOnLogin = true, showTitleBar = true, updateInterval = 0.5,
    DEBUG_ENABLED = false, customColors = {}, useGlobalAppearance = false,
}

local function FakeConfig(defaults)
    local seed = DeepCopy(COMMON_DEFAULTS)
    for key, value in pairs(DeepCopy(defaults)) do
        seed[key] = value
    end

    local config = DeepCopy(seed)
    config.defaults = seed
    config.saves = 0
    function config:Save() self.saves = self.saves + 1 Hop() return true end

    -- Mirrors the real ConfigManager Reset: defaults deep-copied back, and any
    -- key the defaults do not mention dropped. Both halves matter - a Reset that
    -- assigned table defaults by reference, or that left stray keys behind, is
    -- exactly the bug this fixture would otherwise fail to notice.
    function config:Reset()
        for key, value in pairs(self) do
            if type(value) ~= "function" and key ~= "defaults" and key ~= "saves"
                and self.defaults[key] == nil then
                self[key] = nil
            end
        end
        for key, value in pairs(self.defaults) do
            self[key] = DeepCopy(value)
        end
        self:Save()
        return true
    end

    return config
end

local function UnitDefaults(overrides)
    local unit = {
        enabled = true,
        width = 240, height = 46, x = 0, y = 0, bgAlpha = 0.85, tooltip = "always",
        barTexture = "bar", healthColorMode = "class", healthBgAlpha = 0.22,
        healthColor = { r = 0.25, g = 0.62, b = 0.36 },
        showPower = true, powerHeight = 5,
        showName = true, healthText = "percent", fontSize = 11,
        fontOutline = "OUTLINE", fontShadow = false,
        showCastBar = true, castBarHeight = 18, castBarIcon = true,
        showBuffs = true, maxBuffs = 8, showMount = false,
        showDebuffs = true, maxDebuffs = 8, auraSize = 20, auraSpacing = 2,
        buffSource = "all", debuffSource = "all",
        buffCategory = "any", debuffCategory = "any",
    }
    for key, value in pairs(overrides or {}) do unit[key] = value end
    return unit
end

local UNIT_ORDER = { "player", "target", "targettarget", "focus" }

local PUF = {
    Config = FakeConfig({
        hideBlizzardFrames = true,
        unlocked = false,
        refreshRate = 0.1,
        units = {
            player = UnitDefaults(), target = UnitDefaults(),
            targettarget = UnitDefaults(), focus = UnitDefaults(),
        },
    }),
    Core = { refreshed = 0 },
    Blizzard = {},
}
PUF.Config.UNIT_ORDER = UNIT_ORDER
function PUF.Config:GetUnit(key) return self.units[key] or {} end
function PUF.Core:RefreshAll() Hop() self.refreshed = self.refreshed + 1 end
function PUF.Blizzard:Apply() Hop() end

local PMM = {
    Config = FakeConfig({
        enabled = false, squareShape = true, size = 155, scale = 1.0,
        borderSize = 0, anchorEnabled = true, anchor = "TOPRIGHT",
        offsetX = 0, offsetY = 0, zoneTextMode = "hidden", hideZoomButtons = true,
        widgets = {}, widgetLayout = {}, objectiveTracker = "detach",
        collectButtons = true, visibility = "toggle", growDirection = "LEFT",
        buttonSize = 26, buttonSpacing = 2, buttonsPerRow = 2,
        barBackground = false, barBackgroundAlpha = 0.5, excluded = {},
    }),
    Square = {}, Buttons = {},
}
function PMM.Square:Enable() Hop() PMM.Config.enabled = true end
function PMM.Square:Disable() Hop() PMM.Config.enabled = false end
function PMM.Square:Apply() Hop() end
function PMM.Buttons:Layout() Hop() end

local PTT = {
    Config = FakeConfig({
        enabled = false, scale = 1.0, fontSize = 12, bgAlpha = 0.94,
        borderByQuality = true, borderByReaction = true,
        anchorMode = "cursor", cursorOffsetX = 12, cursorOffsetY = -12,
        anchorPoint = "BOTTOMRIGHT", anchorX = -230, anchorY = 230,
        anchorUnlocked = false,
        healthBar = true, healthBarPosition = "bottom", healthBarHeight = 6,
        healthBarColorByUnit = true, healthBarText = "none",
        classColorNames = true, showTarget = true, showItemID = false,
        showSpellID = false, showIcon = false, hideInCombat = "never",
    }),
    Skin = {}, HealthBar = {},
}
function PTT.Skin:ApplyAll() Hop() end
function PTT.Skin:RestoreAll() Hop() end
function PTT.HealthBar:ApplyLayout() Hop() end
function PTT.HealthBar:Restore() Hop() end

local PSB = {
    Config = FakeConfig({
        framePoint = "RIGHT", frameX = -20, frameY = 0, frameWidth = 200,
        barHeight = 20, barSpacing = 2, showOnLogin = false,
        showTitleBar = true, showFrameBackground = true,
        showStatNames = true, showStatValues = true,
    }),
    Core = {}, BarManager = {},
}
PSB.Core.frame = { shown = false }
function PSB.Core.frame:Show() self.shown = true end
function PSB.Core.frame:Hide() self.shown = false end
function PSB.Core.frame:SetWidth(w) self.width = w end
function PSB.Core:ApplyFramePosition() Hop() end
function PSB.Core:AdjustFrameHeight() Hop() end
function PSB.Core:UpdateFrameBackground() Hop() end
function PSB.Core:UpdateTitleBarVisibility() Hop() end
function PSB.Core:UpdateFrameLock() Hop() end
PSB.Core.contentFrame = {}
function PSB.BarManager:CreateBars() Hop() end
function PSB.BarManager:ResizeBars() Hop() end

local appliedPresets = {}
local PPERF = {
    Config = FakeConfig({
        activePreset = false,
        autoSwitchEnabled = false,
        autoSwitchRaid = "performance",
        autoSwitchMythicPlus = "performance",
        autoSwitchDungeon = "none",
        autoSwitchWorld = "restore",
    }),
    Presets = {
        order = { "maximum", "quality", "balanced", "performance", "minimum" },
        presets = {
            maximum     = { name = "Maximum",     blurb = "Everything cranked" },
            quality     = { name = "Quality",     blurb = "Mild FPS wins" },
            balanced    = { name = "Balanced",    blurb = "Noticeable FPS gains" },
            performance = { name = "Performance", blurb = "Big FPS gains" },
            minimum     = { name = "Minimum",     blurb = "Potato" },
        },
    },
    PresetManager = {
        ApplyPreset = function(key)
            Hop()
            appliedPresets[#appliedPresets + 1] = key
        end,
    },
}

PPERF.Presets.GetName = function(key)
    local preset = PPERF.Presets.presets[key]
    return preset and preset.name or key
end

-- Mirrors PeaversPerformance's own AutoSwitch: the same four contexts under the
-- same config keys, and an Evaluate that records rather than acts.
local evaluations = 0
PPERF.AutoSwitch = {
    contexts = {
        { key = "raid",       name = "Raid",       configKey = "autoSwitchRaid" },
        { key = "mythicplus", name = "Mythic+",    configKey = "autoSwitchMythicPlus" },
        { key = "dungeon",    name = "Dungeon",    configKey = "autoSwitchDungeon" },
        { key = "world",      name = "Open world", configKey = "autoSwitchWorld" },
    },
    Evaluate = function(force)
        Hop()
        evaluations = evaluations + 1
        -- The installer must force, or PeaversPerformance's same-context guard
        -- decides nothing changed because the zone did not.
        assert(force == true, "AutoSwitch.Evaluate must be called with force=true, got " .. tostring(force))
    end,
}

-- PeaversChat is deliberately absent: nothing is put in _G for it, and
-- GetAddOnInfo above returns nil for it, so the case covers a module that is not
-- installed at all rather than only the happy path.
_G.PeaversUnitFrames = PUF
_G.PeaversMiniMap = PMM
_G.PeaversToolTip = PTT
_G.PeaversSystemBars = PSB
_G.PeaversPerformance = PPERF
_G.PeaversCommons.ConfigRegistry:Register({ name = "PeaversUnitFrames", addonRef = PUF })
_G.PeaversCommons.ConfigRegistry:Register({ name = "PeaversMiniMap", addonRef = PMM })
_G.PeaversCommons.ConfigRegistry:Register({ name = "PeaversToolTip", addonRef = PTT })
_G.PeaversCommons.ConfigRegistry:Register({ name = "PeaversSystemBars", addonRef = PSB })
_G.PeaversCommons.ConfigRegistry:Register({ name = "PeaversPerformance", addonRef = PPERF })

--------------------------------------------------------------------------------
-- Load the real engine
--
-- In TOC order, and asserted to be in TOC order: Installer captures PUI.Modules
-- and PUI.Layouts at load time, so getting this wrong would leave it holding
-- nils and the case would measure nothing.
--------------------------------------------------------------------------------

local PUI = { name = "PeaversUI", version = "1.0.0" }

local function Load(path)
    local chunk = assert(loadfile(ADDON_DIR .. "/src/" .. path))
    return chunk("PeaversUI", PUI)
end

Load("Utils/Config.lua")
Load("Core/Modules.lua")
Load("Core/Layouts.lua")
Load("Core/Installer.lua")
Load("Core/Preview.lua")
Load("Core/Extras.lua")

assert(PUI.Config and PUI.Modules and PUI.Layouts and PUI.Installer and PUI.Preview,
    "engine did not load: check the file order against PeaversUI.toc")

local Modules = PUI.Modules
local Layouts = PUI.Layouts
local Installer = PUI.Installer

--------------------------------------------------------------------------------
-- Every layout writes keys the modules actually have
--------------------------------------------------------------------------------

local KNOWN = {
    unitframes = PUF.Config,
    minimap = PMM.Config,
    tooltip = PTT.Config,
    systembars = PSB.Config,
    -- PeaversChat is not loaded in this case, so its keys are listed rather
    -- than read off a live config. Transcribed from PeaversChat/src/Utils/Config.lua,
    -- and merged over COMMON_DEFAULTS below the same way a real config is.
    chat = {
        enabled = true, background = true, bgAlpha = 0.6, border = true,
        paddingLeft = 8, paddingRight = 6, paddingTop = 6, paddingBottom = 6,
        -- The legacy pair, kept in PeaversChat's defaults so migration has
        -- something to read on a profile that predates the four-sided split.
        padding = 6, paddingSplit = false,
        edgeToEdge = true, fontSize = 13, fontOutline = "NONE", shadow = true,
        fading = false, timeVisible = 120, maxLines = 1000,
        styleTabs = true, tabFontSize = 12, tabFont = "", tabsInside = true,
        tabStripHeight = 0, tabUppercase = true, tabUnderline = true,
        styleEditBox = true, editBoxPosition = "bottom", editBoxHeight = 22,
        altArrowKeys = false, editBoxChannelColor = true,
        showMenuButton = false, showSocialButton = false, showScrollButtons = false,
        showBottomButton = true, showVoiceButtons = false, showCombatLogBar = false,
        urlLinks = true, urlBrackets = true,
        copyButton = true, copyStripColors = true, copyButtonVisibility = "dim",
        copyIconSize = 11, shortChannelNames = true, timestamps = "default",
        -- Where the window sits. Distinct from edgeToEdge, which only removes
        -- the clamping inset - see PeaversChat/src/Core/Position.lua.
        positionEnabled = false, chatPoint = "BOTTOMLEFT",
        chatX = 0, chatY = 22, chatWidth = 0, chatHeight = 0,
        -- The bisect backups. Their presence is what Modules.Warn reads.
        withoutBackup = {}, minimalBackup = {},
    },
}

for key, value in pairs(COMMON_DEFAULTS) do
    if KNOWN.chat[key] == nil then KNOWN.chat[key] = value end
end

-- Settings whose contents are free-form rather than a fixed set of keys: a
-- minimap widget name, a stat name, a button frame name. The setting itself is
-- checked, its contents are not, because there is no list of valid keys to check
-- them against - the module invents them at runtime from whatever is loaded.
local OPAQUE = {
    widgets = true,
    widgetLayout = true,
    customColors = true,
    excluded = true,
}

local function CheckKeys(layoutKey, moduleKey, overrides, known, path)
    for key, value in pairs(overrides) do
        local where = layoutKey .. "." .. moduleKey .. "." .. path .. key
        assert(known[key] ~= nil, where .. " is not a setting the module has")
        if type(value) == "table" and type(known[key]) == "table" and not OPAQUE[key] then
            CheckKeys(layoutKey, moduleKey, value, known[key], path .. key .. ".")
        end
    end
end

local contextKeys = {}
for _, ctx in ipairs(PPERF.AutoSwitch.contexts) do contextKeys[ctx.key] = true end

local layoutsChecked, keysChecked = 0, 0
for _, entry in ipairs(Layouts:Sorted()) do
    layoutsChecked = layoutsChecked + 1
    for moduleKey, overrides in pairs(entry.layout.overrides or {}) do
        local known = KNOWN[moduleKey]
        assert(known, entry.key .. " overrides unknown module '" .. moduleKey .. "'")
        for _ in pairs(overrides) do keysChecked = keysChecked + 1 end
        CheckKeys(entry.key, moduleKey, overrides, known, "")
    end
    assert(entry.layout.name and entry.layout.blurb and entry.layout.graphics,
        entry.key .. " is missing a name, blurb or graphics suggestion")
    assert(PPERF.Presets.presets[entry.layout.graphics],
        entry.key .. " suggests a graphics preset that does not exist: " .. entry.layout.graphics)

    -- The auto-switch plan is checked the same way the overrides are: every
    -- context has to be one PeaversPerformance knows about, and every target
    -- has to be a real preset or one of the two pseudo-targets.
    local plan = entry.layout.autoSwitch
    assert(plan, entry.key .. " has no auto-switch plan")
    for _, ctx in ipairs(PPERF.AutoSwitch.contexts) do
        local target = plan[ctx.key]
        assert(target ~= nil, entry.key .. " auto-switch is missing context " .. ctx.key)
        assert(target == "none" or target == "restore" or PPERF.Presets.presets[target],
            entry.key .. " auto-switch " .. ctx.key .. " targets an unknown preset: " .. tostring(target))
    end
    for key in pairs(plan) do
        assert(key == "enabled" or contextKeys[key],
            entry.key .. " auto-switch names a context that does not exist: " .. key)
    end
end

--------------------------------------------------------------------------------
-- Detection
--------------------------------------------------------------------------------

assert(Modules:Status(Modules.byKey.minimap) == "loaded", "minimap should be loaded")
assert(Modules:Status(Modules.byKey.chat) == "missing", "chat should read as missing")
assert(Modules:IsEnabled(Modules.byKey.minimap) == false, "minimap starts off in this fixture")

--------------------------------------------------------------------------------
-- A full install
--------------------------------------------------------------------------------

Stubs.ResetCounts()
framesCreated = 0
hops = 0

local choices = Installer:NewChoices("standard")
assert(choices.modules.chat == false, "an absent module must not start ticked")
choices.graphicsPreset = "balanced"

local result = Installer:Apply(choices)
local installHops = hops

assert(#result.failures == 0, "install reported failures: " .. table.concat(result.failures, "; "))
assert(#result.skipped == 1 and result.skipped[1] == "Chat", "Chat should be the only skipped module")
assert(#result.applied == 4, "expected four modules configured, got " .. #result.applied)

-- Layout values landed. These are the Standard layout, which is a transcription
-- of a live install rather than a set of round numbers - so they are spot checks
-- on the transcription as much as on the installer.
assert(PUF.Config.units.player.x == -429, "unit frame position not written")
assert(PUF.Config.units.player.y == -395, "unit frame position not written")
assert(PUF.Config.units.player.healthColorMode == "custom", "flat health bars not written")
assert(PUF.Config.units.player.healthColor.r == 0, "health colour not written")
-- Configured but off, so switching it on later puts it in the right place.
assert(PUF.Config.units.focus.enabled == false, "focus should be off in Standard")
assert(PUF.Config.units.focus.x == -600, "focus should still be positioned while off")

assert(PMM.Config.size == 155 and PMM.Config.enabled == true, "minimap not configured")
assert(PMM.Config.widgets.calendar == "hidden", "minimap widget dispositions not written")
assert(PMM.Config.widgetLayout.difficulty.scale == 0.75, "minimap widget layout not written")

assert(PTT.Config.anchorMode == "anchor" and PTT.Config.enabled == true, "tooltip not configured")
assert(PTT.Config.healthBar == false, "tooltip health bar should be off in Standard")

assert(PSB.Config.framePoint == "TOPRIGHT" and PSB.Core.frame.shown == true, "system bars not configured")
assert(PSB.Config.barSpacing == -1, "system bar overlap not written")
assert(PSB.Config.customColors.FPS.g == 0.408, "system bar FPS colour not written")

-- Deep merge kept the siblings the layout said nothing about. bgAlpha and
-- auraSpacing are good probes precisely because no layout mentions them.
assert(PUF.Config.units.player.auraSpacing == 2, "deep merge clobbered a sibling key")
assert(PUF.Config.units.player.bgAlpha == 0.85, "deep merge clobbered a sibling key")

-- Graphics went through PeaversPerformance rather than being set here.
assert(#appliedPresets == 1 and appliedPresets[1] == "balanced", "graphics preset not applied")

--------------------------------------------------------------------------------
-- Auto-switch
--
-- The standard plan came off the layout and was written into
-- PeaversPerformance's own config keys, and Evaluate was forced so that the
-- context the player is standing in right now is acted on rather than waiting
-- for the next loading screen.
--------------------------------------------------------------------------------

assert(PPERF.Config.autoSwitchEnabled == true, "auto-switch was not enabled")
assert(PPERF.Config.autoSwitchRaid == "quality",
    "raid context not written, got " .. tostring(PPERF.Config.autoSwitchRaid))
assert(PPERF.Config.autoSwitchMythicPlus == "performance", "mythic+ context not written")
assert(PPERF.Config.autoSwitchDungeon == "restore", "dungeon context not written")
assert(PPERF.Config.autoSwitchWorld == "restore", "world context not written")
assert(evaluations == 1, "auto-switch should be evaluated once per install, got " .. evaluations)

-- The pack recorded the run.
assert(PUI.Config.installedVersion == PUI.version, "install was not recorded")
assert(PUI.Config.layout == "standard", "layout was not recorded")

-- Nothing was drawn.
assert(framesCreated == 0, framesCreated .. " frames created during an install; expected none")

--------------------------------------------------------------------------------
-- Ordering: the toggle has to run before the layout
--
-- Cinematic switches target-of-target off. Turning unit frames on sets every
-- frame's `enabled` back to true, so if the installer ever applies the layout
-- first and the toggle second, this is the assertion that catches it.
--------------------------------------------------------------------------------

local cinematic = Installer:NewChoices("cinematic")
cinematic.graphicsPreset = "none"
Installer:Apply(cinematic)

assert(PUF.Config.units.targettarget.enabled == false,
    "cinematic left target-of-target on: module toggles must be applied before layout overrides")
assert(PUF.Config.units.player.enabled == true, "cinematic should leave the player frame on")
assert(PMM.Config.visibility == "hover", "cinematic minimap not applied")
assert(#appliedPresets == 1, "graphicsPreset 'none' must not touch the client")

-- "Leave my graphics alone" has to mean alone. The screen was shown (a plan is
-- present) and the baseline came back "none", so an auto-switch plan carried
-- over from the previous install must be switched off rather than left firing.
assert(PPERF.Config.autoSwitchEnabled == false,
    "a 'none' baseline must switch auto-switch off, not leave the old plan running")
assert(evaluations == 1, "a 'none' baseline must not evaluate")

--------------------------------------------------------------------------------
-- Off means off
--
-- An unticked module gets its toggle and none of the layout. The minimap is a
-- good probe: `size` is the value the raid layout would have written.
--------------------------------------------------------------------------------

local partial = Installer:NewChoices("raid")
partial.modules.minimap = false
partial.graphicsPreset = "none"
PMM.Config.size = 999
local partialResult = Installer:Apply(partial)

assert(PMM.Config.enabled == false, "unticking a module must switch it off")
assert(PMM.Config.size == 999, "an unticked module must not receive layout overrides")

-- Reported as switched off, not as configured. A summary that folds the two
-- together is how somebody ends up believing the pack ignored them.
assert(#partialResult.disabled == 1 and partialResult.disabled[1] == "MiniMap",
    "an unticked module must be reported as switched off")
for _, label in ipairs(partialResult.applied) do
    assert(label ~= "MiniMap", "an unticked module must not be reported as configured")
end
assert(PUF.Config.units.player.x == -300, "the raid layout should still have reached unit frames")

--------------------------------------------------------------------------------
-- A layout-only apply does not touch graphics at all
--
-- /pui apply raid, and the Apply buttons on the settings page, never asked the
-- player about graphics - so they pass no plan, and nothing in PeaversPerformance
-- may move. Without this, changing layout would quietly switch off an
-- auto-switch setup somebody configured weeks ago.
--------------------------------------------------------------------------------

PPERF.Config.autoSwitchEnabled = true
PPERF.Config.autoSwitchRaid = "minimum"
local presetsBefore = #appliedPresets
local evaluationsBefore = evaluations

local layoutOnly = Installer:NewChoices("compact")
layoutOnly.graphicsPreset = "none"
layoutOnly.autoSwitch = nil
Installer:Apply(layoutOnly)

assert(PPERF.Config.autoSwitchEnabled == true,
    "a layout-only apply must not switch auto-switch off")
assert(PPERF.Config.autoSwitchRaid == "minimum",
    "a layout-only apply must not rewrite a context")
assert(#appliedPresets == presetsBefore, "a layout-only apply must not apply a preset")
assert(evaluations == evaluationsBefore, "a layout-only apply must not evaluate")
assert(PUF.Config.units.player.x == -210, "the compact layout should still have been applied")

--------------------------------------------------------------------------------
-- Live preview round-trips exactly
--
-- The preview is the one thing in this addon that writes before the player has
-- pressed Install, so the promise it makes - that Undo puts everything back
-- exactly - is the one worth testing hardest.
--
-- The subtle half is absence. Writing `widgets.calendar = "hidden"` over a table
-- that never had a `calendar` key leaves a value behind that a naive restore has
-- no way to know should be gone, and the UI quietly keeps a piece of a layout
-- the player undid. The fixture below starts with an empty `widgets` table on
-- purpose so that a restore which only puts old values back, rather than also
-- removing new ones, fails here.
--------------------------------------------------------------------------------

-- Bookkeeping the fixture and ConfigManager hang off a config, none of it a
-- setting. `saves` in particular changes on every write, so leaving it in would
-- make the comparison fail for the one reason that does not matter.
local NOT_A_SETTING = {
    saves = true, addon = true, defaults = true, dbName = true,
    UNIT_ORDER = true, UNIT_LABELS = true,
}

local function Fingerprint(value, out, path, depth)
    out = out or {}
    path = path or ""
    depth = depth or 0

    if type(value) ~= "table" then
        out[#out + 1] = path .. "=" .. tostring(value)
        return out
    end

    local keys = {}
    for key in pairs(value) do
        if type(value[key]) ~= "function" and not (depth == 0 and NOT_A_SETTING[key]) then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        Fingerprint(value[key], out, path .. "." .. key, depth + 1)
    end
    return out
end

local function Snapshot()
    local out = {}
    local names = { "unitframes", "minimap", "tooltip", "systembars" }
    for index, config in ipairs({ PUF.Config, PMM.Config, PTT.Config, PSB.Config }) do
        Fingerprint(config, out, names[index], 0)
    end
    return out
end

-- The first place two snapshots disagree, named. "did not restore exactly" with
-- no pointer is a miserable thing to debug six months from now.
local function FirstDifference(a, b)
    for index = 1, math.max(#a, #b) do
        if a[index] ~= b[index] then
            return "expected " .. tostring(a[index]) .. ", got " .. tostring(b[index])
        end
    end
    return nil
end

-- Start from a known, non-default state so the restore has something real to put
-- back rather than coincidentally matching the defaults.
PMM.Config.widgets = {}
PMM.Config.size = 199
PMM.Config.visibility = "always"
PTT.Config.anchorMode = "cursor"
PUF.Config.units.player.x = -111
PUF.Config.units.player.healthColorMode = "class"
PSB.Config.barSpacing = 7
Modules:SetEnabled(Modules.byKey.minimap, true)
Modules:SetEnabled(Modules.byKey.tooltip, true)

local before = Snapshot()
assert(PMM.Config.widgets.calendar == nil, "fixture should start with no widget dispositions")

local previewChoices = Installer:NewChoices("standard")
local started, reason = PUI.Preview:Start("standard", previewChoices)
assert(started, "preview did not start: " .. tostring(reason))
assert(PUI.Preview:IsActive(), "preview should be active once started")

-- The layout screen re-applies its selection every time it is drawn, and uses
-- this to avoid reverting and re-applying the same layout for no reason.
assert(PUI.Preview:IsShowing("standard"), "IsShowing should recognise the live layout")
assert(not PUI.Preview:IsShowing("raid"), "IsShowing must not match a different layout")

-- It really applied - a preview that does nothing would pass the restore test.
assert(PMM.Config.size == 155, "preview did not apply the layout")
assert(PMM.Config.widgets.calendar == "hidden", "preview did not write the new sub-table key")
assert(PUF.Config.units.player.x == -429, "preview did not apply unit frames")
assert(PUI.Config.previewRestore ~= nil, "the restore must be on disk before the first write")

assert(PUI.Preview:Revert(), "revert should report success")
assert(not PUI.Preview:IsActive(), "preview should not be active after a revert")
assert(PUI.Config.previewRestore == nil, "the restore must be cleared once used")

assert(PMM.Config.widgets.calendar == nil,
    "revert left a key behind that did not exist before the preview")
local difference = FirstDifference(before, Snapshot())
assert(not difference, "revert did not put every setting back exactly: " .. tostring(difference))

-- Keep is the other exit: it stops tracking without putting anything back.
PUI.Preview:Start("raid", previewChoices)
assert(PUI.Preview:Keep(), "keep should report success")
assert(not PUI.Preview:IsActive(), "keep should end the preview")
assert(PUI.Config.previewRestore == nil, "keep must clear the outstanding restore")
assert(PUF.Config.units.player.x == -300, "keep must leave the previewed layout in place")

--------------------------------------------------------------------------------
-- Re-running the installer gives a clean result
--
-- The reason this exists: an install that only deep-merges the layout leaves
-- every setting the layout does not happen to name exactly as it found it. A
-- font size changed in March, a bisect mode left switched on, a stray key from
-- a version two releases back - all of it survives, and the result looks like
-- the installer half-worked. Which is what happened.
--
-- So the fixture is deliberately messed up first, in three different ways, and
-- the install has to come out clean.
--------------------------------------------------------------------------------

PMM.Config.size = 999                       -- a setting the layout does name
PMM.Config.buttonSpacing = 77               -- one it does not
PMM.Config.strayKeyFromOldVersion = true    -- a key the defaults never had
PTT.Config.scale = 1.6                      -- another the layout does not name
PSB.Config.barAlpha = 0.42                  -- systembars, not named by Standard

local cleanChoices = Installer:NewChoices("standard")
assert(cleanChoices.resetFirst == true,
    "re-running should default to a clean result, not a merge onto old state")
cleanChoices.graphicsPreset = "none"
cleanChoices.autoSwitch = nil
Installer:Apply(cleanChoices)

assert(PMM.Config.size == 155, "the layout should still win over the reset")
assert(PMM.Config.buttonSpacing == 2,
    "a setting the layout does not name must go back to the module default, got "
    .. tostring(PMM.Config.buttonSpacing))
assert(PMM.Config.strayKeyFromOldVersion == nil,
    "a key the module no longer has must not survive a reset")
assert(PTT.Config.scale == 1.0, "tooltip scale should be back at its default")
assert(PSB.Config.barAlpha == 1.0, "system bar alpha should be back at its default, got "
    .. tostring(PSB.Config.barAlpha))

-- And with the box unticked it is a merge again, which is the whole point of it
-- being a box.
PTT.Config.scale = 1.6
local mergeChoices = Installer:NewChoices("standard")
mergeChoices.resetFirst = false
mergeChoices.graphicsPreset = "none"
mergeChoices.autoSwitch = nil
Installer:Apply(mergeChoices)
assert(PTT.Config.scale == 1.0,
    "the standard layout names tooltip scale, so it is written either way")
PTT.Config.fontSize = 21
Installer:Apply(mergeChoices)
assert(PTT.Config.fontSize == 12,
    "standard names fontSize too")
-- cursorOffsetX is a good probe precisely because the Standard layout has no
-- opinion about it: it parks tooltips, so the cursor offsets never come up.
PTT.Config.cursorOffsetX = 19
Installer:Apply(mergeChoices)
assert(PTT.Config.cursorOffsetX == 19,
    "without a reset, a setting the layout does not name must be left alone")

-- Switching a module off must not wipe it. Turning something off means stop
-- drawing it, not throw away how it was set up.
local offChoices = Installer:NewChoices("standard")
offChoices.modules.tooltip = false
offChoices.graphicsPreset = "none"
offChoices.autoSwitch = nil
PTT.Config.cursorOffsetX = 19
Installer:Apply(offChoices)
assert(PTT.Config.cursorOffsetX == 19,
    "a module being switched off must not be reset out from under the player")

--------------------------------------------------------------------------------
-- A module that will override the layout says so
--
-- PeaversChat has bisect modes that take features away and stash the real
-- settings in a backup table. A layout written underneath one is written and
-- then immediately overridden, which from the outside is indistinguishable from
-- the installer not working - and that is exactly what it looked like the first
-- time it happened. The install must name it rather than report success.
--------------------------------------------------------------------------------

local chatModule = Modules.byKey.chat

-- The fixture leaves PeaversChat absent everywhere else, so it is introduced
-- here and withdrawn again afterwards.
local PCHAT = { Config = FakeConfig({
    enabled = true, withoutBackup = {}, minimalBackup = {},
}) }
function PCHAT.Config:Save() Hop() return true end
_G.PeaversChat = PCHAT

assert(Modules:Warn(chatModule) == nil, "a healthy module should have nothing to warn about")

PCHAT.Config.withoutBackup = { showSocialButton = false }
local warning = Modules:Warn(chatModule)
assert(warning and warning:find("without"), "a withdrawn module must be reported: " .. tostring(warning))

PCHAT.Config.withoutBackup = {}
PCHAT.Config.minimalBackup = { styleTabs = true }
warning = Modules:Warn(chatModule)
assert(warning and warning:find("minimal"), "minimal mode must be reported: " .. tostring(warning))

-- It has to reach the install result, not just the helper - but only on the
-- merge path. A reset clears the backup along with everything else, which is
-- the whole reason a clean re-run fixes this rather than reporting it.
PCHAT.Config.minimalBackup = {}
PCHAT.Config.withoutBackup = { showSocialButton = false }

local mergeWarn = Installer:NewChoices("standard")
mergeWarn.resetFirst = false
mergeWarn.graphicsPreset = "none"
mergeWarn.autoSwitch = nil
local warnResult = Installer:Apply(mergeWarn)
assert(#warnResult.warnings == 1 and warnResult.warnings[1]:find("Chat is in"),
    "merging under a bisect mode must be reported")
assert(#warnResult.failures == 0, "a bisect mode is not a failure")

-- Now the clean path: the same mess, reset on, and it simply goes away.
PCHAT.Config.withoutBackup = { showSocialButton = false }
local cleanWarn = Installer:NewChoices("standard")
cleanWarn.graphicsPreset = "none"
cleanWarn.autoSwitch = nil
local cleanResult = Installer:Apply(cleanWarn)
assert(next(PCHAT.Config.withoutBackup) == nil,
    "a reset must clear the bisect backup")
assert(#cleanResult.warnings == 0,
    "nothing left to warn about once the module has been reset")

_G.PeaversChat = nil

--------------------------------------------------------------------------------
-- The extras list is coherent
--
-- Pure data that a person edits by hand, which is exactly the kind of file that
-- rots: a duplicate key silently shadows an entry, a category typo makes one
-- vanish from the page with no error, and a profile block with a string but no
-- instructions gives somebody a blob and no idea what to do with it.
--
-- None of that throws in game. It just quietly renders wrong.
--------------------------------------------------------------------------------

local Extras = PUI.Extras
local seenKeys = {}
local validCategory = {}
for _, category in ipairs(Extras.categories) do
    validCategory[category] = true
    assert(Extras.categoryNames[category],
        "category '" .. category .. "' has no display name")
end

local extrasChecked, withProfiles = 0, 0

for _, entry in ipairs(Extras.list) do
    extrasChecked = extrasChecked + 1
    local where = "extras entry '" .. tostring(entry.key) .. "'"

    assert(entry.key and entry.key ~= "", "an extras entry has no key")
    assert(not seenKeys[entry.key], "duplicate extras key: " .. tostring(entry.key))
    seenKeys[entry.key] = true

    assert(entry.name and entry.name ~= "", where .. " has no name")
    assert(entry.blurb and entry.blurb ~= "", where .. " has no blurb")
    assert(entry.why and entry.why ~= "", where .. " has no reason to be listed")

    assert(validCategory[entry.category],
        where .. " is in an unknown category: " .. tostring(entry.category))

    assert(type(entry.folders) == "table" and #entry.folders > 0,
        where .. " names no addon folder, so it can never be detected")
    for _, folder in ipairs(entry.folders) do
        assert(type(folder) == "string" and folder ~= "",
            where .. " has a bad folder name")
    end

    -- A url is optional on purpose - an invented CurseForge slug 404s, which is
    -- worse than no link - but a present one has to look like one.
    if entry.url then
        assert(entry.url:match("^https://"), where .. " has a url that is not https")
    end

    if entry.profile then
        assert(entry.profile.how and entry.profile.how ~= "",
            where .. " has a profile block with no import instructions")
        if Extras:HasProfile(entry) then
            withProfiles = withProfiles + 1
        end
    end
end

-- Every entry has to be reachable from the page, which walks categories rather
-- than the flat list. An entry in a category the page never renders is invisible.
local reachable = 0
for _, category in ipairs(Extras.categories) do
    reachable = reachable + #Extras:OfCategory(category)
end
assert(reachable == extrasChecked,
    "some extras entries are not reachable through the categories the page walks")

--------------------------------------------------------------------------------
-- Idle
--
-- The pack installs no OnUpdate on anything. Every frame it could have made is
-- counted above and the count is zero, so there is nothing to tick - but the
-- scenario is reported rather than argued, so that the day somebody adds a
-- ticker the number stops being zero and the build goes red.
--------------------------------------------------------------------------------

Stubs.ResetCounts()
local idle = Stubs.Drive(function() end, 144, 1 / 144)

return {
    {
        name = "installing the pack, four modules and a graphics preset",
        callsPerFrame = 0,
        idleCallsPerSecond = 0,
        notes = installHops .. " calls into the module addons for the whole install, " ..
                "0 frames created; happens once",
    },
    {
        name = "idle, after installing",
        callsPerFrame = idle,
        idleCallsPerSecond = 0,
        notes = "no OnUpdate, no ticker, no combat events: the pack does nothing " ..
                "at all once the installer has closed",
    },
    {
        name = "layout data checked against the module settings",
        callsPerFrame = 0,
        idleCallsPerSecond = 0,
        notes = layoutsChecked .. " layouts, " .. keysChecked ..
                " module blocks verified key by key",
    },
    {
        name = "extras list checked",
        callsPerFrame = 0,
        idleCallsPerSecond = 0,
        notes = extrasChecked .. " recommended addons, " .. withProfiles ..
                " with a shared profile string",
    },
    {
        name = "live preview applied and undone",
        callsPerFrame = 0,
        idleCallsPerSecond = 0,
        notes = "every setting restored exactly, including keys the layout " ..
                "created that did not exist before",
    },
}
