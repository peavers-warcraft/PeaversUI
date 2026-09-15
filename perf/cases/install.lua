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

-- PeaversScaler, with the one piece of state that matters most: the `original`
-- snapshot its Enable records before the first write, and Disable restores.
-- The fixture's Reset mirrors the real flat ConfigManager and drops that key, so
-- a pack that resets the scaler without carrying it across fails below.
local PSC = {
    Config = FakeConfig({
        enabled = false, scaleMode = "pixelPerfect", scale = 1.0, ppMultiplier = 0,
        debugMode = false,
    }),
    Scaler = { applied = 0, restored = 0 },
}
function PSC.Scaler:Enable()
    Hop()
    if not PSC.Config.original then
        PSC.Config.original = { useUiScale = "1", uiScale = "0.65" }
    end
    PSC.Config.enabled = true
    self.applied = self.applied + 1
end
function PSC.Scaler:Disable()
    Hop()
    -- The real Disable has no original to hand back when it was never enabled,
    -- and approximates a scale instead. The pack must never ask for that.
    assert(PSC.Config.original, "Scaler:Disable called with nothing to restore")
    PSC.Config.enabled = false
    self.restored = self.restored + 1
end
function PSC.Scaler:Apply()
    Hop()
    if PSC.Config.enabled then self.applied = self.applied + 1 end
end
_G.PeaversScaler = PSC
_G.PeaversCommons.ConfigRegistry:Register({ name = "PeaversScaler", addonRef = PSC })

-- PeaversCastBar. Per-unit settings under `units`, like the unit frames, and a
-- Blizzard:Apply that reads the config table it is handed rather than a global -
-- so the pack has to pass it explicitly, and this refuses anything else.
local function CastUnitDefaults(overrides)
    local unit = {
        enabled = false, width = 220, height = 24,
        matchCooldownManager = false, anchorToCooldownManager = false,
        cooldownManagerFrame = "EssentialCooldownViewer",
        anchorSide = "BOTTOM", anchorGap = 6,
        showIcon = true, iconSide = "LEFT", showSpellName = true, showCastTime = true,
        framePoint = "CENTER", frameRelativePoint = "CENTER",
        frameX = 0, frameY = -180,
        hideBlizzard = true,
    }
    for key, value in pairs(overrides or {}) do unit[key] = value end
    return unit
end

local PCB = {
    Config = FakeConfig({
        fontSize = 11, barBgAlpha = 0.6, borderAlpha = 1, frameStrata = "MEDIUM",
        showSpark = true, showLatency = true,
        units = {
            player = CastUnitDefaults({ enabled = true }),
            target = CastUnitDefaults({ enabled = true, frameY = 200, width = 200, height = 22 }),
            focus  = CastUnitDefaults({ frameX = -320, frameY = 120, width = 180, height = 20 }),
            pet    = CastUnitDefaults({ frameY = -240, width = 160, height = 16, showCastTime = false }),
        },
    }),
    Units = { { key = "player" }, { key = "target" }, { key = "focus" }, { key = "pet" } },
    Core = {},
    Blizzard = { applied = 0 },
}
function PCB.Config:GetUnit(key) return self.units[key] end
function PCB.Core:ApplyConfig() Hop() end
function PCB.Blizzard:Apply(config)
    Hop()
    assert(type(config) == "table" and type(config.GetUnit) == "function",
        "Blizzard:Apply must be handed the config table, got " .. tostring(config))
    self.applied = self.applied + 1
end
_G.PeaversCastBar = PCB
_G.PeaversCommons.ConfigRegistry:Register({ name = "PeaversCastBar", addonRef = PCB })

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
Load("Core/Versioning.lua")
Load("Core/Extras.lua")
Load("Core/Harvest.lua")

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
    scaler = PSC.Config,
    castbar = PCB.Config,
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
-- System bars are docked to the minimap in every layout
--
-- The bars sit flush against the minimap's inner edge and overhang it by the
-- same two pixels in every layout, so the corner reads as one block whichever
-- card was clicked. The positions are derived rather than typed, and this is
-- what keeps it that way: a layout that gains a hand-written frameY, or a
-- minimap block that stops naming an offset the derivation relies on, fails
-- here instead of drifting apart on somebody's screen.
--------------------------------------------------------------------------------

for _, entry in ipairs(Layouts:Sorted()) do
    local map = entry.layout.overrides.minimap
    local bars = entry.layout.overrides.systembars
    assert(map and bars, entry.key .. " must configure both the minimap and the system bars")

    for _, key in ipairs({ "anchor", "size", "scale", "offsetX", "offsetY" }) do
        assert(map[key] ~= nil, entry.key .. ".minimap must name " .. key ..
            " - the bars are docked from it, and a value left to whatever the player had would move them")
    end

    local edge = map.size * map.scale
    assert(bars.framePoint == map.anchor,
        entry.key .. " system bars are not anchored to the minimap's corner")
    assert(bars.frameX == -map.offsetX * map.scale, entry.key .. " system bars are not aligned with the minimap")
    assert(bars.frameY == -(map.offsetY * map.scale + edge),
        entry.key .. " system bars are not directly under the minimap, got frameY " .. tostring(bars.frameY))
    assert(bars.frameWidth == edge + 2, entry.key .. " system bars are not the minimap's width")
    assert(bars.lockPosition == true, entry.key .. " system bars should be locked in place")
end

-- The chat style is the author's and is the same in every layout: plain
-- mixed-case tabs with no underline, and channel names left as Blizzard prints
-- them. A layout that stays quiet about these gets PeaversChat's own defaults
-- after the reset - capitals and an accent rule - which is the old look.
for _, entry in ipairs(Layouts:Sorted()) do
    local chat = entry.layout.overrides.chat
    assert(chat, entry.key .. " must configure chat")
    assert(chat.tabUppercase == false, entry.key .. " chat tabs should not be uppercase")
    assert(chat.tabUnderline == false, entry.key .. " chat tabs should not be underlined")
    assert(chat.shortChannelNames == false, entry.key .. " should leave channel names unabbreviated")
    assert(chat.shortChannelNamesWithdrawn == nil,
        entry.key .. " must not write PeaversChat's one-time migration flag")
    assert(chat.bgColor and chat.bgColor.r == 0 and chat.bgColor.g == 0 and chat.bgColor.b == 0,
        entry.key .. " chat should be painted the same flat black as the unit frames")
end

-- The transcription still holds: Standard derives to exactly what was on screen.
local standardBars = Layouts:Get("standard").overrides.systembars
assert(standardBars.framePoint == "TOPRIGHT" and standardBars.frameX == 0
    and standardBars.frameY == -155 and standardBars.frameWidth == 157,
    "docking moved the Standard system bars away from the transcribed position")

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
assert(#result.applied == 6, "expected six modules configured, got " .. #result.applied)

-- The canvas went on with the layout. Enable is what records the player's own
-- scale, so it has to have run - and before the reset could discard anything.
assert(PSC.Config.enabled == true, "the scaler should be switched on by an install")
assert(PSC.Config.scaleMode == "1440p",
    "the layout should pin the 1440p canvas, got " .. tostring(PSC.Config.scaleMode))
assert(PSC.Config.original and PSC.Config.original.uiScale == "0.65",
    "the player's original scale must be recorded and survive the install's reset")
assert(PSC.Scaler.applied >= 1, "the scale was never applied")

-- The cast bars went on too, and Blizzard:Apply was handed the config table
-- rather than the owning table - which the stand-in asserts on every call.
assert(PCB.Config.units.player.enabled == true, "the player cast bar should be on after an install")
assert(PCB.Config.units.player.anchorToCooldownManager == true,
    "Standard anchors the player cast bar to the Cooldown Manager")
assert(PCB.Config.units.pet.enabled == false, "Standard leaves the pet cast bar off")
assert(PCB.Blizzard.applied >= 1, "the cast bars never handed Blizzard's own over")

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
-- The scaler
--
-- The one module whose settings include a record of the player's UI from before
-- the pack arrived. Four ways to lose or misuse it, each checked.
--------------------------------------------------------------------------------

local scalerModule = Modules.byKey.scaler

-- 1. A clean re-run resets the scaler but keeps the recorded original. The
--    flat ConfigManager Reset drops every key its defaults do not name, and
--    `original` is one; without the carry, /pscaler restore would restore nothing.
PSC.Config.original = { useUiScale = "1", uiScale = "0.9" }
PSC.Config.strayScalerKey = true
local scalerClean = Installer:NewChoices("standard")
scalerClean.graphicsPreset = "none"
scalerClean.autoSwitch = nil
Installer:Apply(scalerClean)
assert(PSC.Config.original and PSC.Config.original.uiScale == "0.9",
    "resetting the scaler threw away the player's original scale")
assert(PSC.Config.strayScalerKey == nil, "the scaler reset should still clear stray keys")
assert(PSC.Config.scaleMode == "1440p", "the canvas should be back on after the reset")

-- 2. Unticking a scaler that was never on does not call Disable. With nothing
--    recorded, the real Disable approximates a scale of its own, which would
--    change the UI of somebody who only unticked a box. The fixture's Disable
--    asserts on exactly that.
PSC.Config.enabled = false
PSC.Config.original = nil
local noScaler = Installer:NewChoices("standard")
noScaler.modules.scaler = false
noScaler.graphicsPreset = "none"
noScaler.autoSwitch = nil
local noScalerResult = Installer:Apply(noScaler)
assert(#noScalerResult.failures == 0,
    "unticking an unused scaler failed: " .. table.concat(noScalerResult.failures, "; "))
assert(PSC.Config.enabled == false and PSC.Config.original == nil,
    "unticking an unused scaler must leave it exactly as it was")

-- 3. A preview on a UI that was never scaled undoes cleanly: the scaler goes
--    back off through Disable (which restores the scale Enable recorded), and
--    the mode it was in comes back.
PSC.Config.scaleMode = "pixelPerfect"
local restoredBefore = PSC.Scaler.restored
assert(PUI.Preview:Start("standard", Installer:NewChoices("standard")), "scaler preview did not start")
assert(PSC.Config.enabled == true and PSC.Config.scaleMode == "1440p", "preview did not apply the canvas")
assert(PSC.Config.original ~= nil, "preview must record the original scale before changing it")
PUI.Preview:Revert()
assert(PSC.Config.enabled == false, "undoing a preview must switch the scaler back off")
assert(PSC.Config.scaleMode == "pixelPerfect", "undoing a preview must put the scale mode back")
assert(PSC.Scaler.restored == restoredBefore + 1, "undoing a preview must hand the original scale back")
assert(Modules:IsEnabled(scalerModule) == false, "scaler should read as off after the undo")

-- 4. Every layout fits its canvas. 1440 units tall, and 2304 wide on the
--    narrowest common screen (16:10); a frame whose edge is past either is off
--    screen for somebody, which is the bug the canvas exists to fix.
local HALF_HEIGHT, HALF_WIDTH = 720, 1152
for _, entry in ipairs(Layouts:Sorted()) do
    assert(entry.layout.overrides.scaler.scaleMode == Layouts.CANVAS,
        entry.key .. " must pin the " .. Layouts.CANVAS .. " canvas its positions were drawn on")
    for unitKey, unit in pairs(entry.layout.overrides.unitframes.units) do
        if unit.x and unit.y then
            local w, h = unit.width or 240, unit.height or 46
            assert(math.abs(unit.y) + h / 2 <= HALF_HEIGHT,
                entry.key .. "." .. unitKey .. " runs off the top or bottom of the canvas")
            assert(math.abs(unit.x) + w / 2 <= HALF_WIDTH,
                entry.key .. "." .. unitKey .. " runs off the side of a 16:10 canvas")
        end
    end
end

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
-- Versioning: nobody's interface changes unless they asked
--
-- The pack's promise to people already using it. Every path by which a newer
-- layout could reach somebody's screen is driven here, and every one of them
-- has to need an explicit choice.
--------------------------------------------------------------------------------

local Versioning = PUI.Versioning

-- Every layout has a revision, and a sentence saying what that revision changed.
for _, entry in ipairs(Layouts:Sorted()) do
    local revision = entry.layout.revision
    assert(type(revision) == "number" and revision >= 1, entry.key .. " has no revision")
    assert(Layouts:ChangesFor(entry.key, revision),
        entry.key .. " revision " .. revision .. " has no changelog line")
end

-- Detecting a setup of the player's own, in both storage shapes.
local freshModule = { key = "fresh", folder = "PeaversFresh", role = "display" }
_G.PeaversFresh = { Config = FakeConfig({ size = 10, shortChannelNamesWithdrawn = false }) }
assert(not Modules:HasCustomSettings(freshModule), "a module at its defaults is not a setup of the player's own")
_G.PeaversFresh.Config.shortChannelNamesWithdrawn = true
assert(not Modules:HasCustomSettings(freshModule), "a module's own one-time migration is not the player's choice")
-- PeaversChat's padding split, exactly as it lands on a brand-new install.
_G.PeaversFresh = { Config = FakeConfig({ padding = 6, paddingSplit = false,
    paddingLeft = 8, paddingRight = 6, paddingTop = 6, paddingBottom = 6 }) }
_G.PeaversFresh.Config.paddingSplit = true
_G.PeaversFresh.Config.paddingLeft = 6
assert(not Modules:HasCustomSettings(freshModule), "PeaversChat's padding migration is not the player's choice")
_G.PeaversFresh.Config.paddingLeft = 9
assert(Modules:HasCustomSettings(freshModule), "a padding the player chose is theirs")
_G.PeaversFresh = { Config = FakeConfig({ size = 10, shortChannelNamesWithdrawn = true }) }
_G.PeaversFresh.Config.size = 11
assert(Modules:HasCustomSettings(freshModule), "a changed setting is a setup of the player's own")
local aceShaped = { Config = { db = { sv = { profiles = { P = {} } }, keys = { profile = "P" } } } }
_G.PeaversFresh = aceShaped
assert(not Modules:HasCustomSettings(freshModule), "an empty AceDB profile is not a setup")
aceShaped.Config.db.sv.profiles.P.width = 300
assert(Modules:HasCustomSettings(freshModule), "anything stored in an AceDB profile is a setup")
_G.PeaversFresh = nil
assert(Modules:HasExistingSetup(), "after the installs above, the fixture holds a setup of its own")

-- Keeping the current setup writes nothing: no reset even with the box ticked,
-- no toggle re-run, no graphics.
PUF.Config.units.targettarget.enabled = false
PPERF.Config.autoSwitchEnabled = true
PPERF.Config.autoSwitchRaid = "minimum"
local keptBefore = Snapshot()
local keep = Versioning:ChoicesFor(Layouts.CURRENT)
keep.existing = true
keep.resetFirst = true
keep.graphicsPreset = "none"
keep.autoSwitch = Layouts:AutoSwitchFor(Layouts.CURRENT)
local keepResult = Installer:Apply(keep)
assert(#keepResult.failures == 0, "keeping the current setup failed: " .. table.concat(keepResult.failures, "; "))
local keptDifference = FirstDifference(keptBefore, Snapshot())
assert(not keptDifference, "keeping the current setup changed a setting: " .. tostring(keptDifference))
assert(PUF.Config.units.targettarget.enabled == false,
    "keeping the current setup switched back on a frame the player had turned off")
assert(PPERF.Config.autoSwitchEnabled == true and PPERF.Config.autoSwitchRaid == "minimum",
    "keeping the current setup touched graphics nobody asked about")
assert(PUI.Config.layout == Layouts.CURRENT and PUI.Config.layoutRevision == nil,
    "a kept setup is recorded as such, with no layout revision")

-- An existing player who picks a layout but never touches the graphics screen
-- keeps their graphics, and keeps a frame the layout says nothing about.
local picked = Installer:NewChoices("raid")
picked.existing = true
picked.resetFirst = false
picked.graphicsPreset = "none"
Installer:Apply(picked)
assert(PPERF.Config.autoSwitchEnabled == true and PPERF.Config.autoSwitchRaid == "minimum",
    "an existing player's graphics changed without the graphics screen being touched")
assert(PUF.Config.units.player.x == -300, "the picked layout should still apply")

-- The wizard's answer is recorded; applying a layout any other way leaves it.
local tracked = Installer:NewChoices("standard")
tracked.graphicsPreset = "none"
tracked.autoSwitch = nil
tracked.track = Versioning.LATEST
Installer:Apply(tracked)
assert(PUI.Config.layout == "standard" and PUI.Config.layoutRevision == Layouts:Get("standard").revision,
    "an install must record the revision it applied")
assert(PUI.Config.track == Versioning.LATEST, "the wizard's track choice must be recorded")
Installer:Apply(Versioning:ChoicesFor("compact"))
assert(PUI.Config.layout == "compact" and PUI.Config.track == Versioning.LATEST,
    "applying a layout outside the wizard must not change the track")

-- A preview is not an install.
PUI.Config.layoutRevision = 1
assert(PUI.Preview:Start("raid", Installer:NewChoices("raid")), "preview did not start")
assert(PUI.Config.layout == "compact" and PUI.Config.layoutRevision == 1,
    "a preview must not record itself as the installed layout")
PUI.Preview:Revert()

-- An install from before revisions: pinned to revision 1, told once.
PUI.Config.installedVersion = "1.0.4"
PUI.Config.layout = "standard"
PUI.Config.layoutRevision = nil
PUI.Config.track = nil
PUI.Config.versioningNoticeShown = nil
assert(Versioning:Migrate(), "an install from before revisions should be migrated")
assert(PUI.Config.layoutRevision == 1 and PUI.Config.track == Versioning.PINNED,
    "an old install must be pinned to revision 1")
assert(Versioning:NoticeDue(), "a migrated install should be told about pinning")
Versioning:ShowNotice()
assert(not Versioning:NoticeDue(), "the notice is shown once")
assert(not Versioning:Migrate(), "migration runs once")

-- Pinned and behind: never updated.
assert(Versioning:Status().behind, "revision 1 of standard should read as behind")
assert(not Versioning:UpdateDue(), "a pinned account must never be updated")

-- Following the latest: the whole layout comes back, never in combat, with an
-- undo that puts the player's own values back and pins them.
PUF.Config.units.player.x = -111
PTT.Config.fontSize = 21
PUF.Config.units.targettarget.enabled = false
Versioning:SetTrack(Versioning.LATEST)
assert(Versioning:UpdateDue(), "a following account that is behind is due an update")

_G.InCombatLockdown = function() return true end
assert(not Versioning:ApplyLatest(), "an update must not apply in combat")
assert(PUF.Config.units.player.x == -111, "a refused update must change nothing")
_G.InCombatLockdown = function() return false end

assert(Versioning:ApplyLatest(), "the update should apply")
assert(PUF.Config.units.player.x == -429 and PTT.Config.fontSize == 12,
    "the update should re-apply the whole layout")
-- Standard names target-of-target as on, and following the latest means taking
-- the whole layout - so it is on now, and the undo has to be able to say so.
assert(PUF.Config.units.targettarget.enabled == true,
    "the update should apply every setting the layout names, frame toggles included")
assert(PUI.Config.layoutRevision == Layouts:Get("standard").revision, "the update should record its revision")
assert(PUI.Config.updateRestore, "an update must leave its undo on disk")
assert(not PUI.Preview:IsActive(), "an update is not a preview: closing the installer must not undo it")
assert(not Versioning:UpdateDue(), "an updated account is no longer due")

assert(Versioning:Undo(), "the update should undo")
assert(PUF.Config.units.player.x == -111 and PTT.Config.fontSize == 21,
    "undo must put the player's own settings back")
assert(PUF.Config.units.targettarget.enabled == false,
    "undo must switch off again a frame the update switched on")
assert(PUI.Config.track == Versioning.PINNED and PUI.Config.layoutRevision == 1,
    "undo must pin the player back to the revision they had")
assert(PUI.Config.updateRestore == nil, "the undo is used up")
assert(not Versioning:UpdateDue(), "an undone update must not come straight back")

-- Choosing to follow catches up at once, because the choice was just made.
assert(Versioning:Follow(), "following should catch up straight away")
assert(PUI.Config.track == Versioning.LATEST and PUF.Config.units.player.x == -429,
    "following should apply the latest revision")

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
local reachable, offered = 0, 0
for _, category in ipairs(Extras.categories) do
    reachable = reachable + #Extras:OfCategory(category)
end
for _, entry in ipairs(Extras.list) do
    if Extras:ForClient(entry) then offered = offered + 1 end
    for clientKey in pairs(entry.clients or {}) do
        assert(Extras.clientKeys[clientKey],
            "extras entry '" .. entry.key .. "' names an unknown client '" .. tostring(clientKey) .. "'")
    end
end
assert(reachable == offered,
    "some extras entries offered on this client are not reachable through the categories the page walks")

--------------------------------------------------------------------------------
-- The pack on the Classic clients
--
-- Only what the pack itself decides per client: whether a timed-dungeon context
-- exists and what it is called, which plan a layout builds, and which
-- recommendations are offered. The modules' own Classic behaviour is theirs to
-- test. PeaversPerformance's context list is swapped per client the way the real
-- addon builds it, and the client is detected from a stubbed build number.
--------------------------------------------------------------------------------

local realGetBuildInfo = _G.GetBuildInfo
local realContexts = PPERF.AutoSwitch.contexts

local function AsClient(interface, contexts)
    _G.GetBuildInfo = function() return "0.0.0", "1", "", interface end
    Modules:DetectClient()
    PPERF.AutoSwitch.contexts = contexts
end

local function SummaryLine(choices)
    for _, line in ipairs(Installer:Preview(choices)) do
        if line.label == "Auto-switch" then return line.detail end
    end
end

-- Classic Era: no timed dungeons, no retail-only recommendations.
AsClient(11509, {
    { key = "raid",    name = "Raid",       configKey = "autoSwitchRaid" },
    { key = "dungeon", name = "Dungeon",    configKey = "autoSwitchDungeon" },
    { key = "world",   name = "Open world", configKey = "autoSwitchWorld" },
})
assert(Modules.client.key == "era", "11509 should read as Classic Era, got " .. tostring(Modules.client.key))

local eraPlan = Layouts:AutoSwitchFor("standard")
assert(eraPlan.mythicplus == nil, "an Era plan must not carry a Mythic+ context")
assert(eraPlan.raid == "quality" and eraPlan.enabled == true, "the Era plan should still come from the layout")
assert(not Installer:InstancePhrase():find("key", 1, true), "Era wording must not mention keys")
for _, key in ipairs({ "warpdeplete", "raiderio", "cooldownmanagercentered" }) do
    assert(not Extras:ForClient(Extras.byKey[key]), key .. " should not be offered on Classic Era")
end
assert(Extras:ForClient(Extras.byKey.details), "an unrestricted entry is offered on every client")

PPERF.Config.autoSwitchMythicPlus = "untouched"
local eraChoices = Installer:NewChoices("standard")
eraChoices.graphicsPreset = "balanced"
local eraSummary = SummaryLine(eraChoices)
assert(eraSummary and not eraSummary:find("M+", 1, true), "the Era summary must not mention M+: " .. tostring(eraSummary))
Installer:Apply(eraChoices)
assert(PPERF.Config.autoSwitchMythicPlus == "untouched", "an Era install must not write a Mythic+ context")

-- Mists Classic: the timed context is Challenge Mode, named by its own label.
AsClient(50504, {
    { key = "raid",       name = "Raid",           configKey = "autoSwitchRaid" },
    { key = "mythicplus", name = "Challenge Mode", short = "CM", configKey = "autoSwitchMythicPlus" },
    { key = "dungeon",    name = "Dungeon",        configKey = "autoSwitchDungeon" },
    { key = "world",      name = "Open world",     configKey = "autoSwitchWorld" },
})
assert(Modules.client.key == "mists", "50504 should read as Mists Classic")
assert(Installer:InstancePhrase():find("Challenge Mode", 1, true), "Mists wording should name Challenge Mode")
local mistsChoices = Installer:NewChoices("standard")
mistsChoices.graphicsPreset = "balanced"
local mistsSummary = SummaryLine(mistsChoices)
assert(mistsSummary and mistsSummary:find("CM", 1, true) and not mistsSummary:find("M+", 1, true),
    "the Mists summary should use Challenge Mode's own short label: " .. tostring(mistsSummary))

-- Without PeaversPerformance the fallback list follows the same rule.
local registry = _G.PeaversCommons.ConfigRegistry
local realGetAddon = registry.GetAddon
local realPerformance = _G.PeaversPerformance
registry.GetAddon = function(self, name)
    if name == "PeaversPerformance" then return nil end
    return realGetAddon(self, name)
end
_G.PeaversPerformance = nil

local mistsFallback = {}
for _, ctx in ipairs(Installer:AutoSwitchContexts()) do mistsFallback[ctx.key] = ctx end
assert(mistsFallback.mythicplus and mistsFallback.mythicplus.name == "Challenge Mode",
    "the Mists fallback should offer Challenge Mode")
AsClient(20506, realContexts)
assert(Modules.client.key == "anniversary", "20506 should read as Anniversary")
for _, ctx in ipairs(Installer:AutoSwitchContexts()) do
    assert(ctx.key ~= "mythicplus", "the Anniversary fallback must not offer a timed-dungeon context")
end

registry.GetAddon = realGetAddon
_G.PeaversPerformance = realPerformance

-- PeaversCommons.Compat, where present, wins over the build number.
_G.PeaversCommons.Compat = { interface = 50504, isClassic = true,
    isClassicEra = false, isAnniversary = false, isMists = true }
_G.GetBuildInfo = function() return "0.0.0", "1", "", 11509 end
Modules:DetectClient()
assert(Modules.client.key == "mists", "Compat should decide the client when it is there")
_G.PeaversCommons.Compat = nil

-- Back to retail for everything below.
_G.GetBuildInfo = realGetBuildInfo
PPERF.AutoSwitch.contexts = realContexts
Modules:DetectClient()
assert(Modules.client.key == "retail", "the fixture should read as retail again")

--------------------------------------------------------------------------------
-- Capturing profiles from third-party addons
--
-- Every string offered on the More stuff page comes from that addon's own
-- export function, so it is correct by construction and in the format its own
-- import expects. What has to be got right here is the guarding: an addon that
-- is absent, has moved its API, throws, or politely returns an empty string must
-- be skipped with a reason rather than storing a Copy button that hands somebody
-- nothing.
--------------------------------------------------------------------------------

local Harvest = PUI.Harvest
PUI.Config.shared = {}

local REAL = string.rep("aXbYcZ", 40)

-- Nothing installed: everything skipped, nothing stored, no button offered.
local nothing = Harvest:CaptureAll()
assert(#nothing.captured == 0, "nothing is installed, so nothing should be captured")
assert(#nothing.skipped > 0, "absent addons should be reported, not silently ignored")
assert(next(PUI.Config.shared) == nil, "nothing should have been stored")

-- The three failure shapes, one per source, plus one that works.
_G.DandersFrames_Export = function() return REAL end
_G.Details = { ExportCurrentProfile = function() return "" end }
_G.PlaterAPI = {
    GetCurrentProfileKey = function() return "Default" end,
    ExportProfile = function() error("boom") end,
}

local mixed = Harvest:CaptureAll()
assert(PUI.Config.shared.dandersframes == REAL, "a working exporter should be stored")
assert(PUI.Config.shared.details == nil, "an empty string is not a profile")
assert(PUI.Config.shared.plater == nil, "an exporter that throws must not store anything")
assert(#mixed.captured == 1, "expected one capture, got " .. #mixed.captured)

local reasons = {}
for _, skip in ipairs(mixed.skipped) do reasons[skip.key] = skip.reason end
assert(reasons.plater and reasons.plater:find("errored"), "a throw should be reported as one")
assert(reasons.details, "an empty return should be reported")

-- Too short to be a profile: exporters that fail politely return stubs, and a
-- Copy button that hands over eight characters is worse than no button.
_G.DandersFrames_Export = function() return "short" end
PUI.Config.shared = {}
local stub = Harvest:CaptureAll()
assert(next(PUI.Config.shared) == nil, "a stub return must not be stored")
assert(#stub.captured == 0, "a stub is not a capture")

-- A captured profile puts a button on the page, and beats a shipped one -
-- otherwise capturing your own settings would appear to do nothing.
_G.DandersFrames_Export = function() return REAL end
Harvest:CaptureAll()

local dandersEntry = PUI.Extras.byKey.dandersframes
assert(PUI.Extras:HasProfile(dandersEntry), "a captured profile should offer a button")

local text, origin = PUI.Extras:ProfileText(dandersEntry)
assert(text == REAL and origin == "captured", "captured text should be used and labelled")

dandersEntry.profile.text = "shipped-" .. REAL
text, origin = PUI.Extras:ProfileText(dandersEntry)
assert(origin == "captured", "a local capture should win over a shipped string")

PUI.Config.shared = {}
text, origin = PUI.Extras:ProfileText(dandersEntry)
assert(origin == "shipped", "with nothing captured, the shipped string is used")
dandersEntry.profile.text = nil

-- The author's half: what was captured, as the Lua that goes into Extras.lua.
_G.date = _G.date or function() return "2026-09-06" end
Harvest:CaptureAll()
local lua = Harvest:AsLua()
assert(lua and lua:find("%[==%[") and lua:find(REAL, 1, true),
    "the shipping block should contain the string in a long-bracket literal")
assert(lua:find("Extras.lua", 1, true), "the block should say where it goes")

Harvest:Clear()
assert(Harvest:AsLua() == nil, "nothing captured means nothing to ship")

_G.DandersFrames_Export, _G.Details, _G.PlaterAPI = nil, nil, nil

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
        name = "installing the pack, six modules and a graphics preset",
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
