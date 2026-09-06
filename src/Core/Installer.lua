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
        -- The per-context plan, seeded from the layout and editable on the
        -- graphics screen. Kept beside graphicsPreset rather than inside it
        -- because they are two different promises: the preset is what you get
        -- when you log in, the plan is what happens when you zone.
        autoSwitch = Layouts:AutoSwitchFor(key),
        autoSwitchTouched = false,
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
            local warning = Modules:Warn(module)
            if warning then
                lines[#lines + 1] = {
                    label = module.label,
                    detail = warning,
                    ok = false,
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
    end

    local performance = Modules.byKey.performance
    local available = Modules:IsAvailable(performance)
    local preset = choices.graphicsPreset

    if not available then
        lines[#lines + 1] = {
            label = performance.label,
            detail = "not installed - graphics left alone",
            ok = false,
        }
        return lines
    end

    if preset and preset ~= "none" then
        lines[#lines + 1] = {
            label = performance.label,
            detail = "graphics preset: " .. self:PresetName(preset),
            ok = true,
        }
    else
        lines[#lines + 1] = {
            label = performance.label,
            detail = "graphics settings left exactly as they are",
            ok = true,
        }
    end

    -- Auto-switch gets its own line, because it is a different promise from the
    -- preset: one says what you get now, the other says what happens when you
    -- walk through an instance portal. Somebody skimming the summary needs to
    -- see both, and the contexts that will actually do something are named
    -- rather than counted.
    local plan = choices.autoSwitch
    if plan and plan.enabled and preset and preset ~= "none" then
        local active = {}
        for _, ctx in ipairs(self:AutoSwitchContexts()) do
            local target = plan[ctx.key]
            if target and target ~= "none" then
                active[#active + 1] = ctx.short .. " " .. self:PresetName(target)
            end
        end

        lines[#lines + 1] = {
            label = "Auto-switch",
            detail = #active > 0 and table.concat(active, ", ") or "on, but every context set to no change",
            ok = #active > 0,
        }
    else
        lines[#lines + 1] = {
            label = "Auto-switch",
            detail = "off - graphics stay where you put them",
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
    local result = { applied = {}, disabled = {}, skipped = {}, failures = {}, warnings = {} }

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

                -- Asked after the write, not before: a module can only tell us
                -- it is going to ignore the layout once it has been handed one.
                local warning = Modules:Warn(module)
                if warning then
                    result.warnings[#result.warnings + 1] = module.label .. " is " .. warning
                end
            else
                result.disabled[#result.disabled + 1] = module.label
            end
        end
    end

    self:ApplyGraphics(choices.graphicsPreset, result, choices.autoSwitch)

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
--
-- Two things are written, in this order:
--
--   1. The baseline preset, applied now.
--   2. The auto-switch plan, which is config rather than an action - it decides
--      what happens the next time you zone into a raid, a key or the world.
--
-- Order matters here too. Auto-switch is written after the baseline so that
-- Evaluate() at the end sees the finished config and can correct the baseline
-- immediately if the player happens to be standing in a context the plan has an
-- opinion about. Installing Quality while sitting in a raid that the plan says
-- should be Performance should leave you on Performance, not on Quality until
-- the next loading screen.
function Installer:ApplyGraphics(presetKey, result, plan)
    result = result or { skipped = {}, failures = {} }

    local wantsPreset = presetKey and presetKey ~= "none"

    -- `plan` present means somebody was actually shown the graphics screen and
    -- answered it. Absent means this is a layout-only apply - /pui apply raid,
    -- or the Apply button on the settings page - where graphics were never part
    -- of the question. The difference matters: without it, switching layout
    -- would quietly switch off an auto-switch plan the player set up weeks ago.
    local asked = plan ~= nil

    -- "Leave my graphics alone" has to mean alone. Auto-switch is a CVar writer
    -- like any other, so when the screen was shown and the baseline came back
    -- "none" the plan is forced off rather than merely left unwritten -
    -- otherwise a plan carried over from a previous install would start firing
    -- on somebody who just said no.
    local wantsAuto = asked and wantsPreset and plan.enabled

    if not wantsPreset and not asked then
        return result
    end

    local module = Modules.byKey.performance
    local ref = Modules:Ref(module)
    if not ref then
        if wantsPreset then
            result.skipped[#result.skipped + 1] = module.label
        end
        return result
    end

    local config = ref.Config
    local manager = ref.PresetManager

    if wantsPreset then
        if not manager or type(manager.ApplyPreset) ~= "function" then
            result.failures[#result.failures + 1] = "PeaversPerformance: no preset manager"
            return result
        end

        -- ApplyPreset is a plain function on the module, not a method: it is
        -- called as PresetManager.ApplyPreset(key) throughout
        -- PeaversPerformance, so passing self here would land the table in the
        -- key argument.
        local ok, err = pcall(manager.ApplyPreset, presetKey)
        if not ok then
            result.failures[#result.failures + 1] = "PeaversPerformance: " .. tostring(err)
        end
    end

    if not config then
        return result
    end

    if asked then
        config.autoSwitchEnabled = wantsAuto and true or false

        if wantsAuto then
            for _, ctx in ipairs(self:AutoSwitchContexts()) do
                local target = plan[ctx.key]
                if target ~= nil then
                    config[ctx.configKey] = target
                end
            end
        end

        Modules.Call(ref, "Config:Save")
    end

    -- Act on wherever the player is standing right now. force skips
    -- PeaversPerformance's own same-context guard, which would otherwise decide
    -- nothing had changed because the zone had not.
    -- Called directly rather than through Modules.Call: Evaluate is a plain
    -- function taking one argument, and Call passes the owning table as self,
    -- which would land in the `force` parameter.
    if wantsAuto and ref.AutoSwitch and type(ref.AutoSwitch.Evaluate) == "function" then
        local ok, err = pcall(ref.AutoSwitch.Evaluate, true)
        if not ok then
            result.failures[#result.failures + 1] = "PeaversPerformance auto-switch: " .. tostring(err)
        end
    end

    return result
end

--------------------------------------------------------------------------------
-- Auto-switch vocabulary
--
-- Read out of PeaversPerformance where possible rather than restated here, so
-- the wizard offers exactly the contexts and tiers that addon actually knows
-- about. The fallback list exists only so the graphics screen can still be
-- drawn - and explain itself - when the module is not installed.
--------------------------------------------------------------------------------

-- `short` is the label used in the one-line install summary, where "Raid
-- Quality, M+ Performance" has to fit next to three other rows.
local FALLBACK_CONTEXTS = {
    { key = "raid",       name = "Raid",       short = "Raid",    configKey = "autoSwitchRaid" },
    { key = "mythicplus", name = "Mythic+",    short = "M+",      configKey = "autoSwitchMythicPlus" },
    { key = "dungeon",    name = "Dungeon",    short = "Dungeon", configKey = "autoSwitchDungeon" },
    { key = "world",      name = "Open world", short = "World",   configKey = "autoSwitchWorld" },
}

local SHORT_BY_KEY = {}
for _, ctx in ipairs(FALLBACK_CONTEXTS) do SHORT_BY_KEY[ctx.key] = ctx.short end

function Installer:AutoSwitchContexts()
    local ref = Modules:Ref(Modules.byKey.performance)
    local contexts = ref and ref.AutoSwitch and ref.AutoSwitch.contexts

    if not contexts then
        return FALLBACK_CONTEXTS
    end

    -- PeaversPerformance owns key, name and configKey; `short` is ours, so it
    -- is grafted on rather than expected to be there.
    local out = {}
    for index, ctx in ipairs(contexts) do
        out[index] = {
            key = ctx.key,
            name = ctx.name,
            configKey = ctx.configKey,
            short = SHORT_BY_KEY[ctx.key] or ctx.name,
        }
    end
    return out
end

-- Display name for a preset key, or for the two pseudo-targets the auto-switch
-- dropdowns carry alongside the real tiers.
function Installer:PresetName(key)
    if key == "none" then return "No change" end
    if key == "restore" then return "My original settings" end

    local ref = Modules:Ref(Modules.byKey.performance)
    local presets = ref and ref.Presets
    if presets and type(presets.GetName) == "function" then
        local ok, name = pcall(presets.GetName, key)
        if ok and name then return name end
    end

    return tostring(key)
end

-- What a context dropdown offers: leave it alone, any preset, or undo.
function Installer:AutoSwitchTargets()
    local targets = { { value = "none", label = "No change" } }

    local ref = Modules:Ref(Modules.byKey.performance)
    local presets = ref and ref.Presets
    if presets and presets.order then
        for _, key in ipairs(presets.order) do
            local preset = presets.presets and presets.presets[key]
            if preset then
                targets[#targets + 1] = { value = key, label = preset.name }
            end
        end
    end

    targets[#targets + 1] = { value = "restore", label = "My original settings" }
    return targets
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
