--------------------------------------------------------------------------------
-- PeaversUI live preview
--
-- Applies a layout to the real screen so it can be looked at, and puts
-- everything back afterwards.
--
-- This is the one place in the addon that breaks the "nothing is written until
-- you press Install" rule, so it earns its keep by being the most careful file
-- here. Three things make it safe:
--
--   1. The snapshot is the exact inverse of the apply. It is built by walking
--      the layout's own override table and recording the current value at every
--      key path it is about to write - so the restore cannot miss a key the
--      apply touched, and cannot invent one it did not.
--   2. A key that did not exist before is recorded as an absence, not skipped.
--      A plain deep copy loses that: writing `widgets.calendar = "hidden"` over
--      a table that never had `calendar` leaves a value behind that the restore
--      has no way to know should be gone.
--   3. The snapshot goes to disk before the first write. If the client crashes,
--      or the player alt-F4s mid-preview, the next login finds it and offers to
--      put it back - which is the difference between a preview and a mess.
--
-- Graphics are deliberately not previewed. A CVar preview is PeaversPerformance's
-- job (it already snapshots and restores), the effect of one is invisible in a
-- capital city, and applying a graphics preset can want a graphics restart -
-- which is not something to do to somebody who clicked "have a look".
--------------------------------------------------------------------------------

local _, PUI = ...

local Preview = {}
PUI.Preview = Preview

local PeaversCommons = _G.PeaversCommons
local Modules = PUI.Modules
local Layouts = PUI.Layouts

-- Recorded in place of a value that was absent. A table, so it can never be
-- confused with a real setting: no config holds this exact table but ours.
local ABSENT = setmetatable({}, { __tostring = function() return "<absent>" end })
Preview.ABSENT = ABSENT

Preview.active = nil   -- { layout = key, taken = {...}, modules = {...} }

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------

-- Record the current value at every key path `overrides` is about to write.
local function Capture(config, overrides)
    local taken = {}
    if type(config) ~= "table" or type(overrides) ~= "table" then return taken end

    for key, value in pairs(overrides) do
        local current = config[key]
        if type(value) == "table" then
            if type(current) == "table" then
                taken[key] = Capture(current, value)
            else
                -- The whole sub-table is new; recording its absence restores by
                -- removing it, rather than by leaving an empty husk behind.
                taken[key] = ABSENT
            end
        elseif current == nil then
            taken[key] = ABSENT
        else
            taken[key] = current
        end
    end

    return taken
end

-- Put a captured table back, honouring recorded absences.
local function Restore(config, taken)
    if type(config) ~= "table" or type(taken) ~= "table" then return end

    for key, value in pairs(taken) do
        if value == ABSENT then
            config[key] = nil
        elseif type(value) == "table" then
            if type(config[key]) == "table" then
                Restore(config[key], value)
            end
        else
            config[key] = value
        end
    end
end

Preview.Capture = Capture
Preview.Restore = Restore

--------------------------------------------------------------------------------
-- Persisting across a crash
--
-- Only the shape of the restore is written, never functions or frames. ABSENT is
-- turned into a string on the way out and back, because a table identity does
-- not survive a trip through SavedVariables.
--------------------------------------------------------------------------------

local ABSENT_TOKEN = "__peavers_absent__"

local function Encode(value)
    if value == ABSENT then return ABSENT_TOKEN end
    if type(value) ~= "table" then return value end

    local out = {}
    for key, inner in pairs(value) do out[key] = Encode(inner) end
    return out
end

local function Decode(value)
    if value == ABSENT_TOKEN then return ABSENT end
    if type(value) ~= "table" then return value end

    local out = {}
    for key, inner in pairs(value) do out[key] = Decode(inner) end
    return out
end

local function Persist(state)
    PUI.Config.previewRestore = state and {
        layout = state.layout,
        taken = Encode(state.taken),
        modules = state.modules,
    } or nil
    PUI.Config:Save()
end

--------------------------------------------------------------------------------
-- Start / stop
--------------------------------------------------------------------------------

function Preview:IsActive()
    return self.active ~= nil
end

-- True when this exact layout is already the one on screen. The layout screen
-- re-applies its selection whenever it is drawn, so that a lit card always
-- matches what the player is looking at; without this check, walking back to
-- that screen would revert and re-apply the same layout for no reason, which is
-- visible as a flicker.
function Preview:IsShowing(layoutKey)
    return self.active ~= nil and self.active.layout == layoutKey
end

-- @param layoutKey string
-- @param choices table  which modules are ticked, so the preview matches
-- @return boolean started, string|nil reason
function Preview:Start(layoutKey, choices)
    if self.active then
        self:Revert()
    end

    local layout = Layouts:Get(layoutKey)
    if not layout then return false, "Unknown layout." end

    -- Unit frames hand Blizzard's frames back and forth as they enable, and a
    -- protected frame can refuse to be touched mid-fight. Previewing is never
    -- urgent enough to be worth that.
    if InCombatLockdown() then
        return false, "Not in combat - try again when the fight is over."
    end

    local overrides = layout.overrides or {}
    local state = { layout = layoutKey, taken = {}, modules = {} }

    for _, module in ipairs(Modules:OfRole("display")) do
        if Modules:IsAvailable(module) then
            state.modules[module.key] = Modules:IsEnabled(module)

            local block = overrides[module.key]
            local config = Modules:ConfigOf(module)
            if block and config then
                state.taken[module.key] = Capture(config, block)
            end
        end
    end

    -- To disk before the first write, not after: the whole point is to survive
    -- the client going away between those two moments.
    Persist(state)
    self.active = state

    -- Reuse the installer rather than reimplementing the apply. A preview that
    -- writes settings by a different code path is a preview of something else.
    local plan = PUI.Installer:NewChoices(layoutKey)
    for _, module in ipairs(Modules:OfRole("display")) do
        plan.modules[module.key] = choices and choices.modules[module.key] or false
    end
    plan.graphicsPreset = "none"
    plan.autoSwitch = nil
    plan.isPreview = true

    -- Never reset while previewing, even when the install is going to.
    --
    -- The snapshot above records the current value of every key the layout is
    -- about to write, and nothing else - which is exactly enough to undo a
    -- layout and nowhere near enough to undo a reset. Resetting here would give
    -- back an undo that quietly did not.
    --
    -- The cost is a visible difference: a preview shows the layout over your
    -- current settings, while installing additionally clears what the layout
    -- does not mention. The review screen says which of the two it is doing, so
    -- the difference is stated rather than discovered.
    plan.resetFirst = false

    PUI.Installer:Apply(plan)

    return true
end

-- Put everything back. Safe to call when nothing is being previewed.
function Preview:Revert()
    local state = self.active ---@type table?
    if not state then
        -- Nothing live, but there may be something on disk from a session that
        -- ended badly.
        state = self:PendingState()
        if not state then return false end
    end

    for _, module in ipairs(Modules:OfRole("display")) do
        if Modules:IsAvailable(module) then
            local taken = state.taken and state.taken[module.key]
            local config = Modules:ConfigOf(module)
            if taken and config then
                Restore(config, taken)
                Modules.Call(Modules:Ref(module), "Config:Save")
            end

            local wasEnabled = state.modules and state.modules[module.key]
            if wasEnabled ~= nil then
                Modules:SetEnabled(module, wasEnabled)
            end

            Modules:Refresh(module)
        end
    end

    self.active = nil
    Persist(nil)
    return true
end

-- Stop previewing and keep what is on screen. The settings written stay written;
-- only the ability to undo them is given up, which is what "keep" means.
function Preview:Keep()
    if not self.active then return false end
    self.active = nil
    Persist(nil)
    return true
end

--------------------------------------------------------------------------------
-- Recovery
--------------------------------------------------------------------------------

-- A restore left on disk by a session that ended mid-preview, decoded and ready
-- to hand to Revert. nil when there is nothing outstanding.
function Preview:PendingState()
    local stored = PUI.Config.previewRestore
    if type(stored) ~= "table" or not stored.taken then return nil end

    return {
        layout = stored.layout,
        taken = Decode(stored.taken),
        modules = stored.modules,
    }
end

-- Called once at login. Deliberately does not undo anything on its own: waking
-- up to a UI that silently rearranged itself is the thing this is meant to
-- prevent, so it says what happened and leaves the decision alone.
function Preview:AnnouncePending()
    local pending = self:PendingState()
    if not pending then return false end

    local layout = Layouts:Get(pending.layout)
    local name = layout and layout.name or pending.layout or "a layout"

    PeaversCommons.Utils.Print(PUI,
        "you were previewing the " .. name .. " layout when you last logged out. " ..
        "Type /pui undo to put your old settings back, or /pui keep to stop asking.")
    return true
end

return Preview
