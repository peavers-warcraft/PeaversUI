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
    subtitle = "Eight addons, one pass. On the layout screen your interface " ..
               "changes as you click, so you can see what you are choosing - and " ..
               "closing the installer without finishing puts it all back.",

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
    subtitle = "Click one and your interface changes to it, right now, so you can " ..
               "look at the thing itself rather than a description of it. Nothing " ..
               "is committed - closing the installer puts everything back.",

    Build = function(_, page, choices)
        local width = PUI.Wizard:ContentWidth()
        local cards = {}
        local status

        ------------------------------------------------------------------------
        -- Clicking a card applies it
        --
        -- This is the whole design of the screen. A picture of a layout - even a
        -- good one - answers a question nobody actually has; what people want to
        -- know is whether their own screen looks right with it, and the only
        -- thing that answers that is their own screen.
        --
        -- Preview:Start reverts whatever is already being previewed before it
        -- captures, so clicking through all four in a row never compounds: every
        -- snapshot is taken against the settings the player walked in with.
        ------------------------------------------------------------------------
        local function Select(key, applyIt)
            choices.layout = key
            for cardKey, card in pairs(cards) do
                card:SetSelected(cardKey == key)
            end

            -- The graphics step takes its starting values from the layout, right
            -- up until the player edits them by hand. After that their choices
            -- survive a change of mind about the layout. The baseline and the
            -- auto-switch plan track that independently, so tweaking one context
            -- does not freeze the other.
            if not choices.graphicsTouched then
                local layout = Layouts:Get(key)
                choices.recommendedGraphics = layout and layout.graphics or nil
                choices.graphicsPreset = choices.recommendedGraphics
            end

            if not choices.autoSwitchTouched then
                choices.autoSwitch = Layouts:AutoSwitchFor(key)
            end

            if not applyIt then return end

            local ok, reason = PUI.Preview:Start(key, choices)
            if status then
                if ok then
                    local layout = Layouts:Get(key)
                    status:SetText("On screen now: " .. (layout and layout.name or key) ..
                        ". Hide the installer to see it properly.")
                    status:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
                else
                    -- Combat, almost always. Selecting still works; it just does
                    -- not take effect until the fight is over, which is better
                    -- than refusing the click and saying nothing.
                    status:SetText(reason or "Could not switch to that layout right now.")
                    status:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
                end
            end
        end

        ------------------------------------------------------------------------
        -- The four layouts
        ------------------------------------------------------------------------
        local y = -2
        for _, entry in ipairs(Layouts:Sorted()) do
            local card = SelectCard(page, {
                width = width - 4,
                height = 76,
                title = entry.layout.name,
                tagline = entry.layout.tagline,
                blurb = entry.layout.blurb,
                onClick = function() Select(entry.key, true) end,
            })
            card:SetPoint("TOPLEFT", 0, y)
            cards[entry.key] = card
            y = y - 82
        end

        y = y - 6
        local _, ruleY = W:CreateSeparator(page, 0, y, width)
        y = ruleY - 6

        ------------------------------------------------------------------------
        -- Getting the window out of the way
        ------------------------------------------------------------------------
        local hide = W:CreateButton(page, "Hide the installer and look", {
            variant = "secondary",
            width = 200,
            onClick = function()
                PUI.Wizard:EnterPreview(choices.layout)
            end,
        })
        hide:SetPoint("TOPLEFT", 0, y)

        status = W:CreateLabel(page, "", {
            font = "GameFontNormalSmall",
            color = C.textMuted,
            width = width - 216,
            wrap = true,
        })
        status:SetPoint("TOPLEFT", 212, y - 3)

        ------------------------------------------------------------------------
        -- Arriving on this screen
        --
        -- The current selection is applied on arrival rather than waiting for a
        -- click, so what is on screen always matches the card that is lit. A
        -- highlighted card describing something the player cannot see is the
        -- worst state this screen could be in.
        ------------------------------------------------------------------------
        local key = choices.layout or "standard"
        Select(key, not PUI.Preview:IsShowing(key))

        -- Coming back to a layout already on screen: say so, since Select was
        -- told not to re-apply and therefore wrote no status line.
        if PUI.Preview:IsShowing(key) and status:GetText() == "" then
            local layout = Layouts:Get(key)
            status:SetText("On screen now: " .. (layout and layout.name or key) ..
                ". Hide the installer to see it properly.")
            status:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        end
    end,
}
--------------------------------------------------------------------------------
-- 4. Graphics
--------------------------------------------------------------------------------

Steps.list.graphics = {
    title = "Graphics",
    subtitle = "The one screen that changes the game rather than the interface. Every " ..
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
                "to offer and nothing to switch between. The rest of the pack installs " ..
                "normally, and your graphics settings are left exactly as they are.\n\n" ..
                "It is the module that makes this pack worth more than a set of frame " ..
                "positions: it applies a preset when you zone into a raid or a key and " ..
                "puts it back when you leave, which is a thing you would otherwise do " ..
                "by hand or not at all.", {
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

        ------------------------------------------------------------------------
        -- Two columns
        --
        -- Baseline on the left, what-happens-when-you-zone on the right. They
        -- are one decision about graphics rather than two, and splitting them
        -- across two screens would hide the rule that ties them together: if
        -- the baseline is "leave my settings alone", auto-switch has nothing to
        -- switch away from and is greyed out.
        ------------------------------------------------------------------------
        local gutter = 24
        local leftWidth = math.floor((width - gutter) * 0.5)
        local rightWidth = width - gutter - leftWidth
        local rightX = leftWidth + gutter

        local presetCards = {}
        local autoControls = {}
        local enableBox
        local plan = choices.autoSwitch

        -- Everything on the right is meaningless without a baseline, so it dims
        -- and stops responding rather than sitting there looking clickable.
        --
        -- The children have to be walked, not just the control: both the
        -- checkbox and the dropdown are a plain Frame with the actual clickable
        -- Button parented inside it, so calling EnableMouse(false) on the
        -- wrapper alone leaves a greyed-out control that still takes clicks.
        local function SetAutoEnabled(on)
            local alpha = on and 1 or 0.35
            for _, control in ipairs(autoControls) do
                control:SetAlpha(alpha)
                control:EnableMouse(on and true or false)
                for _, child in ipairs({ control:GetChildren() }) do
                    child:EnableMouse(on and true or false)
                end
            end
        end

        local function SelectPreset(value, byHand)
            choices.graphicsPreset = value
            if byHand then choices.graphicsTouched = true end
            for cardValue, card in pairs(presetCards) do
                card:SetSelected(cardValue == value)
            end

            local usable = value ~= "none"
            if not usable then
                plan.enabled = false
                if enableBox and enableBox.SetChecked then
                    enableBox:SetChecked(false)
                end
            end
            SetAutoEnabled(usable)
        end

        ------------------------------------------------------------------------
        -- Left: the baseline
        ------------------------------------------------------------------------
        local _, leftY = W:CreateSectionHeader(page, "Baseline", 0, -2, { width = leftWidth })
        leftY = leftY - 2

        for _, option in ipairs(options) do
            local tagline
            if option.value ~= "none" and option.value == choices.recommendedGraphics then
                tagline = "suggested"
            end

            local card = SelectCard(page, {
                width = leftWidth,
                height = 42,
                title = option.label,
                tagline = tagline,
                onClick = function() SelectPreset(option.value, true) end,
            })

            if option.blurb then
                local blurb = W:CreateLabel(card, option.blurb, {
                    font = "GameFontNormalSmall",
                    color = C.textMuted,
                    width = leftWidth - 26,
                    wrap = false,
                })
                blurb:SetPoint("TOPLEFT", 14, -24)
            end

            card:SetPoint("TOPLEFT", 0, leftY)
            presetCards[option.value] = card
            leftY = leftY - 48
        end

        ------------------------------------------------------------------------
        -- Right: switch automatically
        ------------------------------------------------------------------------
        local _, rightY = W:CreateSectionHeader(page, "Switch automatically", rightX, -2,
            { width = rightWidth })
        rightY = rightY - 2

        local intro = W:CreateLabel(page,
            "Apply a different preset when you zone into a raid, a key or a dungeon, " ..
            "and put it back in the open world. Every switch is announced in chat.", {
            font = "GameFontNormalSmall",
            color = C.textMuted,
            width = rightWidth,
            wrap = true,
        })
        intro:SetPoint("TOPLEFT", rightX, rightY)
        rightY = rightY - 34

        enableBox = W:CreateCheckbox(page, "Switch by content", {
            checked = plan.enabled == true,
            width = rightWidth,
            onChange = function(checked)
                plan.enabled = checked
                choices.autoSwitchTouched = true
            end,
        })
        enableBox:SetPoint("TOPLEFT", rightX, rightY)
        autoControls[#autoControls + 1] = enableBox
        rightY = rightY - 28

        local targets = Installer:AutoSwitchTargets()

        for _, ctx in ipairs(Installer:AutoSwitchContexts()) do
            local dropdown = W:CreateDropdown(page, ctx.name, {
                width = rightWidth,
                selected = plan[ctx.key] or "none",
                options = targets,
                onChange = function(value)
                    plan[ctx.key] = value
                    choices.autoSwitchTouched = true
                end,
            })
            dropdown:SetPoint("TOPLEFT", rightX, rightY)
            autoControls[#autoControls + 1] = dropdown
            rightY = rightY - 50
        end

        SelectPreset(choices.graphicsPreset, false)
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

        y = y - 4

        local reset = W:CreateCheckbox(page, "Reset each module first", {
            checked = choices.resetFirst ~= false,
            description = "Puts every module back to its own defaults before the " ..
                          "layout goes on, so nothing from an earlier setup survives. " ..
                          "Settings you made outside the pack go too.",
            width = width - 8,
            onChange = function(checked)
                choices.resetFirst = checked
                -- The summary above describes what will happen, so it has to be
                -- redrawn rather than left describing the other answer.
                PUI.Wizard:Render()
            end,
        })
        reset:SetPoint("TOPLEFT", 0, y)
        y = y - 46

        local _, ruleY = W:CreateSeparator(page, 0, y, width)
        y = ruleY - 4

        local previewNote = PUI.Preview:IsActive()
            and "The layout you previewed is on screen now; installing keeps it. "
            or ""

        local note = W:CreateLabel(page,
            previewNote ..
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
        -- Warnings before errors: a module that quietly overrides what was just
        -- written is the thing somebody is about to be confused by, and it is
        -- not a failure - the install worked, something else is winning.
        for _, warning in ipairs(result.warnings or {}) do
            Line(warning, C.amber)
        end

        if #result.failures > 0 then
            for _, failure in ipairs(result.failures) do
                Line("Failed: " .. failure, C.danger)
            end
        elseif #(result.warnings or {}) == 0 then
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

        local installedExtras, totalExtras = PUI.Extras:CountInstalled()

        local hint = W:CreateLabel(page,
            "Every module keeps its own page in there, and /peavers opens it any time.\n\n" ..
            "There is also a More stuff page: " .. totalExtras .. " addons this pack " ..
            "works alongside but does not ship, in the places it leaves alone - group " ..
            "frames, nameplates, action bars, boss timers. You already run " ..
            installedExtras .. " of them.\n\n" ..
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

        -- Installing is the strongest possible "keep it". Without this the
        -- preview would still be outstanding, and closing the window afterwards
        -- would helpfully undo the install.
        PUI.Preview:Keep()

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
