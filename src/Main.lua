local addonName, PUI = ...

local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

PUI.name = addonName
PUI.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

--------------------------------------------------------------------------------
-- Slash commands
--
-- `/pui` opens the installer rather than the settings page, which breaks the
-- convention every other addon in the collection follows. It is deliberate:
-- this addon is the installer. Somebody typing its slash command wants the
-- wizard, and the settings page is one word further on.
--------------------------------------------------------------------------------

local function ApplyLayoutByName(name)
    local key = name and name:trim():lower() or ""
    local layout = PUI.Layouts:Get(key)

    if not layout then
        local names = {}
        for _, entry in ipairs(PUI.Layouts:Sorted()) do
            names[#names + 1] = entry.key
        end
        Utils.Print(PUI, "Usage: /pui apply " .. table.concat(names, " | "))
        return
    end

    local choices = PUI.Installer:NewChoices(key)

    -- Honour what is currently switched on rather than the full roster: this
    -- command changes the arrangement, not the decision about which modules the
    -- player wanted in the first place.
    for _, module in ipairs(PUI.Modules:OfRole("display")) do
        choices.modules[module.key] = PUI.Modules:IsAvailable(module)
            and PUI.Modules:IsEnabled(module)
            or false
    end

    -- Never from a slash command. Changing CVars is the one thing in the pack
    -- that wants an explicit yes on a screen that explains it - and dropping the
    -- plan entirely, rather than answering "none", is what stops this command
    -- switching off an auto-switch setup the player already has.
    choices.graphicsPreset = "none"
    choices.autoSwitch = nil

    local result = PUI.Installer:Apply(choices)

    Utils.Print(PUI, layout.name .. " layout applied to " .. #result.applied .. " module(s).")
    for _, failure in ipairs(result.failures) do
        print("  |cffff6666" .. failure .. "|r")
    end
end

PeaversCommons.SlashCommands:Register(addonName, "pui", {
    default = function()
        PUI.Wizard:Toggle()
    end,
    install = function()
        PUI.Wizard:Show()
    end,
    settings = function()
        PUI.ConfigUI:OpenOptions()
    end,
    config = function()
        PUI.ConfigUI:OpenOptions()
    end,
    apply = ApplyLayoutByName,
    layout = ApplyLayoutByName,
    status = function()
        local installed = PUI.Config.installedVersion
        Utils.Print(PUI, installed
            and ("installed with the " .. tostring(PUI.Config.layout) .. " layout (pack " .. installed .. ")")
            or "not installed yet - run /pui to set up the interface.")

        for _, module in ipairs(PUI.Modules.list) do
            local status = PUI.Modules:Status(module)
            local state = status
            if status == "loaded" and module.role == "display" then
                state = PUI.Modules:IsEnabled(module) and "on" or "off"
            end
            print(string.format("  %-14s %s", module.label, state))
        end
    end,
    reset = function()
        -- Clears only this addon's memory of having installed. Nothing written
        -- into the modules is undone, because undoing it would mean restoring
        -- settings this addon never recorded - and each module already has its
        -- own reset for that.
        PUI.Config.installedVersion = nil
        PUI.Config:Save()
        Utils.Print(PUI, "Installer will offer itself again on your next login. " ..
            "Module settings are untouched - use each module's own reset for those.")
    end,
    help = function()
        Utils.Print(PUI, "Commands:")
        print("  /pui - Open the installer")
        print("  /pui settings - Open the Peavers UI settings page")
        print("  /pui apply <layout> - Apply a layout without the wizard")
        print("  /pui status - What is installed, and what is switched on")
        print("  /pui reset - Offer the installer again at next login")
    end,
})

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

PeaversCommons.Events:Init(addonName, function()
    PUI.Config:Initialize()

    if PUI.ConfigUI and PUI.ConfigUI.Initialize then
        PUI.ConfigUI:Initialize()
    end

    if PUI.Patrons and PUI.Patrons.Initialize then
        PUI.Patrons:Initialize()
    end

    ----------------------------------------------------------------------------
    -- First run
    --
    -- Waits for PLAYER_ENTERING_WORLD and then some. The wizard reads the module
    -- roster as it draws, and the modules register themselves on their own
    -- timers during login - opening any earlier would show a welcome screen
    -- claiming half the pack was missing, which is the worst possible first
    -- impression for an installer whose whole job is to know what you have.
    --
    -- Fires once. A player who closes it without installing is not asked again
    -- until they type /pui, which is the point of the "Not now" button.
    ----------------------------------------------------------------------------
    PeaversCommons.Events:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if PUI.firstRunChecked then return end
        PUI.firstRunChecked = true

        local wants = PUI.Config:NeedsInstall()
            or (PUI.Config.promptOnUpdate and PUI.Config:NeedsUpdate())

        if not wants then return end

        C_Timer.After(3, function()
            -- Not over a loading screen, and not mid-pull. Either is a bad
            -- moment for a modal-looking window to appear over the game.
            if InCombatLockdown() then
                PeaversCommons.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
                    if not PUI.Wizard:IsShown() and PUI.Config:NeedsInstall() then
                        PUI.Wizard:Show()
                    end
                end)
                return
            end

            PUI.Wizard:Show()
        end)
    end)

    -- Use the centralized SettingsUI system from PeaversCommons
    C_Timer.After(0.5, function()
        PeaversCommons.SettingsUI:CreateRedirectPage(PUI, "PeaversUI", "Peavers UI")
    end)

    -- Register with PeaversConfig registry. Order 0 puts the pack at the top of
    -- the sidebar, above the modules it installs, which is the order somebody
    -- reads them in.
    if PeaversCommons.ConfigRegistry then
        PeaversCommons.ConfigRegistry:Register({
            name = "PeaversUI",
            displayName = "UI Pack",
            description = "Install and arrange the whole Peavers interface",
            addonRef = PUI,
            config = PUI.Config,
            pages = PUI.ConfigUI:GetPages(),
            order = 0,
        })
    end
end, {
    suppressAnnouncement = true
})

_G.PeaversUI = PUI
