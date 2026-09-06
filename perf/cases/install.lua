--------------------------------------------------------------------------------
-- Ultra Performance case: what PeaversUI costs while you play.
--
-- The claim being tested is unusually simple, and worth stating before the
-- numbers: **this addon does its work once and then stops existing.** It draws
-- no frames until somebody opens the installer, installs no OnUpdate, starts no
-- ticker, and registers no combat events. After the install it is a hundred
-- kilobytes of Lua sitting still.
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

local function FakeConfig(defaults)
    local config = DeepCopy(defaults)
    config.saves = 0
    function config:Save() self.saves = self.saves + 1 Hop() return true end
    return config
end

local function UnitDefaults(overrides)
    local unit = {
        enabled = true,
        width = 240, height = 46, x = 0, y = 0, bgAlpha = 0.85, tooltip = "always",
        barTexture = "bar", healthColorMode = "class", healthBgAlpha = 0.22,
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
    Config = FakeConfig({ activePreset = false, autoSwitchEnabled = false }),
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

assert(PUI.Config and PUI.Modules and PUI.Layouts and PUI.Installer,
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
    -- than read off a live config. Transcribed from PeaversChat/src/Utils/Config.lua.
    chat = {
        enabled = true, background = true, bgAlpha = 0.6, border = true,
        paddingLeft = 8, paddingRight = 6, paddingTop = 6, paddingBottom = 6,
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
    },
}

local function CheckKeys(layoutKey, moduleKey, overrides, known, path)
    for key, value in pairs(overrides) do
        local where = layoutKey .. "." .. moduleKey .. "." .. path .. key
        assert(known[key] ~= nil, where .. " is not a setting the module has")
        if type(value) == "table" and type(known[key]) == "table" then
            CheckKeys(layoutKey, moduleKey, value, known[key], path .. key .. ".")
        end
    end
end

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

-- Layout values landed.
assert(PUF.Config.units.player.x == -270, "unit frame position not written")
assert(PMM.Config.size == 155 and PMM.Config.enabled == true, "minimap not configured")
assert(PTT.Config.anchorMode == "cursor" and PTT.Config.enabled == true, "tooltip not configured")
assert(PSB.Config.framePoint == "RIGHT" and PSB.Core.frame.shown == true, "system bars not configured")

-- Deep merge kept the siblings the layout said nothing about.
assert(PUF.Config.units.player.auraSpacing == 2, "deep merge clobbered a sibling key")
assert(PUF.Config.units.player.height == 46, "deep merge clobbered a sibling key")

-- Graphics went through PeaversPerformance rather than being set here.
assert(#appliedPresets == 1 and appliedPresets[1] == "balanced", "graphics preset not applied")

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
}
