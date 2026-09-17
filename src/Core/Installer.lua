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
-- written lands in the module's own saved variables - the same ones Edit Mode
-- edits, so anything the pack sets can be changed there afterwards -
-- PeaversPerformance snapshots every CVar before it
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
-- The overrides a set of choices asks for
--
-- Everything that reads a layout goes through Layouts:OverridesFor with the
-- chosen canvas - the install, the summary and the live preview's snapshot - so
-- all three walk the same table. Reading the shipped layout anywhere would take
-- a snapshot against unscaled positions and hand back an undo that put the
-- frames somewhere they had never been.
--------------------------------------------------------------------------------
function Installer:OverridesFor(choices)
    if not choices or choices.layout == Layouts.CURRENT then return {} end
    return Layouts:OverridesFor(choices.layout, choices.canvas)
end

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
    -- "Keep my current setup" is a choice on the layout screen but not a layout:
    -- it has no overrides, no graphics suggestion and no revision, hence the
    -- empty table standing in for one.
    local keepCurrent = layoutKey == Layouts.CURRENT
    local key = (keepCurrent or Layouts:Get(layoutKey)) and layoutKey or "standard"
    local layout = Layouts:Get(key) or {}

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
        -- The canvas the layout is drawn for: the interface size question. What
        -- the account already holds, never the recommendation - a re-run, a
        -- /pui apply or a layout update must not resize somebody's interface
        -- because their monitor would have been told something different on a
        -- first install. The wizard is the only caller that pre-selects the
        -- suggestion, and only when nothing has ever been installed.
        canvas = tonumber(PUI.Config and PUI.Config.canvas) or Layouts.CANVAS_HEIGHT,
        -- Put each module back to its own defaults before the layout goes on.
        --
        -- On by default, because the thing people mean by "run the installer
        -- again" is "give me the clean result", not "merge this over whatever I
        -- have accumulated". Without it a layout only overwrites the settings it
        -- happens to name, and everything it stays quiet about - a font size
        -- changed in March, a bisect mode left switched on - survives and makes
        -- the result look like the installer half-worked.
        --
        -- It is a checkbox rather than a rule because it is the one genuinely
        -- destructive thing in here: settings made outside the pack go too.
        resetFirst = true,
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
    local overrides = self:OverridesFor(choices)
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
                local has = overrides[module.key] ~= nil
                local detail
                if choices.resetFirst and has then
                    detail = "reset, then styled for " .. layout.name
                elseif choices.resetFirst then
                    detail = "reset to its own defaults"
                elseif has then
                    detail = "on, styled for " .. layout.name
                else
                    detail = "on, left at its own settings"
                end

                lines[#lines + 1] = {
                    label = module.label,
                    detail = detail,
                    ok = true,
                }
            end
        end
    end

    -- Interface size gets its own row rather than hiding inside the Scaler's. It
    -- is the one thing in the summary that changes how big everything else on
    -- the list comes out, and "Scaler: reset, then styled for Standard" says
    -- none of that. Only when a layout is going on: keeping your current setup
    -- writes no positions, so there is no canvas to draw them for.
    if choices.layout ~= Layouts.CURRENT then
        local canvas = tonumber(choices.canvas) or Layouts.CANVAS_HEIGHT
        local size = Layouts:SizeLabel(canvas)
        local scaler = Modules.byKey.scaler
        local detail, ok

        if not Modules:IsAvailable(scaler) then
            detail = "PeaversScaler is not running, so the layout is placed for " ..
                     size .. " and drawn at whatever scale you are on"
        elseif not choices.modules[scaler.key] then
            detail = "Scaler switched off, so the layout is placed for " .. size ..
                     " and drawn at whatever scale you are on"
        elseif canvas == Layouts.CANVAS_HEIGHT then
            detail, ok = size .. " - the size the layouts were drawn at", true
        else
            detail, ok = size .. " of the size the layouts were drawn at, on a canvas " ..
                math.floor(canvas + 0.5) .. " units tall", true
        end

        lines[#lines + 1] = { label = "Interface size", detail = detail, ok = ok or false }
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
    -- Keeping the current setup applies no layout at all: nothing is reset and
    -- no override is written, whatever the reset box says.
    local keepCurrent = choices.layout == Layouts.CURRENT
    local layoutKey = not keepCurrent and (Layouts:Get(choices.layout) and choices.layout or "standard") or nil
    -- Drawn for the chosen interface size, not as shipped. See Layouts:OverridesFor.
    local overrides = layoutKey and Layouts:OverridesFor(layoutKey, choices.canvas) or {}

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

            -- Reset first of all, when asked - but only for modules being kept.
            -- Switching something off means "stop drawing this", not "throw away
            -- how I had it set up"; wiping the settings of a module on its way
            -- out is gratuitous and unrecoverable.
            --
            -- It has to come before the toggle as well as before the layout: a
            -- reset restores the module's own default for its enabled flag,
            -- which would otherwise undo the choice made two screens back.
            if wanted and choices.resetFirst and not keepCurrent then
                Modules:Reset(module)
            end

            -- Order matters: the toggle first, then the layout. Turning unit
            -- frames on switches every frame's `enabled` back to true, so a
            -- layout that wants target-of-target off has to be written after.
            --
            -- And only when the answer actually changes. Re-running "on" for a
            -- module that is already on re-enables every unit frame, including
            -- one the player switched off and the layout never mentions.
            if wanted ~= Modules:IsEnabled(module) then
                Modules:SetEnabled(module, wanted)
            end

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

    -- A player with a setup of their own who never touched the graphics screen
    -- was never asked about graphics, whatever the screen pre-filled: no plan,
    -- so an auto-switch setup they already run is left running.
    local plan = choices.autoSwitch
    if choices.existing and not choices.graphicsTouched and not choices.autoSwitchTouched then
        plan = nil
    end
    self:ApplyGraphics(choices.graphicsPreset, result, plan)

    -- Anything the module hops recorded along the way.
    for _, failure in ipairs(Modules:TakeFailures()) do
        result.failures[#result.failures + 1] = failure
    end

    -- A preview is not an install: it must not record a layout, a revision or a
    -- finished run that nobody agreed to.
    if not choices.isPreview then
        PUI.Config:MarkInstalled(choices)
    end

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
-- Quality, M+ Performance" has to fit next to three other rows. Keyed by name
-- rather than key: the timed-dungeon context keeps the key "mythicplus" on every
-- client that has one, and is called something different on each.
local SHORT_BY_NAME = {
    ["Raid"] = "Raid", ["Mythic+"] = "M+", ["Challenge Mode"] = "CM",
    ["Dungeon"] = "Dungeon", ["Open world"] = "World",
}

-- The contexts PeaversPerformance would offer on this client, for drawing the
-- graphics screen when it is not installed. Same rule it follows: a timed
-- dungeon context only where timed dungeons exist, named for what they are
-- called there.
local function FallbackContexts()
    local client = Modules.client and Modules.client.key or "retail"
    local list = { { key = "raid", name = "Raid", configKey = "autoSwitchRaid" } }
    if client == "retail" then
        list[#list + 1] = { key = "mythicplus", name = "Mythic+", configKey = "autoSwitchMythicPlus" }
    elseif client == "mists" then
        list[#list + 1] = { key = "mythicplus", name = "Challenge Mode", configKey = "autoSwitchMythicPlus" }
    end
    list[#list + 1] = { key = "dungeon", name = "Dungeon", configKey = "autoSwitchDungeon" }
    list[#list + 1] = { key = "world", name = "Open world", configKey = "autoSwitchWorld" }
    return list
end

function Installer:AutoSwitchContexts()
    local ref = Modules:Ref(Modules.byKey.performance)
    local contexts = ref and ref.AutoSwitch and ref.AutoSwitch.contexts or FallbackContexts()

    -- PeaversPerformance owns key, name, configKey and - since it learned which
    -- client it is on - short. Ours is only a fallback for an older version.
    local out = {}
    for _, ctx in ipairs(contexts) do
        if ctx.key and ctx.configKey then
            out[#out + 1] = {
                key = ctx.key,
                name = ctx.name,
                configKey = ctx.configKey,
                short = ctx.short or SHORT_BY_NAME[ctx.name] or ctx.name,
            }
        end
    end
    return out
end

-- What auto-switch reacts to on this client, as a phrase for the wizard's
-- sentences: "a raid, a key or a dungeon" on retail, and nothing about keys on a
-- client that has none.
function Installer:InstancePhrase()
    local timed
    for _, ctx in ipairs(self:AutoSwitchContexts()) do
        if ctx.key == "mythicplus" then timed = ctx.name end
    end
    if timed == "Mythic+" then return "a raid, a key or a dungeon" end
    if timed then return "a raid, a " .. timed .. " or a dungeon" end
    return "a raid or a dungeon"
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
