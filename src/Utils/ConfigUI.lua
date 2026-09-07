--------------------------------------------------------------------------------
-- PeaversUI settings pages
--
-- The pack's pages inside PeaversConfig. Deliberately thin: this addon owns
-- almost no settings of its own, so their job is to say what is installed,
-- reopen the installer, switch layout, and point at the things the pack does not
-- ship.
--
-- LAYOUT RULES, because the first version of this file broke all three and
-- looked it:
--
-- 1. EVERY PAGE SETS ITS OWN HEIGHT AT THE END. PeaversConfig creates the panel
--    one pixel tall and hands it to the builder; the builder is what tells the
--    scroll frame how much there is. Without it the page is a one-pixel scroll
--    child - content past the fold is unreachable and everything looks jammed
--    into the top. Every other addon in the collection does this and this one
--    did not.
--
-- 2. NEVER ADVANCE PAST A WRAPPING LABEL BY A FIXED NUMBER. A paragraph's height
--    depends on the width it was given and the words in it, so `y = y - 56`
--    after one is a guess that is wrong the moment somebody edits the sentence -
--    and being wrong means the next widget is drawn on top of it. Paragraph()
--    below measures instead.
--
-- 3. THE ACTION COLUMN IS MEASURED FROM THE RIGHT. PeaversConfig is resizable
--    and not wide by default; a button pinned at INDENT + 300 with a width of
--    120 needs 420 pixels of row and runs off the panel on anything narrower.
--
-- perf/cases/pages.lua builds all three pages against recording stubs and
-- asserts each of those, because none of them throw - they just render badly.
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

--------------------------------------------------------------------------------
-- The grid
--------------------------------------------------------------------------------

local INDENT = 25

local COL_STATUS = 190
local ACTION_WIDTH = 120
local COL_STATUS_MIN_GAP = 12

-- Vertical rhythm, named so the gaps are consistent rather than whatever number
-- was in the author's head at the time.
local GAP_TIGHT = 6      -- between a heading and the thing under it
local GAP_ROW = 10       -- between rows in a list
local GAP_SECTION = 18   -- between one section and the next
local ROW_HEIGHT = 22    -- a single line of label

-- x for the action column, given the usable content width. Right-aligned, so
-- the buttons line up with each other and with the panel edge at every window
-- width - which is what "aligned" has to mean in a window somebody can drag.
local function ActionX(width)
    return math.max(COL_STATUS + COL_STATUS_MIN_GAP, width - ACTION_WIDTH)
end

local function ResolveWidth(parentFrame)
    local parentWidth = parentFrame:GetWidth() or 0
    if parentWidth > 100 then
        return parentWidth - (INDENT * 2) - 10
    end
    return 360
end

--- A wrapping block of body text, measured.
--- @return number nextY  the y to carry on from, below the text
local function Paragraph(parent, text, y, width, opts)
    opts = opts or {}

    local label = W:CreateLabel(parent, text, {
        font = opts.font or "GameFontNormalSmall",
        color = opts.color or C.textMuted,
        width = width,
        wrap = true,
    })
    label:SetPoint("TOPLEFT", opts.x or INDENT, y)

    -- GetStringHeight is the wrapped height once the text and a width are set.
    -- The fallback matters: a font string the client has not laid out yet can
    -- report 0, and a 0 here would stack the next widget straight on top.
    local height = label:GetStringHeight() or 0
    if height < 1 then height = 14 end

    return y - height - (opts.gap or GAP_TIGHT), label
end

--- Close a page off. Call it last, always.
local function Finish(parentFrame, y)
    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Overview
--------------------------------------------------------------------------------

function ConfigUI:BuildOverviewPage(parentFrame)
    local width = ResolveWidth(parentFrame)
    local y = -10

    local _, nextY = W:CreateSectionHeader(parentFrame, "Peavers UI", INDENT, y)
    y = nextY - GAP_TIGHT

    local installed = PUI.Config.installedVersion
    local layout = Layouts:Get(PUI.Config.layout)

    local summary
    if not installed then
        summary = "The installer has not been run on this account yet. It walks " ..
                  "through which modules you want, how they should be arranged, " ..
                  "and what to do about graphics."
    else
        summary = "Installed with the " .. (layout and layout.name or PUI.Config.layout) ..
                  " layout" ..
                  (PUI.Config.graphicsPreset and PUI.Config.graphicsPreset ~= "none"
                      and (", graphics preset " .. PUI.Config.graphicsPreset) or "") ..
                  ". Everything it wrote is an ordinary setting in the module's own " ..
                  "page, so change what you like there rather than reinstalling."
    end

    y = Paragraph(parentFrame, summary, y, width, { gap = GAP_ROW })

    local run = W:CreateButton(parentFrame,
        installed and "Run the installer again" or "Run the installer", {
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
    y = y - 26 - GAP_SECTION

    ----------------------------------------------------------------------------
    -- Module roster
    ----------------------------------------------------------------------------
    local _, rosterY = W:CreateSectionHeader(parentFrame, "Modules", INDENT, y)
    y = rosterY - GAP_TIGHT

    local function Row(module)
        local status = Modules:Status(module)
        local enabled = status == "loaded" and Modules:IsEnabled(module)

        local state, color
        if status ~= "loaded" then
            state = status == "disabled" and "not enabled" or "not installed"
            color = C.amber
        elseif module.role ~= "display" then
            state = "running"
            color = C.textMuted
        else
            state = enabled and "on" or "off"
            color = enabled and C.accent or C.textMuted
        end

        local label = W:CreateLabel(parentFrame, module.label, { color = C.text })
        label:SetPoint("TOPLEFT", INDENT, y)

        local detail = W:CreateLabel(parentFrame, state, {
            font = "GameFontNormalSmall",
            color = color,
        })
        detail:SetPoint("TOPLEFT", INDENT + COL_STATUS, y - 1)

        if module.slash then
            local slash = W:CreateLabel(parentFrame, module.slash, {
                font = "GameFontNormalSmall",
                color = C.textMuted,
            })
            slash:SetPoint("TOPLEFT", INDENT + ActionX(width), y - 1)
        end

        y = y - ROW_HEIGHT
    end

    for _, module in ipairs(Modules:OfRole("core")) do Row(module) end
    for _, module in ipairs(Modules:OfRole("display")) do Row(module) end
    for _, module in ipairs(Modules:OfRole("system")) do Row(module) end

    y = y - GAP_SECTION

    local promptToggle = W:CreateCheckbox(parentFrame,
        "Offer the installer again when the pack updates", {
        checked = PUI.Config.promptOnUpdate == true,
        description = "Off by default. An installer that reopens itself uninvited " ..
                      "is the thing people dislike about installers.",
        width = width,
        onChange = function(checked)
            PUI.Config.promptOnUpdate = checked
            PUI.Config:Save()
        end,
    })
    promptToggle:SetPoint("TOPLEFT", INDENT, y)
    -- A checkbox with a description is 36 tall, not 22.
    y = y - 40

    Finish(parentFrame, y)
end

--------------------------------------------------------------------------------
-- Layouts
--
-- Applying from here skips the module and graphics questions on purpose: those
-- are decisions about what you have installed and what your machine can do, and
-- neither changes because you fancied a different arrangement of frames.
--------------------------------------------------------------------------------

function ConfigUI:BuildLayoutPage(parentFrame)
    local width = ResolveWidth(parentFrame)
    local y = -10

    local _, nextY = W:CreateSectionHeader(parentFrame, "Layouts", INDENT, y)
    y = nextY - GAP_TIGHT

    y = Paragraph(parentFrame,
        "Applying a layout rewrites position, size and text settings across the " ..
        "modules you have switched on. It does not touch your module choices or " ..
        "your graphics settings.", y, width, { gap = GAP_SECTION })

    for _, entry in ipairs(Layouts:Sorted()) do
        local isCurrent = (PUI.Config.layout == entry.key)

        local name = W:CreateLabel(parentFrame,
            entry.layout.name .. (isCurrent and "  (current)" or ""), {
            color = isCurrent and C.accent or C.text,
        })
        name:SetPoint("TOPLEFT", INDENT, y)

        local apply = W:CreateButton(parentFrame, isCurrent and "Reapply" or "Apply", {
            variant = "secondary",
            width = ACTION_WIDTH,
            height = 22,
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

                -- Graphics were never asked about on this path, so the plan is
                -- dropped rather than passed as "none": passing it would count
                -- as an answer and switch an existing auto-switch setup off.
                choices.autoSwitch = nil
                choices.graphicsPreset = "none"
                Installer:Apply(choices)

                PeaversCommons.Utils.Print(PUI, entry.layout.name .. " layout applied.")
                ConfigUI:OpenOptions("layouts")
            end,
        })
        apply:SetPoint("TOPLEFT", INDENT + ActionX(width), y - 2)

        y = y - ROW_HEIGHT
        y = Paragraph(parentFrame, entry.layout.blurb, y, width, { gap = GAP_SECTION })
    end

    Finish(parentFrame, y)
end

--------------------------------------------------------------------------------
-- More stuff
--
-- Addons the pack does not ship but works well alongside, and where one has been
-- shared, the profile string that sets it up the way the pack's author runs it.
--
-- Deliberately a page rather than a wizard step. Nothing here is part of
-- installing the interface, none of it can be done by the pack on the player's
-- behalf, and a screen in the middle of a five-screen wizard saying "here is
-- some other software you might like" is an advert. As a page somebody opens on
-- purpose it is a recommendation.
--------------------------------------------------------------------------------

local EXTRA_STATUS = {
    loaded   = { text = "installed", color = C.accent },
    disabled = { text = "not enabled", color = C.amber },
    missing  = { text = "not installed", color = C.textMuted },
}

function ConfigUI:BuildExtrasPage(parentFrame)
    local Extras = PUI.Extras
    local width = ResolveWidth(parentFrame)
    local y = -10

    local _, nextY = W:CreateSectionHeader(parentFrame, "More stuff", INDENT, y)
    y = nextY - GAP_TIGHT

    local installed, total = Extras:CountInstalled()

    y = Paragraph(parentFrame,
        "None of this is part of the pack and none of it is needed. It is what " ..
        "the author runs alongside it, in the places this collection deliberately " ..
        "leaves alone - group frames, nameplates, action bars, boss timers. You " ..
        "have " .. installed .. " of these " .. total .. ".", y, width, { gap = GAP_ROW })

    y = Paragraph(parentFrame,
        "Where a profile has been shared the button copies a string to paste into " ..
        "that addon's own import box. The pack never writes into another addon's " ..
        "settings: its own import understands its own format, has its own undo, " ..
        "and fails safely when a string is out of date.",
        y, width, { gap = GAP_SECTION })

    for _, category in ipairs(Extras.categories) do
        local entries = Extras:OfCategory(category)
        if #entries > 0 then
            local _, catY = W:CreateSectionHeader(parentFrame,
                Extras.categoryNames[category] or category, INDENT, y)
            y = catY - GAP_TIGHT

            for _, entry in ipairs(entries) do
                local badge = EXTRA_STATUS[Extras:Status(entry)] or EXTRA_STATUS.missing

                local name = W:CreateLabel(parentFrame, entry.name, { color = C.text })
                name:SetPoint("TOPLEFT", INDENT, y)

                local state = W:CreateLabel(parentFrame, badge.text, {
                    font = "GameFontNormalSmall",
                    color = badge.color,
                })
                state:SetPoint("TOPLEFT", INDENT + COL_STATUS, y - 1)

                if Extras:HasProfile(entry) then
                    local copy = W:CreateButton(parentFrame, "Copy profile", {
                        variant = "secondary",
                        width = ACTION_WIDTH,
                        height = 22,
                        onClick = function()
                            PUI.CopyBox:Show(
                                entry.name .. " profile",
                                entry.profile.text,
                                (entry.profile.how or "") ..
                                    "  The string is selected already - Ctrl+C.")
                        end,
                    })
                    copy:SetPoint("TOPLEFT", INDENT + ActionX(width), y - 2)
                end

                y = y - ROW_HEIGHT

                local detail = entry.blurb .. "  " .. entry.why
                if not Extras:HasProfile(entry) and entry.profile and entry.profile.how then
                    detail = detail .. "  No profile shared yet; its own settings are at "
                        .. entry.profile.how
                end
                y = Paragraph(parentFrame, detail, y, width, { gap = GAP_TIGHT })

                if entry.url then
                    y = Paragraph(parentFrame, entry.url, y, width,
                        { color = C.textSec, gap = GAP_ROW })
                else
                    y = y - GAP_TIGHT
                end
            end

            y = y - GAP_ROW
        end
    end

    Finish(parentFrame, y)
end

--------------------------------------------------------------------------------

function ConfigUI:GetPages()
    return {
        { key = "overview", label = "Overview", builder = function(f) ConfigUI:BuildOverviewPage(f) end },
        { key = "layouts", label = "Layouts", builder = function(f) ConfigUI:BuildLayoutPage(f) end },
        { key = "extras", label = "More stuff", builder = function(f) ConfigUI:BuildExtrasPage(f) end },
    }
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildOverviewPage(parentFrame)
    return parentFrame
end

--- Open the pack's settings.
--- @param pageKey? string One of GetPages()' keys, to land on directly.
function ConfigUI:OpenOptions(pageKey)
    if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
        _G.PeaversConfig.MainFrame:Show()
        _G.PeaversConfig.MainFrame:SelectAddon("PeaversUI")

        -- Landing on a named page is a nicety, and PeaversConfig owns whether it
        -- is possible - so it is attempted through its own tab API and quietly
        -- skipped if that is not there. Worst case somebody arrives on the
        -- Overview and clicks one tab.
        if pageKey then
            local content = _G.PeaversConfig.ContentArea
            local registry = _G.PeaversCommons and _G.PeaversCommons.ConfigRegistry
            local info = registry and registry:GetAddon("PeaversUI")
            if content and info and type(content.ShowTabPage) == "function" then
                pcall(content.ShowTabPage, content, "PeaversUI", info, pageKey)
            end
        end
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
