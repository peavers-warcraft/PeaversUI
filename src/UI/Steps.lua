--------------------------------------------------------------------------------
-- PeaversUI wizard steps
--
-- Five pages, in order: what you have, what you want, how it should look, what
-- to do about graphics, and a summary you have to agree to before anything is
-- written. Each is a table with a title, a Build(page, choices), and optionally
-- an OnNext that can take the footer click for itself.
--
-- The shape of the whole thing follows one rule: nothing is applied until the
-- last step. Ticking boxes and picking layouts only edits the `choices` table,
-- so backing out at any point up to "Install" leaves the game exactly as it was
-- found. That is the difference between an installer and a settings panel, and
-- it is the reason the review page can promise anything at all.
--------------------------------------------------------------------------------

local _, PUI = ...

local Steps = {}
PUI.Steps = Steps

local PeaversCommons = _G.PeaversCommons
local W = PeaversCommons.Widgets
local C = W.Colors

local Modules = PUI.Modules
local Layouts = PUI.Layouts
local Installer = PUI.Installer

--------------------------------------------------------------------------------
-- Shared bits
--------------------------------------------------------------------------------

-- A small status dot. Colour carries the same three states Modules:Status does:
-- running, installed but switched off, absent.
local STATUS_COLOR = {
    loaded   = C.accent,
    disabled = C.amber,
    missing  = C.danger,
}

local STATUS_WORD = {
    loaded   = "ready",
    disabled = "not enabled",
    missing  = "not installed",
}

local function Dot(parent, status)
    local dot = parent:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    local color = STATUS_COLOR[status] or C.textMuted
    dot:SetColorTexture(color[1], color[2], color[3], 1)
    return dot
end

-- A clickable card: a hairline panel that shows which one is chosen by taking
-- the accent border and a filled left edge.
--
-- Used by both the layout and the graphics steps, which want the same control
-- for the same reason: three or four mutually exclusive choices, each needing a
-- sentence of explanation. A dropdown hides the explanations behind a click,
-- and radio buttons have nowhere to put them.
local function SelectCard(parent, opts)
    local card = W:CreatePanel(parent, {
        width = opts.width,
        height = opts.height or 76,
        bg = C.bgNested,
    })

    local edge = card:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMLEFT", 0, 0)
    edge:SetWidth(2)
    edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

    local title = W:CreateLabel(card, opts.title, { color = C.text })
    title:SetPoint("TOPLEFT", 14, -10)

    local tagline
    if opts.tagline then
        tagline = W:CreateLabel(card, opts.tagline, {
            font = "GameFontNormalSmall",
            color = C.accent,
        })
        tagline:SetPoint("LEFT", title, "RIGHT", 8, 0)
    end

    if opts.blurb then
        local blurb = W:CreateLabel(card, opts.blurb, {
            font = "GameFontNormalSmall",
            color = C.textMuted,
            width = (opts.width or 400) - 28,
            wrap = true,
        })
        blurb:SetPoint("TOPLEFT", 14, -30)
    end

    local button = CreateFrame("Button", nil, card)
    button:SetAllPoints()

    function card:SetSelected(selected)
        self.selected = selected and true or false
        if selected then
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            self:SetBackdropColor(C.bgNested[1], C.bgNested[2], C.bgNested[3], 1)
            edge:Show()
            title:SetTextColor(C.text[1], C.text[2], C.text[3])
        else
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            self:SetBackdropColor(C.bgBase[1], C.bgBase[2], C.bgBase[3], 1)
            edge:Hide()
            title:SetTextColor(C.textSec[1], C.textSec[2], C.textSec[3])
        end
    end

    button:SetScript("OnEnter", function()
        if not card.selected then
            card:SetBackdropBorderColor(C.borderHover[1], C.borderHover[2], C.borderHover[3], 1)
        end
    end)
    button:SetScript("OnLeave", function()
        if not card.selected then
            card:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end
    end)
    button:SetScript("OnClick", function()
        if opts.onClick then opts.onClick() end
    end)

    card:SetSelected(false)
    return card
end

--------------------------------------------------------------------------------
-- 1. Welcome - the roster
--------------------------------------------------------------------------------

Steps.list = {}

Steps.list.welcome = {
    title = "Set up your interface",
    subtitle = "Eight addons, one pass. Nothing on this screen or the next three " ..
               "changes anything - the installer only writes when you press Install.",

    Build = function(_, page, _)
        local width = PUI.Wizard:ContentWidth()
        local y = -4

        local _, nextY = W:CreateSectionHeader(page, "What the pack is made of", 0, y, { width = width })
        y = nextY - 4

        local missing = 0

        local function Row(module)
            local status = Modules:Status(module)
            if status ~= "loaded" then missing = missing + 1 end

            local dot = Dot(page, status)
            dot:SetPoint("TOPLEFT", 2, y - 7)

            local label = W:CreateLabel(page, module.label, { color = C.text })
            label:SetPoint("TOPLEFT", 16, y)

            local detail = module.blurb
            if status ~= "loaded" then
                detail = STATUS_WORD[status] .. " - " .. module.blurb
            end

            local text = W:CreateLabel(page, detail, {
                font = "GameFontNormalSmall",
                color = status == "loaded" and C.textMuted or (STATUS_COLOR[status] or C.textMuted),
                width = width - 150,
                wrap = false,
            })
            text:SetPoint("TOPLEFT", 140, y - 1)

            y = y - 25
        end

        for _, module in ipairs(Modules:OfRole("core")) do Row(module) end
        for _, module in ipairs(Modules:OfRole("display")) do Row(module) end
        for _, module in ipairs(Modules:OfRole("system")) do Row(module) end

        y = y - 6
        local _, ruleY = W:CreateSeparator(page, 0, y, width)
        y = ruleY - 4

        local footer
        if missing == 0 then
            footer = "Everything is here. The next three screens ask which parts you " ..
                     "want, how they should be arranged, and what to do about graphics."
        else
            footer = (missing == 1
                        and "One module is not running, and will be skipped. "
                        or (missing .. " modules are not running, and will be skipped. ")) ..
                     "That is not a failure - the pack installs whatever it finds. " ..
                     "PeaversUpdater installs the whole collection in one go, or each " ..
                     "one is on CurseForge separately."
        end

        local note = W:CreateLabel(page, footer, {
            font = "GameFontNormalSmall",
            color = missing == 0 and C.textMuted or (C.amber),
            width = width - 8,
            wrap = true,
        })
        note:SetPoint("TOPLEFT", 0, y)
    end,
}

--------------------------------------------------------------------------------
-- 2. Modules
--------------------------------------------------------------------------------

Steps.list.modules = {
    title = "Choose your modules",
    subtitle = "Everything you have is on. Unticking one switches it off and hands " ..
               "that part of the interface back to Blizzard - it does not uninstall " ..
               "anything, and each module's own settings can turn it back on later.",

    Build = function(_, page, choices)
        local width = PUI.Wizard:ContentWidth()
        local y = -4

        for _, module in ipairs(Modules:OfRole("display")) do
            local available = Modules:IsAvailable(module)

            if available then
                local check = W:CreateCheckbox(page, module.label, {
                    checked = choices.modules[module.key] ~= false,
                    description = module.blurb .. "   " .. (module.slash or ""),
                    width = width - 8,
                    onChange = function(checked)
                        choices.modules[module.key] = checked
                    end,
                })
                check:SetPoint("TOPLEFT", 0, y)
            else
                -- Shown rather than hidden. A module that quietly vanishes from
                -- the list reads as a bug in the pack; one that is listed as
                -- absent reads as a thing you could go and install.
                local status = Modules:Status(module)
                local label = W:CreateLabel(page, module.label, { color = C.textMuted })
                label:SetPoint("TOPLEFT", 24, y - 2)

                local detail = W:CreateLabel(page, STATUS_WORD[status] .. " - nothing to configure", {
                    font = "GameFontNormalSmall",
                    color = C.textMuted,
                    width = width - 32,
                    wrap = true,
                })
                detail:SetPoint("TOPLEFT", 24, y - 20)
            end

            y = y - 44
        end

        y = y - 4
        local _, ruleY = W:CreateSeparator(page, 0, y, width)
        y = ruleY - 4

        local note = W:CreateLabel(page,
            "PeaversPerformance is not in this list because on and off is not the " ..
            "question worth asking about it - it gets a screen of its own two steps " ..
            "from here.", {
            font = "GameFontNormalSmall",
            color = C.textMuted,
            width = width - 8,
            wrap = true,
        })
        note:SetPoint("TOPLEFT", 0, y)
    end,
}

--------------------------------------------------------------------------------
-- 3. Layout
--------------------------------------------------------------------------------

Steps.list.layout = {
    title = "Pick a layout",
    subtitle = "Where things sit and how big they are. Every value a layout sets is " ..
               "an ordinary setting afterwards, so nothing here is a decision you " ..
               "are stuck with.",

    Build = function(_, page, choices)
        local width = PUI.Wizard:ContentWidth()
        local cards = {}
        local y = -2

        local function Select(key)
            choices.layout = key
            for cardKey, card in pairs(cards) do
                card:SetSelected(cardKey == key)
            end

            -- The graphics step takes its starting value from the layout, right
            -- up until the player picks a tier by hand. After that their choice
            -- survives a change of mind about the layout.
            if not choices.graphicsTouched then
                local layout = Layouts:Get(key)
                choices.recommendedGraphics = layout and layout.graphics or nil
                choices.graphicsPreset = choices.recommendedGraphics
            end
        end

        for _, entry in ipairs(Layouts:Sorted()) do
            local card = SelectCard(page, {
                width = width - 4,
                height = 78,
                title = entry.layout.name,
                tagline = entry.layout.tagline,
                blurb = entry.layout.blurb,
                onClick = function() Select(entry.key) end,
            })
            card:SetPoint("TOPLEFT", 0, y)
            cards[entry.key] = card
            y = y - 84
        end

        Select(choices.layout or "standard")
    end,
}

--------------------------------------------------------------------------------
-- 4. Graphics
--------------------------------------------------------------------------------

Steps.list.graphics = {
    title = "Graphics",
    subtitle = "The one step that changes the game rather than the interface. Every " ..
               "console variable is recorded before it is touched, so /pperf restore " ..
               "puts all of it back exactly as it was.",

    Build = function(_, page, choices)
        local width = PUI.Wizard:ContentWidth()
        local options = Installer:GraphicsOptions()

        -- Only "leave it alone" came back, so PeaversPerformance is not running.
        -- Say so plainly instead of showing a one-option chooser.
        if #options == 1 then
            local note = W:CreateLabel(page,
                "PeaversPerformance is not running, so there are no graphics presets " ..
                "to offer. The rest of the pack installs normally, and your graphics " ..
                "settings are left exactly as they are.\n\n" ..
                "If you install it later, /pperf has the same five tiers this step " ..
                "would have shown.", {
                color = C.textMuted,
                width = width - 8,
                wrap = true,
            })
            note:SetPoint("TOPLEFT", 0, -4)
            choices.graphicsPreset = "none"
            return
        end

        if choices.graphicsPreset == nil then
            choices.graphicsPreset = choices.recommendedGraphics or "none"
        end

        local cards = {}
        local y = -2

        local function Select(value, byHand)
            choices.graphicsPreset = value
            if byHand then choices.graphicsTouched = true end
            for cardValue, card in pairs(cards) do
                card:SetSelected(cardValue == value)
            end
        end

        for _, option in ipairs(options) do
            local tagline
            if option.value ~= "none" and option.value == choices.recommendedGraphics then
                local layout = Layouts:Get(choices.layout)
                tagline = "suggested for " .. (layout and layout.name or "this layout")
            end

            local card = SelectCard(page, {
                width = width - 4,
                height = 46,
                title = option.label,
                tagline = tagline,
                blurb = nil,
                onClick = function() Select(option.value, true) end,
            })

            -- A one-line card, so the blurb sits beside the title rather than
            -- under it; six of these have to fit on one screen.
            if option.blurb then
                local blurb = W:CreateLabel(card, option.blurb, {
                    font = "GameFontNormalSmall",
                    color = C.textMuted,
                    width = width - 40,
                    wrap = true,
                })
                blurb:SetPoint("TOPLEFT", 14, -26)
            end

            card:SetPoint("TOPLEFT", 0, y)
            cards[option.value] = card
            y = y - 52
        end

        Select(choices.graphicsPreset, false)
    end,
}

--------------------------------------------------------------------------------
-- 5. Review, then done
--
-- One step wearing two faces. Keeping the result on the same page as the plan
-- is deliberate: the summary you agreed to and the report of what happened line
-- up row for row, so a module that was skipped is obvious rather than buried in
-- a chat message that has already scrolled away.
--------------------------------------------------------------------------------

Steps.list.review = {
    title = "Ready to install",
    nextLabel = "Install",

    Build = function(self, page, choices)
        local width = PUI.Wizard:ContentWidth()

        if self.result then
            self:BuildResult(page)
            return
        end

        self.title = "Ready to install"
        self.subtitle = "This is everything that will change. Nothing outside this " ..
                        "list is touched - your keybinds, action bars and Edit Mode " ..
                        "layout are left alone."
        self.nextLabel = "Install"
        self.skipLabel = "Not now"
        self.hideBack = false

        local y = -4
        local _, nextY = W:CreateSectionHeader(page, "Summary", 0, y, { width = width })
        y = nextY - 2

        for _, line in ipairs(Installer:Preview(choices)) do
            local dot = Dot(page, line.ok and "loaded" or "missing")
            dot:SetPoint("TOPLEFT", 2, y - 7)

            local label = W:CreateLabel(page, line.label, { color = C.text })
            label:SetPoint("TOPLEFT", 16, y)

            local detail = W:CreateLabel(page, line.detail, {
                font = "GameFontNormalSmall",
                color = C.textMuted,
                width = width - 150,
                wrap = false,
            })
            detail:SetPoint("TOPLEFT", 140, y - 1)

            y = y - 25
        end

        y = y - 6
        local _, ruleY = W:CreateSeparator(page, 0, y, width)
        y = ruleY - 4

        local note = W:CreateLabel(page,
            "Everything written here lands in each module's own saved settings, " ..
            "where its settings page can edit it afterwards. Run the installer " ..
            "again from /pui at any time to start over.", {
            font = "GameFontNormalSmall",
            color = C.textMuted,
            width = width - 8,
            wrap = true,
        })
        note:SetPoint("TOPLEFT", 0, y)
    end,

    BuildResult = function(self, page)
        local width = PUI.Wizard:ContentWidth()
        local result = self.result

        self.title = "Installed"
        self.subtitle = "Most of it is already on screen. A reload settles the few " ..
                        "settings the game only reads at login."
        self.nextLabel = "Reload UI"
        self.skipLabel = "Close"
        self.hideBack = true

        local y = -4
        local _, nextY = W:CreateSectionHeader(page, "What happened", 0, y, { width = width })
        y = nextY - 2

        local function Line(text, color)
            local label = W:CreateLabel(page, text, {
                font = "GameFontNormalSmall",
                color = color or C.textMuted,
                width = width - 8,
                wrap = true,
            })
            label:SetPoint("TOPLEFT", 2, y)
            y = y - 20
        end

        if #result.applied > 0 then
            Line("Configured: " .. table.concat(result.applied, ", "), C.text)
        end
        if #result.disabled > 0 then
            Line("Switched off, at your request: " .. table.concat(result.disabled, ", "))
        end
        if #result.skipped > 0 then
            Line("Skipped, not installed: " .. table.concat(result.skipped, ", "))
        end
        if #result.failures > 0 then
            for _, failure in ipairs(result.failures) do
                Line("Failed: " .. failure, C.danger)
            end
        else
            Line("No errors.")
        end

        y = y - 8
        local _, ruleY = W:CreateSeparator(page, 0, y, width)
        y = ruleY - 6

        local settings = W:CreateButton(page, "Open settings", {
            variant = "secondary",
            width = 140,
            onClick = function()
                PUI.Wizard:Hide()
                if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
                    _G.PeaversConfig.MainFrame:Show()
                end
            end,
        })
        settings:SetPoint("TOPLEFT", 0, y)

        local hint = W:CreateLabel(page,
            "Every module keeps its own page in there, and /peavers opens it any time.\n\n" ..
            "If any of it is not to your taste, change it there rather than reinstalling - " ..
            "the pack only ever wrote ordinary settings.", {
            font = "GameFontNormalSmall",
            color = C.textMuted,
            width = width - 160,
            wrap = true,
        })
        hint:SetPoint("TOPLEFT", 152, y - 2)
    end,

    OnNext = function(self, choices)
        if self.result then
            ReloadUI()
            return true
        end

        self.result = Installer:Apply(choices)
        PUI.Wizard:Render()
        return true
    end,
}

-- The rail draws one dot per entry, so this is also the length of the wizard.
Steps.order = { "welcome", "modules", "layout", "graphics", "review" }

-- The review step carries its own result between renders, which would otherwise
-- survive into the next run and show a stale report. Cleared whenever the
-- wizard opens.
function Steps:Reset()
    self.list.review.result = nil
end

return Steps
