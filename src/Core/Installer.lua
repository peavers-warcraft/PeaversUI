--------------------------------------------------------------------------------
-- PeaversUI installer
--
-- Takes the choices the wizard collected and writes them into the module
-- addons. This is the only file that mutates another addon's settings, and it
-- does so in a fixed order that matters:
--
--   1. Module toggles, because turning unit frames on resets every frame's
--      `enabled` flag, and a layout that switches target-of-target off has to
--      run after that or its decision is thrown away.
--   2. Layout overrides, deep-merged over whatever the module already holds.
--   3. Save, then refresh, so a module never redraws from a half-written table.
--   4. The graphics preset, last and separately, because it is the one step
--      that changes the game client rather than the interface.
--
-- Nothing here is destructive in the way an installer usually is. Every value
-- written lands in the module's own saved variables where its own settings page
-- can edit it afterwards, PeaversPerformance snapshots every CVar before it
-- touches one, and `Preview` answers "what would this change" without changing
-- anything - which is what the review step is built out of.
--------------------------------------------------------------------------------

local _, PUI = ...

local Installer = {}
PUI.Installer = Installer

local Modules = PUI.Modules
local Layouts = PUI.Layouts

--------------------------------------------------------------------------------
-- Deep merge
--
-- Writes `src` over `dst` in place, recursing into tables rather than replacing
-- them. Replacing would be wrong twice over: a layout naming only
-- `units.player.x` would blow away the rest of the player's settings, and for an
-- AceDB-backed config it would also detach the table from the defaults
-- metatable that AceDB uses to decide what is worth saving to disk.
--
-- Colour tables ({r=,g=,b=}) merge key by key like anything else, which is what
-- we want: a layout can change alpha without restating the colour.
--------------------------------------------------------------------------------
local function DeepMerge(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end

    for key, value in pairs(src) do
        if type(value) == "table" then
            -- Index dst[key] first: on an AceDB profile that read is what
            -- materialises the sub-table from the defaults, so assigning into
            -- it afterwards persists.
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            DeepMerge(dst[key], value)
        else
            dst[key] = value
        end
    end
end

Installer.DeepMerge = DeepMerge

--------------------------------------------------------------------------------
-- Choices
--
-- The shape the wizard fills in and the installer consumes. Built here rather
-- than in the UI so that /pui apply raid produces exactly the same object a
-- click-through does, and there is only one thing to test.
--------------------------------------------------------------------------------

-- @param layoutKey string  a key from PUI.Layouts.order
-- @return table            { layout, graphicsPreset, modules = { [key] = bool } }
function Installer:NewChoices(layoutKey)
    local key = Layouts:Get(layoutKey) and layoutKey or "standard"
    local layout = Layouts:Get(key)

    local choices = {
        layout = key,
        -- nil until the graphics step runs, where it takes the layout's
        -- recommendation as its starting value. "none" is a real answer meaning
        -- "leave my CVars alone" and has to be distinguishable from "not asked
        -- yet", which is what the nil is for.
        graphicsPreset = nil,
        -- Set once the player picks a tier by hand. After that, changing the
        -- layout no longer overwrites their choice.
        graphicsTouched = false,
        modules = {},
        recommendedGraphics = layout.graphics,
    }

    -- Every display module the client is actually running starts ticked. A
    -- module that is installed but currently switched off in its own settings
    -- still starts ticked: the player opened a pack installer, so the default
    -- answer to "do you want this part of the pack" is yes.
    for _, module in ipairs(Modules:OfRole("display")) do
        choices.modules[module.key] = Modules:IsAvailable(module)
    end

    return choices
end

--------------------------------------------------------------------------------
-- Preview
--
-- What Apply would do, without doing it. The review step renders this, so the
-- summary a player reads is generated from the same manifest the install walks
-- rather than written out by hand somewhere it can drift.
--------------------------------------------------------------------------------
function Installer:Preview(choices)
    local layout = Layouts:Get(choices.layout)
    local lines = {}

    for _, module in ipairs(Modules:OfRole("display")) do
        local status = Modules:Status(module)
        local wanted = choices.modules[module.key]

        if status ~= "loaded" then
            lines[#lines + 1] = {
                label = module.label,
                detail = status == "disabled"
                    and "not enabled at the character screen - skipped"
                    or "not installed - skipped",
                ok = false,
            }
        elseif not wanted then
            lines[#lines + 1] = {
                label = module.label,
                detail = "switched off",
                ok = true,
            }
        else
            local has = layout and layout.overrides and layout.overrides[module.key]
            lines[#lines + 1] = {
                label = module.label,
                detail = has and ("on, styled for " .. layout.name) or "on, left at its own settings",
                ok = true,
            }
        end
    end

    local performance = Modules.byKey.performance
    if choices.graphicsPreset and choices.graphicsPreset ~= "none" then
        local available = Modules:IsAvailable(performance)
        lines[#lines + 1] = {
            label = performance.label,
            detail = available
                and ("graphics preset: " .. choices.graphicsPreset)
                or "not installed - graphics left alone",
            ok = available,
        }
    else
        lines[#lines + 1] = {
            label = performance.label,
            detail = "graphics settings left exactly as they are",
            ok = true,
        }
    end

    return lines
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

-- Write one module's layout block into its live config.
local function ApplyOverrides(module, overrides)
    local config = Modules:ConfigOf(module)
    if not config or not overrides then return false end

    local ok, err = pcall(DeepMerge, config, overrides)
    if not ok then
        return false, err
    end

    Modules.Call(Modules:Ref(module), "Config:Save")
    return true
end

-- @param choices table from NewChoices, with the wizard's answers filled in
-- @return table   { applied = {labels}, skipped = {labels}, failures = {strings} }
function Installer:Apply(choices)
    local layout = Layouts:Get(choices.layout) or Layouts:Get("standard")
    local overrides = layout.overrides or {}

    -- Drain anything left over from an earlier run so the report only ever
    -- describes this one.
    Modules:TakeFailures()

    -- Three outcomes, kept apart on purpose. "Configured X, Y and Z" that
    -- silently includes the module you just switched off is the kind of summary
    -- that makes people stop reading summaries.
    local result = { applied = {}, disabled = {}, skipped = {}, failures = {} }

    for _, module in ipairs(Modules:OfRole("display")) do
        if not Modules:IsAvailable(module) then
            result.skipped[#result.skipped + 1] = module.label
        else
            local wanted = choices.modules[module.key] and true or false

            -- Order matters: the toggle first, then the layout. Turning unit
            -- frames on switches every frame's `enabled` back to true, so a
            -- layout that wants target-of-target off has to be written after.
            Modules:SetEnabled(module, wanted)

            if wanted then
                local ok, err = ApplyOverrides(module, overrides[module.key])
                if not ok and err then
                    result.failures[#result.failures + 1] = module.folder .. ": " .. tostring(err)
                end
                Modules:Refresh(module)
                result.applied[#result.applied + 1] = module.label
            else
                result.disabled[#result.disabled + 1] = module.label
            end
        end
    end

    self:ApplyGraphics(choices.graphicsPreset, result)

    -- Anything the module hops recorded along the way.
    for _, failure in ipairs(Modules:TakeFailures()) do
        result.failures[#result.failures + 1] = failure
    end

    PUI.Config:MarkInstalled(choices)

    return result
end

-- Graphics is separate from the layout loop because it is a different kind of
-- change: it rewrites console variables rather than interface settings, and it
-- is the only thing in the pack that can want a graphics restart.
--
-- The work is PeaversPerformance's, not ours. It snapshots every CVar before it
-- writes one, defers to after combat if it has to, and can put everything back
-- with /pperf restore - none of which we would get right by setting CVars here.
function Installer:ApplyGraphics(presetKey, result)
    result = result or { skipped = {}, failures = {} }

    if not presetKey or presetKey == "none" then
        return result
    end

    local module = Modules.byKey.performance
    local ref = Modules:Ref(module)
    if not ref then
        result.skipped[#result.skipped + 1] = module.label
        return result
    end

    local manager = ref.PresetManager
    if not manager or type(manager.ApplyPreset) ~= "function" then
        result.failures[#result.failures + 1] = "PeaversPerformance: no preset manager"
        return result
    end

    -- ApplyPreset is a plain function on the module, not a method: it is called
    -- as PresetManager.ApplyPreset(key) throughout PeaversPerformance, so
    -- passing self here would land the table in the key argument.
    local ok, err = pcall(manager.ApplyPreset, presetKey)
    if not ok then
        result.failures[#result.failures + 1] = "PeaversPerformance: " .. tostring(err)
    end

    return result
end

--------------------------------------------------------------------------------
-- Graphics preset choices
--
-- Read out of PeaversPerformance rather than duplicated here, so the wizard
-- offers exactly the tiers that addon actually ships. When it is not installed
-- the step still renders, with the one honest option.
--------------------------------------------------------------------------------
function Installer:GraphicsOptions()
    local options = {
        { value = "none", label = "Leave my graphics settings alone",
          blurb = "Nothing is changed. You can pick a preset later with /pperf." },
    }

    local ref = Modules:Ref(Modules.byKey.performance)
    local presets = ref and ref.Presets
    if not presets or not presets.order then
        return options
    end

    for _, key in ipairs(presets.order) do
        local preset = presets.presets and presets.presets[key]
        if preset then
            options[#options + 1] = {
                value = key,
                label = preset.name,
                blurb = preset.blurb,
            }
        end
    end

    return options
end

return Installer
