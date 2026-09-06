--------------------------------------------------------------------------------
-- PeaversUI settings pages
--
-- The pack's page inside PeaversConfig. Deliberately thin: this addon owns
-- almost no settings of its own, so the page's job is to say what is currently
-- installed, reopen the installer, and apply a layout without walking the whole
-- wizard again for somebody who only wants to try a different one.
--
-- Everything here is a shortcut to something the wizard already does. There is
-- no second implementation of the install, and no setting that can only be
-- reached from one of the two places.
--------------------------------------------------------------------------------

local _, PUI = ...

local ConfigUI = {}
PUI.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local W = PeaversCommons.Widgets
local C = W.Colors

local Modules = PUI.Modules
local Layouts = PUI.Layouts
local Installer = PUI.Installer

local INDENT = 25

local function ResolveWidth(parentFrame)
    local parentWidth = parentFrame:GetWidth() or 0
    if parentWidth > 100 then
        return parentWidth - (INDENT * 2) - 10
    end
    return 360
end

--------------------------------------------------------------------------------
-- Overview
--------------------------------------------------------------------------------

function ConfigUI:BuildOverviewPage(parentFrame)
    local width = ResolveWidth(parentFrame)
    local y = -10

    local _, nextY = W:CreateSectionHeader(parentFrame, "Peavers UI", INDENT, y)
    y = nextY - 6

    local installed = PUI.Config.installedVersion
    local layout = Layouts:Get(PUI.Config.layout)

    local summary
    if not installed then
        summary = "The installer has not been run on this account yet. " ..
                  "It walks through which modules you want, how they should be " ..
                  "arranged, and what to do about graphics - and writes nothing " ..
                  "until the last screen."
    else
        summary = "Installed with the " .. (layout and layout.name or PUI.Config.layout) ..
                  " layout" ..
                  (PUI.Config.graphicsPreset and PUI.Config.graphicsPreset ~= "none"
                      and (", graphics preset " .. PUI.Config.graphicsPreset) or "") ..
                  ". Every value it wrote is an ordinary setting in the module's own " ..
                  "page, so change anything you like there rather than reinstalling."
    end

    local text = W:CreateLabel(parentFrame, summary, {
        font = "GameFontNormalSmall",
        color = C.textMuted,
        width = width,
        wrap = true,
    })
    text:SetPoint("TOPLEFT", INDENT, y)
    y = y - 56

    local run = W:CreateButton(parentFrame, installed and "Run the installer again" or "Run the installer", {
        variant = "primary",
        width = 200,
        onClick = function()
            if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
                _G.PeaversConfig.MainFrame:Hide()
            end
            PUI.Wizard:Show()
        end,
    })
    run:SetPoint("TOPLEFT", INDENT, y)
    y = y - 42

    local _, ruleY = W:CreateSeparator(parentFrame, INDENT, y, width)
    y = ruleY - 6

    ----------------------------------------------------------------------------
    -- Module roster
    ----------------------------------------------------------------------------
    local _, rosterY = W:CreateSectionHeader(parentFrame, "Modules", INDENT, y)
    y = rosterY - 4

    local function Row(module)
        local status = Modules:Status(module)
        local enabled = status == "loaded" and Modules:IsEnabled(module)

        local state
        if status ~= "loaded" then
            state = status == "disabled" and "not enabled at the character screen" or "not installed"
        elseif module.role ~= "display" then
            state = "running"
        else
            state = enabled and "on" or "off"
        end

        local label = W:CreateLabel(parentFrame, module.label, { color = C.text })
        label:SetPoint("TOPLEFT", INDENT, y)

        local detail = W:CreateLabel(parentFrame, state .. (module.slash and ("   " .. module.slash) or ""), {
            font = "GameFontNormalSmall",
            color = status == "loaded" and C.textMuted or C.amber,
        })
        detail:SetPoint("TOPLEFT", INDENT + 150, y - 1)

        y = y - 22
    end

    for _, module in ipairs(Modules:OfRole("core")) do Row(module) end
    for _, module in ipairs(Modules:OfRole("display")) do Row(module) end
    for _, module in ipairs(Modules:OfRole("system")) do Row(module) end

    y = y - 10
    local promptToggle = W:CreateCheckbox(parentFrame, "Offer the installer again when the pack updates", {
        checked = PUI.Config.promptOnUpdate == true,
        description = "Off by default. An installer that reopens itself uninvited is " ..
                      "the thing people dislike about installers.",
        width = width,
        onChange = function(checked)
            PUI.Config.promptOnUpdate = checked
            PUI.Config:Save()
        end,
    })
    promptToggle:SetPoint("TOPLEFT", INDENT, y)
end

--------------------------------------------------------------------------------
-- Layouts
--
-- Applying a layout from here skips the module and graphics questions on
-- purpose: those are decisions about what you have installed and what your
-- machine can do, and neither of them changes because you fancied a different
-- arrangement of frames.
--------------------------------------------------------------------------------

function ConfigUI:BuildLayoutPage(parentFrame)
    local width = ResolveWidth(parentFrame)
    local y = -10

    local _, nextY = W:CreateSectionHeader(parentFrame, "Layouts", INDENT, y)
    y = nextY - 4

    local intro = W:CreateLabel(parentFrame,
        "Applying a layout rewrites position, size and text settings across the " ..
        "modules you have switched on. It does not touch your module choices or " ..
        "your graphics settings - those keep whatever the installer left them at.", {
        font = "GameFontNormalSmall",
        color = C.textMuted,
        width = width,
        wrap = true,
    })
    intro:SetPoint("TOPLEFT", INDENT, y)
    y = y - 48

    for _, entry in ipairs(Layouts:Sorted()) do
        local isCurrent = (PUI.Config.layout == entry.key)

        local name = W:CreateLabel(parentFrame,
            entry.layout.name .. (isCurrent and "  (current)" or ""), {
            color = isCurrent and C.accent or C.text,
        })
        name:SetPoint("TOPLEFT", INDENT, y)

        local apply = W:CreateButton(parentFrame, "Apply", {
            variant = "secondary",
            width = 80,
            onClick = function()
                local choices = Installer:NewChoices(entry.key)

                -- Keep what is already on, rather than the roster of what is
                -- installed: someone who switched chat off in step two should
                -- not have it come back because they tried another layout.
                for _, module in ipairs(Modules:OfRole("display")) do
                    choices.modules[module.key] = Modules:IsAvailable(module)
                        and Modules:IsEnabled(module)
                        or false
                end

                choices.graphicsPreset = "none"
                Installer:Apply(choices)

                PeaversCommons.Utils.Print(PUI, entry.layout.name .. " layout applied.")
                ConfigUI:OpenOptions()
            end,
        })
        apply:SetPoint("TOPLEFT", INDENT + 150, y - 4)

        local blurb = W:CreateLabel(parentFrame, entry.layout.blurb, {
            font = "GameFontNormalSmall",
            color = C.textMuted,
            width = width,
            wrap = true,
        })
        blurb:SetPoint("TOPLEFT", INDENT, y - 20)

        y = y - 66
    end
end

--------------------------------------------------------------------------------

function ConfigUI:GetPages()
    return {
        { key = "overview", label = "Overview", builder = function(f) ConfigUI:BuildOverviewPage(f) end },
        { key = "layouts", label = "Layouts", builder = function(f) ConfigUI:BuildLayoutPage(f) end },
    }
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildOverviewPage(parentFrame)
    return parentFrame
end

function ConfigUI:OpenOptions()
    if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
        _G.PeaversConfig.MainFrame:Show()
        _G.PeaversConfig.MainFrame:SelectAddon("PeaversUI")
        return
    end

    if Settings and Settings.OpenToCategory then
        if PUI.directSettingsCategoryID then
            local success = pcall(Settings.OpenToCategory, PUI.directSettingsCategoryID)
            if success then return end
        end
        if PUI.directCategoryID then
            local success = pcall(Settings.OpenToCategory, PUI.directCategoryID)
            if success then return end
        end
    end

    if SettingsPanel then
        SettingsPanel:Open()
    end
end

function ConfigUI:Initialize()
end

return ConfigUI
