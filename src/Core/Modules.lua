--------------------------------------------------------------------------------
-- PeaversUI module manifest
--
-- The list of what the pack is made of, and the only place that knows how to
-- talk to each piece. Everything else in this addon - the wizard, the installer,
-- the settings page - works against this table and never reaches into another
-- addon directly.
--
-- That is the whole design rule here: one file that breaks when a module changes
-- its API, rather than five. If PeaversChat renames Frames:Refresh, exactly one
-- function below stops working and the pack keeps running, because every hop
-- into another addon goes through Call() and is allowed to fail.
--
-- Detection is deliberately three-valued. "loaded" is not the same as
-- "installed but switched off at the character screen", and neither is the same
-- as "not installed at all" - they need three different sentences on the welcome
-- screen, and only one of them is a problem the player can fix from in here.
--------------------------------------------------------------------------------

local _, PUI = ...

local Modules = {}
PUI.Modules = Modules

--------------------------------------------------------------------------------
-- Safe calling
--
-- Every hop into another addon is a call into code this addon does not ship and
-- cannot version-lock. WoW suppresses Lua errors by default, so an unprotected
-- throw halfway through an install looks exactly like "the installer did
-- nothing": the modules after the failing one are silently skipped and no error
-- ever reaches the screen. pcall plus a recorded failure is what turns that into
-- a line on the summary page.
--------------------------------------------------------------------------------

local failures = {}

-- Resolve a dotted path against a root table without erroring on a missing hop.
local function Resolve(root, path)
    local node = root
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

-- Call `root.a.b:method(...)` if every hop exists, and swallow whatever it
-- throws. Returns true when the call actually happened and returned cleanly.
local function Call(root, path, ...)
    if not root then return false end

    -- "Square:Apply" splits into the owner path and the method; a bare "Apply"
    -- has no separator and is called on the root itself.
    local ownerPath, method = path:match("^(.+)[:%.]([^:%.]+)$")
    if not method then
        ownerPath, method = nil, path
    end

    local owner = ownerPath and Resolve(root, ownerPath) or root
    if type(owner) ~= "table" then return false end

    local fn = owner[method]
    if type(fn) ~= "function" then return false end

    local ok, err = pcall(fn, owner, ...)
    if not ok then
        failures[#failures + 1] = path .. ": " .. tostring(err)
    end
    return ok
end

Modules.Call = Call

function Modules:TakeFailures()
    local taken = failures
    failures = {}
    return taken
end

--------------------------------------------------------------------------------
-- The manifest
--
-- `role`:
--   "core"    - a library the pack cannot run without. Listed on the welcome
--               screen so the roster is honest, never toggleable.
--   "display" - draws something. Gets a checkbox in the modules step and a
--               block of settings in every layout.
--   "system"  - changes the client rather than the interface. Configured by its
--               own step, because "on/off" is not the question worth asking.
--------------------------------------------------------------------------------

Modules.list = {
    {
        key = "commons",
        folder = "PeaversCommons",
        label = "Commons",
        role = "core",
        blurb = "The shared library every Peavers addon is built on.",
    },
    {
        key = "config",
        folder = "PeaversConfig",
        label = "Config",
        role = "core",
        blurb = "One settings window for the whole collection - /peavers.",
    },
    {
        key = "unitframes",
        folder = "PeaversUnitFrames",
        label = "Unit Frames",
        role = "display",
        blurb = "Player, target, target of target and focus, with cast bars and auras.",
        slash = "/puf",

        IsEnabled = function(_, ref)
            local unit = ref.Config and ref.Config.GetUnit and ref.Config:GetUnit("player")
            return unit and unit.enabled ~= false or false
        end,

        -- Unit frames have no master switch of their own: "off" means every
        -- frame off *and* Blizzard's frames handed back, or the player is left
        -- staring at an empty screen where their health used to be.
        SetEnabled = function(_, ref, on)
            local config = ref.Config
            if not config then return end
            for _, key in ipairs(config.UNIT_ORDER or {}) do
                local unit = config:GetUnit(key)
                if unit then unit.enabled = on end
            end
            config.hideBlizzardFrames = on
            Call(ref, "Config:Save")
        end,

        Refresh = function(_, ref)
            Call(ref, "Blizzard:Apply")
            Call(ref, "Core:RefreshAll")
        end,
    },
    {
        key = "castbar",
        folder = "PeaversCastBar",
        label = "Cast Bar",
        role = "display",
        blurb = "Cast bars for player, target, focus and pet, matched to the Cooldown Manager.",
        slash = "/pcb",

        IsEnabled = function(_, ref)
            local unit = ref.Config and ref.Config.GetUnit and ref.Config:GetUnit("player")
            return unit and unit.enabled == true or false
        end,

        -- The same shape as the unit frames, and for the same reason: there is
        -- no master switch, so "off" means every bar off *and* Blizzard's own
        -- cast bars handed back, or the player is left with no cast bar at all.
        SetEnabled = function(_, ref, on)
            local config = ref.Config
            if not config or type(config.GetUnit) ~= "function" then return end

            for _, unit in ipairs(ref.Units or {}) do
                local unitConfig = config:GetUnit(unit.key)
                if unitConfig then unitConfig.enabled = on end
            end
            Call(ref, "Config:Save")

            -- Blizzard:Apply reads the config it is handed, so it is passed
            -- explicitly: Call would otherwise hand it the owning table as the
            -- first argument and it would find no units at all.
            Call(ref, "Blizzard:Apply", config)
            Call(ref, "Core:ApplyConfig")
        end,

        Refresh = function(_, ref)
            Call(ref, "Core:ApplyConfig")
            Call(ref, "Blizzard:Apply", ref.Config)
        end,
    },
    {
        key = "minimap",
        folder = "PeaversMiniMap",
        label = "MiniMap",
        role = "display",
        blurb = "Square minimap pinned to a corner, with the addon buttons in one grid.",
        slash = "/pmm",

        IsEnabled = function(_, ref)
            return ref.Config and ref.Config.enabled == true
        end,

        -- Square:Enable/Disable do the reversible work; setting the flag alone
        -- would leave the minimap round until the next login.
        SetEnabled = function(_, ref, on)
            Call(ref, on and "Square:Enable" or "Square:Disable")
        end,

        Refresh = function(_, ref)
            if ref.Config and ref.Config.enabled then
                Call(ref, "Square:Apply")
                Call(ref, "Buttons:Layout")
            end
        end,
    },
    {
        key = "chat",
        folder = "PeaversChat",
        label = "Chat",
        role = "display",
        blurb = "A flat chat window with text tabs, clickable links and a copy button.",
        slash = "/pchat",

        IsEnabled = function(_, ref)
            return ref.Config and ref.Config.enabled == true
        end,

        SetEnabled = function(_, ref, on)
            if not ref.Config then return end
            ref.Config.enabled = on
            Call(ref, "Config:Save")
            if on then
                Call(ref, "Channels:Apply")
            else
                Call(ref, "Channels:Restore")
                Call(ref, "Frames:Restore")
            end
            -- Links has to be synced either way: off means the URL filter is
            -- gone from the client's table, not that it runs and declines.
            Call(ref, "Links:Sync")
            Call(ref, "Buttons:Refresh")
        end,

        Refresh = function(_, ref)
            if ref.Config and ref.Config.enabled then
                Call(ref, "Channels:Apply")
                Call(ref, "Buttons:Refresh")
                Call(ref, "Frames:Refresh")
                Call(ref, "Tabs:PaintAll")
                Call(ref, "Position:Reapply")
                Call(ref, "Links:Sync")
            end
        end,

        -- PeaversChat has bisect modes - /pchat without <group> and /pchat
        -- minimal - that take features away to find which one is breaking chat,
        -- and stash the real settings in a backup table while they do. A layout
        -- written underneath one of those is written and then immediately
        -- overridden, which from the outside looks exactly like the installer
        -- not working.
        --
        -- It is worth detecting rather than fixing silently: those modes were
        -- switched on to answer a question, and clearing one behind somebody's
        -- back would throw away the answer. So the installer says so and leaves
        -- the decision alone.
        Warn = function(_, ref)
            local config = ref.Config
            if not config then return nil end

            if next(config.minimalBackup or {}) ~= nil then
                return "in /pchat minimal - run /pchat minimal to leave it, or the layout stays overridden"
            end

            if next(config.withoutBackup or {}) ~= nil then
                return "in /pchat without - run /pchat without none, or the layout stays overridden"
            end

            return nil
        end,
    },
    {
        key = "tooltip",
        folder = "PeaversToolTip",
        label = "ToolTip",
        role = "display",
        blurb = "Flat tooltips whose border carries item quality or unit reaction.",
        slash = "/ptt",

        IsEnabled = function(_, ref)
            return ref.Config and ref.Config.enabled == true
        end,

        SetEnabled = function(_, ref, on)
            if not ref.Config then return end
            ref.Config.enabled = on
            Call(ref, "Config:Save")
            if on then
                Call(ref, "Skin:ApplyAll")
                Call(ref, "HealthBar:ApplyLayout")
            else
                Call(ref, "Skin:RestoreAll")
                Call(ref, "HealthBar:Restore")
            end
        end,

        Refresh = function(_, ref)
            if ref.Config and ref.Config.enabled then
                Call(ref, "Skin:ApplyAll")
                Call(ref, "HealthBar:ApplyLayout")
            end
        end,
    },
    {
        key = "systembars",
        folder = "PeaversSystemBars",
        label = "System Bars",
        role = "display",
        blurb = "FPS and latency as bars, so a stutter has a shape you can see.",
        slash = "/psb",

        IsEnabled = function(_, ref)
            return ref.Config and ref.Config.showOnLogin == true
        end,

        SetEnabled = function(_, ref, on)
            if not ref.Config then return end
            ref.Config.showOnLogin = on
            Call(ref, "Config:Save")
            local frame = ref.Core and ref.Core.frame
            if frame then
                if on then frame:Show() else frame:Hide() end
            end
        end,

        -- The same sequence PeaversSystemBars runs for itself when its profile
        -- changes. Bars are rebuilt rather than resized because a layout can
        -- change the frame width, and the bars size themselves off the frame.
        Refresh = function(_, ref)
            local core = ref.Core
            if not core or not core.frame then return end
            if ref.Config and ref.Config.frameWidth then
                core.frame:SetWidth(ref.Config.frameWidth)
            end
            Call(ref, "Core:ApplyFramePosition")
            if ref.BarManager and core.contentFrame then
                Call(ref, "BarManager:CreateBars", core.contentFrame)
                Call(ref, "BarManager:ResizeBars")
                Call(ref, "Core:AdjustFrameHeight")
            end
            Call(ref, "Core:UpdateFrameBackground")
            Call(ref, "Core:UpdateTitleBarVisibility")
            Call(ref, "Core:UpdateFrameLock")
        end,
    },
    {
        key = "scaler",
        folder = "PeaversScaler",
        label = "Scaler",
        role = "display",
        blurb = "Sets the UI scale the layouts were drawn at, so they land in the same place on any screen.",
        slash = "/pscaler",

        IsEnabled = function(_, ref)
            return ref.Config and ref.Config.enabled == true
        end,

        -- Scaler:Enable records the player's own Blizzard scale before its first
        -- write, and Disable hands that back, so both go through the addon rather
        -- than flipping the flag.
        --
        -- Off when already off does nothing. Disable with no recorded original
        -- falls back to an approximate scale of its own, which would change the
        -- UI of somebody who never used the scaler and only unticked its box.
        SetEnabled = function(_, ref, on)
            if not on and not (ref.Config and ref.Config.enabled) then return end
            Call(ref, on and "Scaler:Enable" or "Scaler:Disable")
        end,

        Refresh = function(_, ref)
            if ref.Config and ref.Config.enabled then
                Call(ref, "Scaler:Apply")
            end
        end,

        -- The flat ConfigManager Reset drops every key the defaults do not name,
        -- and `original` - the player's scale from before PeaversScaler ever
        -- touched it - is exactly such a key. Losing it would turn "reset first"
        -- into "forget what my UI used to look like", and /pscaler restore into a
        -- command that restores nothing. So it is carried across the reset.
        Reset = function(_, ref)
            local config = ref.Config
            local original = config.original
            config:Reset()
            config.original = original
            config:Save()
        end,
    },
    {
        key = "performance",
        folder = "PeaversPerformance",
        label = "Performance",
        role = "system",
        blurb = "One-click graphics presets, with every CVar it touches snapshotted first.",
        slash = "/pperf",
    },
}

Modules.byKey = {}
for _, module in ipairs(Modules.list) do
    Modules.byKey[module.key] = module
end

--------------------------------------------------------------------------------
-- Which client
--
-- The pack runs on retail and on the Classic clients. Nearly everything that
-- differs between them is the modules' business; the pack only needs to know
-- which content exists - keys, Challenge Modes, neither - and which recommended
-- addons make sense. PeaversCommons.Compat answers when it is there, the
-- interface number otherwise, and anything unrecognised reads as retail so an
-- unfamiliar client keeps today's behaviour rather than losing some of it.
--------------------------------------------------------------------------------
function Modules:DetectClient()
    local compat = _G.PeaversCommons and _G.PeaversCommons.Compat
    local interface = compat and compat.interface
    if not interface and type(GetBuildInfo) == "function" then
        interface = tonumber((select(4, GetBuildInfo())))
    end
    interface = interface or 0

    local key = "retail"
    if compat and compat.isClassicEra ~= nil then
        key = (compat.isClassicEra and "era") or (compat.isAnniversary and "anniversary")
            or (compat.isMists and "mists") or (compat.isClassic and "classic") or "retail"
    elseif interface > 0 and interface < 20000 then
        key = "era"
    elseif interface >= 20000 and interface < 30000 then
        key = "anniversary"
    elseif interface >= 50000 and interface < 60000 then
        key = "mists"
    elseif interface > 0 and interface < 100000 then
        key = "classic"
    end

    self.client = { key = key, interface = interface, isRetail = key == "retail" }
    return self.client
end

Modules:DetectClient()

--------------------------------------------------------------------------------
-- Presence
--------------------------------------------------------------------------------

-- The live addon table a module publishes into _G, or nil if it is not running.
-- Preferred over _G alone because a module that registered with PeaversConfig
-- has told us where it lives; _G is the fallback for one that has not.
function Modules:Ref(module)
    local registry = _G.PeaversCommons and _G.PeaversCommons.ConfigRegistry
    if registry then
        local info = registry:GetAddon(module.folder)
        if info and info.addonRef then return info.addonRef end
    end
    return _G[module.folder]
end

-- "loaded" | "disabled" | "missing"
--
-- Three values rather than a boolean because they need three different
-- sentences. "disabled" is the interesting one: the files are on disk and the
-- player only has to tick a box at the character screen, which is worth saying
-- out loud instead of telling them to go and download something they already
-- have.
function Modules:Status(module)
    if self:Ref(module) then return "loaded" end

    local info = C_AddOns and C_AddOns.GetAddOnInfo
    if info then
        local name = C_AddOns.GetAddOnInfo(module.folder)
        if name then return "disabled" end
    end

    return "missing"
end

function Modules:IsAvailable(module)
    return self:Ref(module) ~= nil
end

-- Modules of one role, in manifest order.
function Modules:OfRole(role)
    local out = {}
    for _, module in ipairs(self.list) do
        if module.role == role then out[#out + 1] = module end
    end
    return out
end

--------------------------------------------------------------------------------
-- Talking to a module
--
-- All three take the manifest entry rather than the key, and all three are
-- no-ops for a module that is not running. Callers never have to guard.
--------------------------------------------------------------------------------

function Modules:IsEnabled(module)
    local ref = self:Ref(module)
    if not ref or not module.IsEnabled then return false end
    local ok, result = pcall(module.IsEnabled, module, ref)
    return ok and result or false
end

function Modules:SetEnabled(module, on)
    local ref = self:Ref(module)
    if not ref or not module.SetEnabled then return false end
    local ok, err = pcall(module.SetEnabled, module, ref, on and true or false)
    if not ok then
        failures[#failures + 1] = module.folder .. " enable: " .. tostring(err)
    end
    return ok
end

function Modules:Refresh(module)
    local ref = self:Ref(module)
    if not ref or not module.Refresh then return false end
    local ok, err = pcall(module.Refresh, module, ref)
    if not ok then
        failures[#failures + 1] = module.folder .. " refresh: " .. tostring(err)
    end
    return ok
end

-- Put a module back to its own defaults, wiping whatever an earlier setup, a
-- bisect mode or a season of tinkering left behind.
--
-- Deliberately the module's own Reset rather than anything of ours: it knows
-- which of its settings are settings and which are bookkeeping, and for the
-- profile-backed modules it is AceDB's ResetProfile, which is the only correct
-- answer. The pack has no business inventing a second idea of "default".
function Modules:Reset(module)
    local config = self:ConfigOf(module)
    if not config or type(config.Reset) ~= "function" then return false end

    -- A module that keeps state its defaults do not describe - PeaversScaler's
    -- record of the player's original scale - declares a Reset of its own that
    -- carries it across. Everything else gets the config's own Reset directly.
    local ok, err
    if module.Reset then
        ok, err = pcall(module.Reset, module, self:Ref(module))
    else
        ok, err = pcall(config.Reset, config)
    end
    if not ok then
        failures[#failures + 1] = module.folder .. " reset: " .. tostring(err)
    end
    return ok
end

-- A reason this module will not do what the layout says, or nil when there is
-- none. Modules opt in by declaring Warn; most have nothing to say.
function Modules:Warn(module)
    local ref = self:Ref(module)
    if not ref or not module.Warn then return nil end
    local ok, reason = pcall(module.Warn, module, ref)
    return ok and reason or nil
end

-- The module's own config table, for the installer to write layout values into.
function Modules:ConfigOf(module)
    local ref = self:Ref(module)
    return ref and ref.Config or nil
end

--------------------------------------------------------------------------------
-- Has this player set anything up?
--
-- Asked when the installer opens, to decide whether it starts from "keep what I
-- have" instead of from the pack's own layout. The signal is a setting that
-- differs from the module's defaults: a module that has only ever run at its
-- defaults has nothing to lose, and one with anything else - by hand or by an
-- earlier install - does.
--
-- AceDB-backed configs store only what differs from the defaults, so a stored
-- profile with anything in it is the answer. Flat configs store every key and
-- keep their defaults beside them, so values are compared.
--
-- Wrong in the safe direction when it is wrong: a new player flagged as existing
-- has to click a layout, and an existing player is never treated as new.
--------------------------------------------------------------------------------

-- Written by the modules themselves - debug switches, a scale snapshot, one-time
-- migrations - so they say nothing about what the player chose.
local NOT_A_CHOICE = {
    DEBUG_ENABLED = true, debugMode = true, original = true,
    shortChannelNamesWithdrawn = true, edgeToEdgeWithdrawn = true,
    paddingSplit = true, padding = true,
}

-- PeaversChat splits its old single padding into four sides on first run, which
-- on a brand-new install writes the legacy value over the left default. A side
-- equal to that legacy value is the migration's doing, not the player's.
local function Migrated(config, key)
    if key ~= "paddingLeft" and key ~= "paddingRight"
        and key ~= "paddingTop" and key ~= "paddingBottom" then
        return false
    end
    local legacy = tonumber(config.padding)
    return legacy ~= nil and tonumber(config[key]) == legacy
end

local function Differs(a, b)
    if type(a) == "number" and type(b) == "number" then
        return math.abs(a - b) > 1e-6
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return a ~= b
    end
    for key, value in pairs(a) do
        if Differs(value, b[key]) then return true end
    end
    for key in pairs(b) do
        if a[key] == nil then return true end
    end
    return false
end

function Modules:HasCustomSettings(module)
    local config = self:ConfigOf(module)
    if type(config) ~= "table" then return false end

    local db = rawget(config, "db")
    if type(db) == "table" and type(db.sv) == "table" and type(db.keys) == "table" then
        local stored = db.sv.profiles and db.sv.profiles[db.keys.profile]
        if type(stored) ~= "table" then return false end
        for key in pairs(stored) do
            if not NOT_A_CHOICE[key] then return true end
        end
        return false
    end

    local defaults = rawget(config, "defaults")
    if type(defaults) ~= "table" then return false end
    for key, default in pairs(defaults) do
        if not NOT_A_CHOICE[key] and not Migrated(config, key)
            and Differs(config[key], default) then
            return true
        end
    end
    return false
end

-- @return boolean, string|nil  whether any running display module holds settings
--                              of the player's own, and the first one found
function Modules:HasExistingSetup()
    for _, module in ipairs(self:OfRole("display")) do
        if self:IsAvailable(module) then
            local ok, custom = pcall(self.HasCustomSettings, self, module)
            if ok and custom then return true, module.label end
        end
    end
    return false
end

return Modules
