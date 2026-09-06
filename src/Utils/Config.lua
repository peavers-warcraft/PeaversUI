--------------------------------------------------------------------------------
-- PeaversUI Configuration
--
-- Account-wide by design, and deliberately tiny. This addon owns almost no
-- settings: everything the installer decides is written into the module addons'
-- own saved variables, where the module's settings page can then edit it. What
-- is kept here is only what the pack itself needs to remember between sessions.
--
-- The most load-bearing value is `installedVersion`. It is what stops the wizard
-- opening on every login, and it is a version rather than a boolean so that a
-- future pack release can offer a fresh pass ("the pack has new modules since
-- you set this up") without also nagging people who are already done.
--------------------------------------------------------------------------------

local addonName, PUI = ...

local PeaversCommons = _G.PeaversCommons
local ConfigManager = PeaversCommons.ConfigManager

PUI.name = PUI.name or addonName

local PUI_DEFAULTS = {
    -- Pack version the installer last completed a run for. nil means "never
    -- installed", which is what triggers the first-run wizard.
    installedVersion = nil,

    -- What the last run chose. Kept so the settings page can say what is
    -- currently applied, and so re-opening the wizard starts where you left off
    -- rather than back at the factory defaults.
    layout = "standard",
    graphicsPreset = "none",

    -- [moduleKey] = true/false, the module toggles from step two. Absent means
    -- "never asked", which the installer reads as the module's own default
    -- rather than as off - a module added in a later pack release must not
    -- arrive switched off because an older install never mentioned it.
    modules = {},

    -- Offer the wizard again when the pack updates. Off by default: an
    -- installer that reopens itself uninvited is the thing people hate about
    -- installers.
    promptOnUpdate = false,

    -- The wizard remembers where it was dragged to.
    framePoint = "CENTER",
    frameX = 0,
    frameY = 0,

    debugMode = false,
    DEBUG_ENABLED = false,
}

PUI.Config = ConfigManager:New(PUI, PUI_DEFAULTS, {
    savedVariablesName = "PeaversUIDB",
})

-- True when the wizard has never been completed for this pack version.
function PUI.Config:NeedsInstall()
    return self.installedVersion == nil
end

-- True when the pack has been installed, but by an older version of itself.
function PUI.Config:NeedsUpdate()
    return self.installedVersion ~= nil and self.installedVersion ~= PUI.version
end

-- Record a finished run. Takes the choices rather than reading them back off the
-- wizard so that a scripted install (/pui apply compact) records the same thing
-- a click-through does.
function PUI.Config:MarkInstalled(choices)
    self.installedVersion = PUI.version
    if choices then
        self.layout = choices.layout or self.layout
        self.graphicsPreset = choices.graphicsPreset or self.graphicsPreset
        if choices.modules then
            self.modules = {}
            for key, on in pairs(choices.modules) do
                self.modules[key] = on and true or false
            end
        end
    end
    self:Save()
end

return PUI.Config
