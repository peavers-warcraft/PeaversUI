--------------------------------------------------------------------------------
-- PeaversUI wizard steps
--
-- Six pages, in order: what you have, what you want, how it should look, how big
-- it should be, what to do about graphics, and a summary you have to agree to
-- before anything is written. Each is a table with a title, a Build(page,
-- choices), and optionally an OnNext that can take the footer click for itself.
--
-- The shape of the whole thing follows one rule: nothing is applied until the
-- last step. Ticking boxes and picking layouts only edits the `choices` table,
-- so backing out at any point up to "Install" leaves the game exactly as it was
-- found. That is the difference between an installer and a settings panel, and
-- it is the reason the review page can promise anything at all.
--
-- Every page here is drawn out of PeaversCommons' Style and holds no numbers of its
-- own. Lists are flush banded rows rather than floating cards with gaps between
-- them, headings are sections rather than panels, and the accent appears exactly
-- twice on any screen: on the row you have chosen, and on the button that moves
-- you forward.
--------------------------------------------------------------------------------

local _, PUI = ...

local Steps = {}
PUI.Steps = Steps

local PeaversCommons = _G.PeaversCommons
local W = PeaversCommons.Widgets
local C = W.Colors
local Style = PeaversCommons.Style

local Modules = PUI.Modules
local Layouts = PUI.Layouts
local Installer = PUI.Installer

--------------------------------------------------------------------------------
-- Shared bits
--------------------------------------------------------------------------------

-- Where the second column starts, and how much room the right-hand value keeps
-- for itself. Two numbers, used by every table on every page, so the label
-- column lines up from the first screen to the last.
-- Where the second column starts, and how much room the right-hand value keeps
-- for itself. Two numbers, used by every table on every page, so the label
-- column lines up from the first screen to the last.
--
-- The longest module name is "Performance", which sits comfortably inside the
-- 130 points this leaves. The blurb column beside it is the one that runs out
-- of room, so spare width belongs there rather than here.
local LABEL_COL = 152
local VALUE_COL = 96

-- The three states Modules:Status reports. Only the two that need attention are
-- coloured: "ready" is the normal case and reads as a dimmed value like any
-- other, because ten accent-coloured rows would spend the accent on the one
-- thing nobody has to act on.
local STATUS_COLOR = {
    disabled = C.amber,
    missing  = C.danger,
}

local STATUS_WORD = {
    loaded   = "ready",
    disabled = "not enabled",
    missing  = "not installed",
}

-- A wrapping block of small text, and how tall it came out.
--
-- Every paragraph on these pages goes through here so that nothing below one is
-- placed by a guess. The installer's text used to be laid out with fixed
-- advances and single-line labels, and a sentence longer than the author's
-- screen ran off the right of the window or under the next control. Asking the
-- font string how tall it actually is costs nothing and is always right.
local function Paragraph(parent, text, width, opts)
    opts = opts or {}
    local label = Style.Label(parent, text, Style.Size.value,
        opts.alpha or Style.Alpha.muted,
        { width = width, wrap = true, color = opts.color })
    local height = label.GetStringHeight and label:GetStringHeight() or 0
    return label, math.max(height or 0, opts.minHeight or Style.Size.value + 2)
end

-- A table row: name on the left, a sentence in the middle, a state word on the
-- right. The middle column is held to one line and truncates, because this shape
-- is for scanning a list rather than reading it - anything that needs reading
-- gets its own paragraph.
local function TableRow(parent, y, width, opts)
    local row, nextY = Style.MakeRow(parent, y, width, { height = Style.Row.height })

    local name = Style.Label(row, opts.label, Style.Size.label, Style.Alpha.primary)
    name:SetPoint("LEFT", Style.Row.inset, 0)
    name:SetWidth(LABEL_COL - Style.Row.inset - 8)
    name:SetWordWrap(false)
    name:SetJustifyH("LEFT")

    if opts.value then
        local value = Style.Label(row, opts.value, Style.Size.value,
            opts.valueAlpha or Style.Alpha.muted, { color = opts.valueColor })
        value:SetPoint("RIGHT", -Style.Row.inset, 0)
        value:SetJustifyH("RIGHT")
    end

    if opts.detail then
        local detail = Style.Label(row, opts.detail, Style.Size.value,
            Style.Alpha.muted, { color = opts.detailColor })
        detail:SetPoint("LEFT", LABEL_COL, 0)
        detail:SetWidth(width - LABEL_COL - (opts.value and VALUE_COL or Style.Row.inset))
        detail:SetWordWrap(false)
        detail:SetJustifyH("LEFT")
    end

    return row, nextY
end

-- The same row, but the second column wraps and the row grows to hold it. For
-- the review summary, where the auto-switch line names every context it will act
-- on and is the longest sentence in the installer.
local function DetailRow(parent, y, width, label, detail, opts)
    opts = opts or {}
    local row = Style.MakeRow(parent, y, width, { height = Style.Row.height })

    local name = Style.Label(row, label, Style.Size.label, Style.Alpha.primary)
    name:SetPoint("TOPLEFT", Style.Row.inset, -9)
    name:SetWidth(LABEL_COL - Style.Row.inset - 8)
    name:SetWordWrap(false)
    name:SetJustifyH("LEFT")

    local text, textHeight = Paragraph(row, detail,
        width - LABEL_COL - Style.Row.inset, { color = opts.color })
    text:SetPoint("TOPLEFT", LABEL_COL, -9)

    local height = math.max(Style.Row.height, textHeight + 18)
    row:SetHeight(height)
    return row, y - height
end

-- A row of wrapped text and nothing else, for the result screen's report lines.
local function TextRow(parent, y, width, text, color)
    local row = Style.MakeRow(parent, y, width, { height = Style.Row.height })

    local label, height = Paragraph(row, text,
        width - (Style.Row.inset * 2), { color = color, alpha = Style.Alpha.secondary })
    label:SetPoint("TOPLEFT", Style.Row.inset, -9)

    local rowHeight = math.max(Style.Row.height, height + 18)
    row:SetHeight(rowHeight)
    return row, y - rowHeight
end

-- A choosable row: title, an optional word beside it, and a sentence underneath.
-- The row grows to fit the sentence rather than clipping it.
--
-- This replaces the card the layout and graphics screens used to be built from.
-- A selected card signalled three times over - accent border, accent left edge
-- and a recoloured title - and a hovered one changed its border, so at a glance
-- hover and selected looked like the same state. Here selection is the accent
-- bar down the left edge and nothing else, and hover is a change in alpha.
local function ChoiceRow(parent, y, width, opts)
    local row = Style.MakeRow(parent, y, width, {
        height = opts.height or Style.Row.tall,
        onClick = opts.onClick,
    })

    local title = Style.Label(row, opts.title, Style.Size.label, Style.Alpha.primary)
    title:SetPoint("TOPLEFT", Style.Row.inset, -10)

    if opts.tagline then
        local tagline = Style.Label(row, opts.tagline, Style.Size.meta, Style.Alpha.muted)
        tagline:SetPoint("LEFT", title, "RIGHT", 8, -1)
    end

    local height = opts.height or Style.Row.tall

    if opts.blurb then
        local blurbTop = 10 + Style.Size.label + 6
        local blurb, blurbHeight = Paragraph(row, opts.blurb,
            width - (Style.Row.inset * 2))
        blurb:SetPoint("TOPLEFT", Style.Row.inset, -blurbTop)
        height = math.max(height, blurbTop + blurbHeight + 12)
        row:SetHeight(height)
    end

    row:SetSelected(false)
    return row, y - height
end

--------------------------------------------------------------------------------
-- 1. Welcome - the roster
--------------------------------------------------------------------------------

Steps.list = {}

Steps.list.welcome = {
    title = "Set up your interface",
    subtitle = "Ten addons, one pass. On the layout screen your interface " ..
               "changes as you click, so you can see what you are choosing - and " ..
               "closing the installer without finishing puts it all back.",

    Build = function(_, page, _)
        local width = PUI.Wizard:ContentWidth()
        local y = 0
        local missing = 0

        -- Grouped by what each module is for, rather than run together as one
        -- list of ten. The three headings are free - they are the same rule the
        -- banding already restarts at - and they turn a wall into a contents
        -- page.
        local GROUPS = {
            { role = "core",    label = "Core" },
            { role = "display", label = "On screen" },
            { role = "system",  label = "System" },
        }

        for _, group in ipairs(GROUPS) do
            local modules = Modules:OfRole(group.role)
            if #modules > 0 then
                y = Style.Section(page, group.label, y, width)

                for _, module in ipairs(modules) do
                    local status = Modules:Status(module)
                    if status ~= "loaded" then missing = missing + 1 end

                    local _, nextY = TableRow(page, y, width, {
                        label = module.label,
                        detail = module.blurb,
                        value = STATUS_WORD[status],
                        valueColor = STATUS_COLOR[status],
                        valueAlpha = status == "loaded" and Style.Alpha.muted or Style.Alpha.primary,
                    })
                    y = nextY
                end
            end
        end

        y = y - Style.Pad.gap

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

        local note = Paragraph(page, footer, width, {
            color = missing > 0 and C.amber or nil,
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
        local y = 0

        for _, module in ipairs(Modules:OfRole("display")) do
            if Modules:IsAvailable(module) then
                local _, nextY = Style.Checkbox(page, y, width, {
                    label = module.label,
                    description = module.blurb .. "   " .. (module.slash or ""),
                    checked = choices.modules[module.key] ~= false,
                    onChange = function(checked)
                        choices.modules[module.key] = checked
                    end,
                })
                y = nextY
            else
                -- Shown rather than hidden. A module that quietly vanishes from
                -- the list reads as a bug in the pack; one that is listed as
                -- absent reads as a thing you could go and install.
                local status = Modules:Status(module)
                local _, nextY = TableRow(page, y, width, {
                    label = module.label,
                    detail = "nothing to configure",
                    value = STATUS_WORD[status],
                    valueColor = STATUS_COLOR[status],
                })
                y = nextY
            end
        end

        y = y - Style.Pad.gap

        local note = Paragraph(page,
            "PeaversPerformance is not in this list because on and off is not the " ..
            "question worth asking about it - it gets a screen of its own two steps " ..
            "from here.", width)
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
        local rows = {}
        local status

        ------------------------------------------------------------------------
        -- Clicking a row applies it
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
            for rowKey, row in pairs(rows) do
                row:SetSelected(rowKey == key)
            end

            -- The graphics step takes its starting values from the layout, right
            -- up until the player edits them by hand. After that their choices
            -- survive a change of mind about the layout. The baseline and the
            -- auto-switch plan track that independently, so tweaking one context
            -- does not freeze the other.
            if not choices.graphicsTouched then
                local layout = Layouts:Get(key)
                choices.recommendedGraphics = layout and layout.graphics or nil
                -- Suggested but never preselected for somebody with a setup of
                -- their own: graphics are not the question they came to answer.
                if not choices.existing then
                    choices.graphicsPreset = choices.recommendedGraphics
                end
            end

            if not choices.autoSwitchTouched then
                choices.autoSwitch = Layouts:AutoSwitchFor(key)
            end

            -- The one row that puts nothing on screen. Whatever was being
            -- previewed goes back, and that is all.
            if key == Layouts.CURRENT then
                if PUI.Preview:IsActive() then PUI.Preview:Revert() end
                if status then
                    status:SetText("Nothing has changed - your modules stay exactly as they are.")
                    Style.Text(status, Style.Size.value, Style.Alpha.muted)
                end
                return
            end

            if not applyIt then return end

            local ok, reason = PUI.Preview:Start(key, choices)
            if status then
                if ok then
                    local layout = Layouts:Get(key)
                    status:SetText("On screen now: " .. (layout and layout.name or key) ..
                        ". Hide the installer to see it properly.")
                    Style.Text(status, Style.Size.value, Style.Alpha.secondary)
                else
                    -- Combat, almost always. Selecting still works; it just does
                    -- not take effect until the fight is over, which is better
                    -- than refusing the click and saying nothing.
                    status:SetText(reason or "Could not switch to that layout right now.")
                    Style.Text(status, Style.Size.value, Style.Alpha.primary, C.amber)
                end
            end
        end

        ------------------------------------------------------------------------
        -- The four layouts
        ------------------------------------------------------------------------
        local y = 0

        -- First, and selected, for anybody whose modules already hold settings
        -- of their own. Only for them: to a new player it would be a row
        -- offering to change nothing.
        local entries = Layouts:Sorted()
        if choices.existing then
            table.insert(entries, 1, { key = Layouts.CURRENT, layout = {
                name = "Keep my current setup",
                tagline = "nothing is rewritten",
                blurb = "Your modules stay exactly as they are - positions, sizes, " ..
                        "colours and all. Choose this to add or remove modules or set " ..
                        "up graphics without touching the look you already have.",
            } })
        end

        for _, entry in ipairs(entries) do
            local row, nextY = ChoiceRow(page, y, width, {
                title = entry.layout.name,
                tagline = entry.layout.tagline,
                blurb = entry.layout.blurb,
                onClick = function() Select(entry.key, true) end,
            })
            rows[entry.key] = row
            y = nextY
        end

        y = y - Style.Pad.section

        ------------------------------------------------------------------------
        -- Getting the window out of the way
        ------------------------------------------------------------------------
        local hide = Style.Button(page, "Hide the installer and look", {
            variant = "secondary",
            width = 200,
            onClick = function()
                PUI.Wizard:EnterPreview(choices.layout)
            end,
        })
        hide:SetPoint("TOPLEFT", 0, y)

        status = Style.Label(page, "", Style.Size.value, Style.Alpha.muted, {
            width = width - 216,
            wrap = true,
        })
        status:SetPoint("TOPLEFT", 212, y - 4)

        ------------------------------------------------------------------------
        -- Arriving on this screen
        --
        -- The current selection is applied on arrival rather than waiting for a
        -- click, so what is on screen always matches the row that is lit. A
        -- highlighted row describing something the player cannot see is the
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
            Style.Text(status, Style.Size.value, Style.Alpha.secondary)
        end
    end,
}

--------------------------------------------------------------------------------
-- 4. Interface size
--
-- The layout screen answers what this should look like. This one answers how
-- big, which has a different right answer on every machine and was the one thing
-- the pack decided on everybody's behalf: every layout was drawn on a 1440-unit
-- canvas and every install got that canvas, which is right on the monitor the
-- pack was built on and too small to read on a laptop.
--
-- Like the layout screen, it applies as you click. "A third larger" means
-- nothing until it is on your own screen at your own seating distance, so the
-- rows re-apply the whole layout at the new canvas and the window can stand
-- aside to let you look.
--------------------------------------------------------------------------------

-- The re-apply settles rather than firing per step: dragging the slider walks
-- every value in between, and each one would otherwise rewrite six addons'
-- settings and rebuild their frames. Long enough that a drag settles once;
-- short enough that a click on a row still feels like the click did it.
local SIZE_SETTLE = 0.25

Steps.list.size = {
    title = "How big should it be",
    subtitle = "The layouts are drawn at a fixed size so they land in the same place " ..
               "on any screen - which means the pack needs telling which screen. " ..
               "This changes as you click, the same way the layouts do.",

    Build = function(self, page, choices)
        local width = PUI.Wizard:ContentWidth()
        local scaler = Modules.byKey.scaler

        -- A pending re-apply belongs to the page that scheduled it. Rendering
        -- this step again - arriving, or coming back - starts a new page, so the
        -- old timer would write its status line onto a frame nobody can see.
        if self.timer then
            self.timer:Cancel()
            self.timer = nil
        end

        ------------------------------------------------------------------------
        -- Nothing being placed
        --
        -- "Keep my current setup" writes no positions and no scale, so there is
        -- no canvas to draw it on and nothing here to ask. A size chooser that
        -- did nothing would be the only screen in this installer that lied.
        ------------------------------------------------------------------------
        if choices.layout == Layouts.CURRENT then
            local note = Paragraph(page,
                "You are keeping your own setup, so the pack is not placing anything and " ..
                "has no reason to change how big it is. Your UI scale is left exactly " ..
                "where you have it.\n\n" ..
                "If it is your scale you want to change rather than your layout, " ..
                "/pscaler does that on its own - presets, a slider and a pixel-perfect " ..
                "mode - without this installer rewriting anything else.", width)
            note:SetPoint("TOPLEFT", 0, -4)
            return
        end

        ------------------------------------------------------------------------
        -- Nothing to set it with
        --
        -- PeaversScaler is what holds the UI scale; without it the pack can
        -- place a layout but not size it. Say so rather than offering a chooser
        -- whose every option does the same nothing.
        ------------------------------------------------------------------------
        if not Modules:IsAvailable(scaler) then
            local note = Paragraph(page,
                "PeaversScaler is not running, so there is no size to choose: the pack " ..
                "can move things around your screen but not change how big your screen " ..
                "is in UI units.\n\n" ..
                "The layout is placed for the size it was drawn at, which is right if " ..
                "your UI scale is already there and small if it is not. Install " ..
                "PeaversScaler and run /pui again, or set Blizzard's own UI scale by " ..
                "hand and come back.", width)
            note:SetPoint("TOPLEFT", 0, -4)
            choices.canvas = Layouts.CANVAS_HEIGHT
            return
        end

        local y = 0
        local status

        ------------------------------------------------------------------------
        -- Switched off two screens back
        --
        -- Still a real question, since the positions are written for a canvas
        -- either way, but nothing here will set the scale to match - so it is
        -- said at the top rather than discovered on the summary.
        ------------------------------------------------------------------------
        if not choices.modules[scaler.key] then
            local warn, warnHeight = Paragraph(page,
                "The Scaler is switched off, so nothing will change your UI scale. The " ..
                "size below still decides where the layout puts things, so pick the one " ..
                "matching the scale you already run - or go back a screen and switch the " ..
                "Scaler on.", width, { color = C.amber, alpha = Style.Alpha.secondary })
            warn:SetPoint("TOPLEFT", 0, y)
            y = y - (warnHeight + Style.Pad.section)
        end

        local rows = {}
        local slider
        local sliderEcho = false   -- our own SetValue, not a drag: ignore it

        local recommended = Layouts:RecommendedCanvas()

        local function Apply()
            self.timer = nil

            local ok, reason = PUI.Preview:Start(choices.layout, choices)
            if not status then return end

            if ok then
                status:SetText("On screen now at " .. Layouts:SizeLabel(choices.canvas) ..
                    ". Hide the installer to see it properly.")
                Style.Text(status, Style.Size.value, Style.Alpha.secondary)
            else
                status:SetText(reason or "Could not change the size right now.")
                Style.Text(status, Style.Size.value, Style.Alpha.primary, C.amber)
            end
        end

        local function ApplySoon()
            if self.timer then self.timer:Cancel() end
            self.timer = C_Timer.NewTimer(SIZE_SETTLE, function() Apply() end)
        end

        -- `custom` is the row the slider drives. Clicking a named size moves the
        -- slider to match; moving the slider lights `custom`, because a value
        -- between two named sizes is not either of them.
        local function Select(canvas, applyIt)
            choices.canvas = canvas

            local named = Layouts:SizeKeyFor(canvas)
            for rowKey, row in pairs(rows) do
                row:SetSelected(rowKey == (named or "custom"))
            end

            if slider then
                sliderEcho = true
                slider:SetValue(Layouts:SizeOf(canvas))
                sliderEcho = false
            end

            if applyIt then ApplySoon() end
        end

        ------------------------------------------------------------------------
        -- The named sizes
        ------------------------------------------------------------------------
        y = Style.Section(page, "Size", y, width)

        for _, size in ipairs(Layouts.sizes) do
            local tagline = Layouts:SizeLabel(size.canvas)
            -- The suggestion is marked, never pre-selected on a re-run: see
            -- Wizard:Show. On a first install it is already the selected row,
            -- and saying so is what explains why.
            if size.canvas == recommended then
                tagline = tagline .. " - suggested for your screen"
            end

            local row, nextY = ChoiceRow(page, y, width, {
                title = size.label,
                tagline = tagline,
                blurb = size.blurb,
                onClick = function() Select(size.canvas, true) end,
            })
            rows[size.key] = row
            y = nextY
        end

        -- No blurb: the slider directly underneath is the explanation, and the
        -- page has exactly one row's worth of height to spare.
        local customRow, afterCustom = ChoiceRow(page, y, width, {
            title = "Custom",
            tagline = "set it by hand with the slider below",
            onClick = function()
                if slider then Select(Layouts:CanvasFor(slider:GetValue()), true) end
            end,
        })
        rows.custom = customRow
        y = afterCustom - Style.Pad.section

        ------------------------------------------------------------------------
        -- The slider
        ------------------------------------------------------------------------
        slider = W:CreateSlider(page, "Interface size", {
            width = width,
            min = Layouts.SIZE_MIN,
            max = Layouts.SIZE_MAX,
            step = Layouts.SIZE_STEP,
            value = Layouts:SizeOf(choices.canvas),
            format = function(value)
                return math.floor(value * 100 + 0.5) .. "%"
            end,
            onChange = function(value)
                -- SetValue from Select fires this too, and letting it through
                -- would turn every click on a named row into a custom size two
                -- decimal places away from it.
                if sliderEcho then return end
                Select(Layouts:CanvasFor(value), true)
            end,
        })
        slider:SetPoint("TOPLEFT", 0, y)
        y = y - (44 + Style.Pad.section)

        ------------------------------------------------------------------------
        -- Getting the window out of the way
        ------------------------------------------------------------------------
        local hide = Style.Button(page, "Hide the installer and look", {
            variant = "secondary",
            width = 200,
            onClick = function()
                PUI.Wizard:EnterPreview(choices.layout)
            end,
        })
        hide:SetPoint("TOPLEFT", 0, y)

        status = Style.Label(page, "", Style.Size.value, Style.Alpha.muted, {
            width = width - 216,
            wrap = true,
        })
        status:SetPoint("TOPLEFT", 212, y - 4)

        ------------------------------------------------------------------------
        -- Arriving on this screen
        --
        -- Light the row that matches, and only re-apply when what is on screen
        -- is not already this layout at this size - which it usually is, having
        -- come straight from the layout screen.
        ------------------------------------------------------------------------
        local canvas = tonumber(choices.canvas) or Layouts.CANVAS_HEIGHT
        Select(canvas, not PUI.Preview:IsShowing(choices.layout, canvas))

        if PUI.Preview:IsShowing(choices.layout, canvas) then
            status:SetText("On screen now at " .. Layouts:SizeLabel(canvas) ..
                ". Hide the installer to see it properly.")
            Style.Text(status, Style.Size.value, Style.Alpha.secondary)
        end
    end,
}

--------------------------------------------------------------------------------
-- 5. Graphics
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
            local note = Paragraph(page,
                "PeaversPerformance is not running, so there are no graphics presets " ..
                "to offer and nothing to switch between. The rest of the pack installs " ..
                "normally, and your graphics settings are left exactly as they are.\n\n" ..
                "It is the module that makes this pack worth more than a set of frame " ..
                "positions: it applies a preset when you zone into " .. Installer:InstancePhrase() .. " and " ..
                "puts it back when you leave, which is a thing you would otherwise do " ..
                "by hand or not at all.", width)
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
        --
        -- Each column is a frame of its own rather than an x offset, because the
        -- row banding counts per parent: sharing one parent would have the right
        -- column carry on the left column's alternation and the two would read
        -- as one broken list.
        ------------------------------------------------------------------------
        local gutter = 24
        local leftWidth = math.floor((width - gutter) * 0.5)
        local rightWidth = width - gutter - leftWidth

        local leftColumn = CreateFrame("Frame", nil, page)
        leftColumn:SetPoint("TOPLEFT", 0, 0)
        leftColumn:SetSize(leftWidth, 1)

        local rightColumn = CreateFrame("Frame", nil, page)
        rightColumn:SetPoint("TOPLEFT", leftWidth + gutter, 0)
        rightColumn:SetSize(rightWidth, 1)

        local presetRows = {}
        local autoControls = {}
        local enableBox
        local plan = choices.autoSwitch

        -- Everything on the right is meaningless without a baseline, so it dims
        -- and stops responding rather than sitting there looking clickable.
        --
        -- The children have to be walked, not just the control: a dropdown is a
        -- plain Frame with the actual clickable Button parented inside it, so
        -- calling EnableMouse(false) on the wrapper alone leaves a greyed-out
        -- control that still takes clicks.
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
            for rowValue, row in pairs(presetRows) do
                row:SetSelected(rowValue == value)
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
        local leftY = Style.Section(leftColumn, "Baseline", 0, leftWidth)

        for _, option in ipairs(options) do
            local tagline
            if option.value ~= "none" and option.value == choices.recommendedGraphics then
                tagline = "suggested"
            end

            local row, nextY = ChoiceRow(leftColumn, leftY, leftWidth, {
                title = option.label,
                tagline = tagline,
                blurb = option.blurb,
                onClick = function() SelectPreset(option.value, true) end,
            })
            presetRows[option.value] = row
            leftY = nextY
        end

        ------------------------------------------------------------------------
        -- Right: switch automatically
        ------------------------------------------------------------------------
        local rightY = Style.Section(rightColumn, "Switch automatically", 0, rightWidth)

        local intro, introHeight = Paragraph(rightColumn,
            "Apply a different preset when you zone into " .. Installer:InstancePhrase() .. ", " ..
            "and put it back in the open world. Every switch is announced in chat.", rightWidth)
        intro:SetPoint("TOPLEFT", 0, rightY)
        rightY = rightY - (introHeight + Style.Pad.gap)

        local afterBox
        enableBox, afterBox = Style.Checkbox(rightColumn, rightY, rightWidth, {
            label = "Switch by content",
            checked = plan.enabled == true,
            onChange = function(checked)
                plan.enabled = checked
                choices.autoSwitchTouched = true
            end,
        })
        autoControls[#autoControls + 1] = enableBox
        rightY = afterBox

        local targets = Installer:AutoSwitchTargets()

        for _, ctx in ipairs(Installer:AutoSwitchContexts()) do
            local dropdown = W:CreateDropdown(rightColumn, ctx.name, {
                width = rightWidth,
                selected = plan[ctx.key] or "none",
                options = targets,
                onChange = function(value)
                    plan[ctx.key] = value
                    choices.autoSwitchTouched = true
                end,
            })
            dropdown:SetPoint("TOPLEFT", 0, rightY - 6)
            autoControls[#autoControls + 1] = dropdown
            rightY = rightY - 50
        end

        SelectPreset(choices.graphicsPreset, false)
    end,
}

--------------------------------------------------------------------------------
-- 6. Review, then done
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
        self.hideBack = false

        local y = Style.Section(page, "Summary", 0, width)

        for _, line in ipairs(Installer:Preview(choices)) do
            local _, nextY = DetailRow(page, y, width, line.label, line.detail, {
                color = not line.ok and C.amber or nil,
            })
            y = nextY
        end

        -- Keeping the current setup has nothing to reset and nothing to follow,
        -- so neither box is offered: both are questions about a layout that is
        -- not being applied.
        if choices.layout ~= Layouts.CURRENT then
            y = Style.Section(page, "Before it goes on", y, width)

            local _, afterReset = Style.Checkbox(page, y, width, {
                label = "Reset each module first",
                checked = choices.resetFirst ~= false,
                description = "Puts every module back to its own defaults before the " ..
                              "layout goes on, so nothing from an earlier setup survives. " ..
                              "Settings you made outside the pack go too.",
                onChange = function(checked)
                    choices.resetFirst = checked
                    -- The summary above describes what will happen, so it has to be
                    -- redrawn rather than left describing the other answer.
                    PUI.Wizard:Render()
                end,
            })
            y = afterReset

            -- Off unless ticked, on a first run and on every run after: pack
            -- updates changing somebody's screen has to be something they chose.
            local layout = Layouts:Get(choices.layout)
            local _, afterTrack = Style.Checkbox(page, y, width, {
                label = "Keep this layout up to date",
                checked = choices.track == PUI.Versioning.LATEST,
                description = "Off: pack updates never change your interface. On: when an " ..
                              "update changes the " .. (layout and layout.name or "chosen") ..
                              " layout it is re-applied the next time you log in, over any of " ..
                              "its settings you have changed, and /pui undo reverses it.",
                onChange = function(checked)
                    choices.track = checked and PUI.Versioning.LATEST or PUI.Versioning.PINNED
                end,
            })
            y = afterTrack
        end

        y = y - Style.Pad.gap

        -- One line, not four. The page it sits at the bottom of is the longest in
        -- the installer, and most of what this used to say - that the pack only
        -- ever writes ordinary settings, and where to change them - is said
        -- again, with room to say it properly, on the screen after this one.
        local note = Paragraph(page,
            (PUI.Preview:IsActive()
                and "The layout you previewed is on screen now; installing keeps it. "
                or "") ..
            "Everything here lands in the modules' own settings, and /pui starts over.",
            width)
        note:SetPoint("TOPLEFT", 0, y)
    end,

    BuildResult = function(self, page)
        local width = PUI.Wizard:ContentWidth()
        local result = self.result

        self.title = "Installed"
        self.subtitle = "Most of it is already on screen. A reload settles the few " ..
                        "settings the game only reads at login."
        self.nextLabel = "Reload UI"
        self.hideBack = true

        local y = Style.Section(page, "What happened", 0, width)

        -- Failure lines carry whatever the module's error said, which can run
        -- to two or three lines, so every row is measured rather than advanced
        -- by a fixed amount.
        local function Line(text, color)
            local _, nextY = TextRow(page, y, width, text, color)
            y = nextY
        end

        if #result.applied > 0 then
            Line("Configured: " .. table.concat(result.applied, ", "))
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

        y = Style.Section(page, "Where to go next", y, width)

        local installedExtras, totalExtras = PUI.Extras:CountInstalled()

        local hint, hintHeight = Paragraph(page,
            "Each module's settings are in Blizzard's Edit Mode now: press Escape, " ..
            "choose Edit Mode, and select the thing you want to change. Every " ..
            "module still keeps a page in /peavers explaining what it does.\n\n" ..
            "There is also a More stuff page: " .. totalExtras .. " addons this pack " ..
            "works alongside but does not ship, in the places it leaves alone - group " ..
            "frames, nameplates, action bars, boss timers. You already run " ..
            installedExtras .. " of them.\n\n" ..
            "If any of it is not to your taste, change it in Edit Mode rather than " ..
            "reinstalling - the pack only ever wrote ordinary settings, and that " ..
            "is where they are edited.", width)
        hint:SetPoint("TOPLEFT", 0, y - 2)
        y = y - (hintHeight + Style.Pad.section)

        -- PeaversConfig rather than Edit Mode, even though the settings live in
        -- Edit Mode now: opening Edit Mode from here would mean touching
        -- EditModeManagerFrame, which is the classic way an addon taints
        -- Blizzard's own UI. Its pages say where to go and how to get there.
        local settings = Style.Button(page, "Open the addon pages", {
            variant = "secondary",
            width = 180,
            onClick = function()
                PUI.Wizard:Hide()
                if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
                    _G.PeaversConfig.MainFrame:Show()
                end
            end,
        })
        settings:SetPoint("TOPLEFT", 0, y)
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

-- The footer counts these to say "step 3 of 6", so this is also the length of
-- the wizard.
Steps.order = { "welcome", "modules", "layout", "size", "graphics", "review" }

-- The review step carries its own result between renders, which would otherwise
-- survive into the next run and show a stale report. Cleared whenever the
-- wizard opens.
--
-- The size step's pending re-apply goes with it: a timer left running from a
-- closed wizard would write a layout onto the screen of somebody who had already
-- walked away from the question.
function Steps:Reset()
    self.list.review.result = nil
    self:CancelPending()
end

-- Drop any re-apply the size step still has in flight. Called when the wizard
-- opens and again when it closes: closing reverts the preview, and a timer that
-- survived it would put the layout straight back on a fraction of a second
-- later, over the settings that had just been restored.
function Steps:CancelPending()
    local size = self.list.size
    if size and size.timer then
        size.timer:Cancel()
        size.timer = nil
    end
end

return Steps
