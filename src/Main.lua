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

    -- The arrangement and nothing else: modules stay as switched on, nothing is
    -- reset first, and graphics are never touched from a slash command.
    -- Versioning:ChoicesFor is the one definition of that, shared with the
    -- settings page and layout updates.
    local result = PUI.Installer:Apply(PUI.Versioning:ChoicesFor(key))

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
    extras = function()
        PUI.ConfigUI:OpenOptions("extras")
    end,
    share = function(rest)
        local arg = tostring(rest or ""):trim():lower()

        -- The author's half: everything captured, as the exact block of Lua that
        -- goes into src/Core/Extras.lua. One command, one copy, one paste.
        if arg == "lua" then
            local lua = PUI.Harvest:AsLua()
            if not lua then
                Utils.Print(PUI, "Nothing captured yet - run /pui share first.")
                return
            end
            PUI.CopyBox:Show("Profiles as Lua", lua,
                "Paste each block into its entry in src/Core/Extras.lua to ship it.")
            return
        end

        if arg == "clear" then
            PUI.Harvest:Clear()
            Utils.Print(PUI, "Captured profiles forgotten. Anything shipped with the " ..
                "pack is untouched.")
            return
        end

        local result = PUI.Harvest:CaptureAll()
        Utils.Print(PUI, #result.captured .. " profile(s) captured from your own addons:")
        for _, item in ipairs(result.captured) do
            print(("  |cff4ade80%s|r  %d characters"):format(item.key, item.bytes))
        end
        for _, skip in ipairs(result.skipped) do
            print(("  |cff949494%s: %s|r"):format(skip.key, skip.reason))
        end
        print("  /pui extras shows them. /pui share lua gives you the block for " ..
            "src/Core/Extras.lua.")
    end,
    config = function()
        PUI.ConfigUI:OpenOptions()
    end,
    apply = ApplyLayoutByName,
    layout = ApplyLayoutByName,
    preview = function(rest)
        local key = rest and rest:trim():lower() or ""
        if key == "" then key = PUI.Config.layout or PUI.Layouts.DEFAULT end

        local ok, reason = PUI.Preview:Start(key, PUI.Installer:NewChoices(key))
        if ok then
            local layout = PUI.Layouts:Get(key)
            Utils.Print(PUI, "Previewing " .. (layout and layout.name or key) ..
                ". /pui undo puts your settings back, /pui keep makes it stick.")
        else
            Utils.Print(PUI, reason or "Could not preview that layout.")
        end
    end,
    undo = function()
        -- A preview in progress first, then the last layout update: the two
        -- things the pack can have changed that somebody might want back.
        if PUI.Preview:Revert() then
            Utils.Print(PUI, "Preview undone - your settings are back as they were.")
            return
        end
        local ok, reason = PUI.Versioning:Undo()
        if not ok then
            Utils.Print(PUI, reason or "Nothing to undo.")
        end
    end,
    follow = function()
        local ok, reason = PUI.Versioning:Follow()
        if not ok and reason then Utils.Print(PUI, reason) end
    end,
    pin = function()
        PUI.Versioning:SetTrack(PUI.Versioning.PINNED)
        Utils.Print(PUI, "Pinned. Pack updates will not change your layout; " ..
            "/pui update applies a newer one whenever you want it.")
    end,
    update = function()
        local ok, reason = PUI.Versioning:ApplyLatest()
        if not ok and reason then Utils.Print(PUI, reason) end
    end,
    keep = function()
        -- Also the answer to the login message: it clears the outstanding
        -- restore without touching anything on screen.
        if PUI.Preview:Keep() or PUI.Config.previewRestore then
            PUI.Config.previewRestore = nil
            PUI.Config:Save()
            Utils.Print(PUI, "Kept. The previewed layout is now just your settings.")
        else
            Utils.Print(PUI, "Nothing being previewed.")
        end
    end,
    status = function()
        local installed = PUI.Config.installedVersion
        Utils.Print(PUI, installed
            and ("installed with the " .. tostring(PUI.Config.layout) .. " layout (pack " .. installed .. ")")
            or "not installed yet - run /pui to set up the interface.")

        local version = PUI.Versioning:Status()
        if version.installed and version.name then
            print(("  layout revision %s of %d, %s"):format(tostring(version.revision or "?"),
                version.latest, version.track == PUI.Versioning.LATEST
                    and "following the latest (/pui pin to stop)"
                    or "pinned (/pui follow to keep it up to date)"))
        end

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
        print("  /pui extras - Addons this pack works alongside")
        print("  /pui share - Capture your own profiles from those addons")
        print("  /pui share lua - Those profiles as Lua, ready for Extras.lua")
        print("  /pui apply <layout> - Apply a layout without the wizard")
        print("  /pui preview <layout> - Put a layout on screen to look at")
        print("  /pui undo - Put your settings back after a preview or a layout update")
        print("  /pui follow - Keep your layout up to date with pack updates")
        print("  /pui pin - Stop pack updates changing your layout (the default)")
        print("  /pui update - Apply the newest revision of your layout once")
        print("  /pui keep - Stop treating a previewed layout as temporary")
        print("  /pui status - What is installed, and what is switched on")
        print("  /pui reset - Offer the installer again at next login")
    end,
})

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

PeaversCommons.Events:Init(addonName, function()
    PUI.Config:Initialize()

    -- Installs from before layouts had revisions are pinned to the one they
    -- have, before anything below gets to look at them.
    PUI.Versioning:Migrate()

    -- And installs on a layout that has since been retired are pointed at its
    -- replacement and pinned, so nothing further down is reasoning about a key
    -- that no longer names anything.
    PUI.Versioning:MigrateRetired()

    -- The only thing the pack ever applies at login, and only for an account
    -- that chose to follow the latest layout. Never over a loading screen and
    -- never mid-pull: in combat it waits for the fight to end.
    local function ApplyLayoutUpdate()
        if not PUI.Versioning:UpdateDue() then return end
        if InCombatLockdown() then
            PeaversCommons.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
                if PUI.Versioning:UpdateDue() and not InCombatLockdown() then
                    PUI.Versioning:ApplyLatest()
                end
            end)
            return
        end
        PUI.Versioning:ApplyLatest()
    end

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

        -- A restore left on disk means the last session ended mid-preview. Said
        -- out loud rather than acted on: waking up to a UI that rearranged
        -- itself while you were reading the login screen is the exact surprise
        -- the preview design exists to avoid.
        if PUI.Preview:AnnouncePending() then
            return
        end

        -- Once, for installs made before layouts had revisions. Delayed past
        -- the wall of login messages it would otherwise scroll away under.
        if PUI.Versioning:NoticeDue() then
            C_Timer.After(6, function()
                if PUI.Versioning:NoticeDue() then PUI.Versioning:ShowNotice() end
            end)
        end

        -- Once, for an account whose layout was retired. Said rather than shown,
        -- and said plainly: nothing on their screen has changed, and the only
        -- reason they are hearing about it at all is so the different name on the
        -- settings page is not a mystery.
        local retired = PUI.Versioning:RetiredNotice()
        if retired then
            C_Timer.After(8, function()
                local from, now = PUI.Versioning:RetiredNotice()
                if not from then return end
                Utils.Print(PUI, "the " .. from .. " layout has been retired. Your " ..
                    "interface is untouched and stays exactly as it is; the pack now " ..
                    "lists it as " .. now .. ", and /pui lets you pick again.")
                PUI.Versioning:ClearRetiredNotice()
            end)
        end

        if PUI.Versioning:UpdateDue() then
            C_Timer.After(3, ApplyLayoutUpdate)
            return
        end

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
