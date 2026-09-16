--------------------------------------------------------------------------------
-- PeaversUI wizard chrome
--
-- The frame, the step rail and the footer buttons. It knows how to move between
-- steps and nothing at all about what any of them contain: a step is a table in
-- PUI.Steps with a `title`, a `Build(content, choices)` and optionally a
-- `nextLabel`, and this file never looks inside one.
--
-- Built out of PeaversCommons.Widgets so the installer looks like the settings
-- window it hands off to, rather than like a separate product bolted on the
-- front. Same paper, same hairlines, same indigo.
--
-- Everything is created on first open and reused afterwards. An installer that
-- runs once should not be holding frames for the rest of the session, but it
-- also should not rebuild them if somebody reopens it to change their mind, so
-- the compromise is: nothing exists until /pui or a first login, and after that
-- one frame is kept and its content area is what gets rebuilt per step.
--------------------------------------------------------------------------------

local _, PUI = ...

local Wizard = {}
PUI.Wizard = Wizard

local PeaversCommons = _G.PeaversCommons
local W = PeaversCommons.Widgets
local C = W.Colors

-- Every number this window is drawn with lives in Style, and nothing here
-- restates one. See src/UI/Style.lua for the system and why it is that system.
local Style = PUI.Style

-- Wide enough for the graphics screen, which is the only two-column page and
-- therefore the one that sets the floor: a preset card and a context dropdown
-- side by side both need room for a sentence.
local FRAME_WIDTH = 760
-- Tall enough for the summary screen with both of its checkboxes under a row per
-- module; still inside the 768-unit screen of an unscaled UI.
local FRAME_HEIGHT = 640
local CONTENT_INSET = Style.Pad.content
-- Room for a 32px button with air above and below it. The buttons this window
-- borrows from stand 38 tall in a popup with nothing else in it; a footer wants
-- the shorter one.
local FOOTER_HEIGHT = 58
-- Room for a three-line subtitle. At 76 the second line of every longer subtitle
-- ran through the header rule and into the page underneath it, and the hero
-- title sits lower than the old eyebrow-and-title pair did.
local HEADER_HEIGHT = 104

local frame          ---@type Frame
local contentFrame   ---@type Frame
local titleText      ---@type FontString
local subtitleText   ---@type FontString
local stepText       ---@type FontString
local backButton     ---@type Button
local nextButton     ---@type Button
local skipButton     ---@type Button

Wizard.stepIndex = 1
Wizard.choices = nil

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local function SaveFramePosition()
    if not frame then return end
    local point, _, _, x, y = frame:GetPoint()
    if not point then return end
    PUI.Config.framePoint = point
    PUI.Config.frameX = math.floor(x + 0.5)
    PUI.Config.frameY = math.floor(y + 0.5)
    PUI.Config:Save()
end

local function BuildFrame()
    frame = CreateFrame("Frame", "PeaversUIInstaller", UIParent, "BackdropTemplate") --[[@as Frame]]
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint(PUI.Config.framePoint or "CENTER", PUI.Config.frameX or 0, PUI.Config.frameY or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition()
    end)

    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    frame:SetBackdropColor(C.bgBase[1], C.bgBase[2], C.bgBase[3], C.bgBase[4])

    -- The edge is four unsnapped textures rather than a backdrop edgeSize; see
    -- Style.Border for why a one pixel edge does not come out one pixel wide on
    -- all four sides at this pack's scale.
    local frameBorder = Style.Border(frame)
    frameBorder:SetColor(C.border[1], C.border[2], C.border[3], 1)

    -- Escape closes it. An installer you cannot dismiss with the key everything
    -- else in the game dismisses with is a trap, not a wizard.
    table.insert(UISpecialFrames, "PeaversUIInstaller")

    -- UISpecialFrames hides the FRAME, not the wizard - Escape never reaches
    -- Wizard:Hide, so the cleanup that lives there was skipped and an
    -- outstanding layout preview was left applied with its undo still sitting in
    -- SavedVariables. Hanging the cleanup off OnHide catches every route out:
    -- Escape, the close button, and anything else that hides the frame.
    frame:SetScript("OnHide", function()
        Wizard:OnClosed()
    end)

    ----------------------------------------------------------------------------
    -- Header
    ----------------------------------------------------------------------------
    -- Title and one line of description. The accent eyebrow that used to sit
    -- above the title was colour doing decoration rather than carrying state,
    -- which is the habit this window is being broken of.
    titleText = Style.Label(frame, "", Style.Size.hero, Style.Alpha.primary)
    titleText:SetPoint("TOPLEFT", CONTENT_INSET, -24)

    subtitleText = Style.Label(frame, "", Style.Size.value, Style.Alpha.secondary, {
        width = FRAME_WIDTH - (CONTENT_INSET * 2) - 40,
        wrap = true,
    })
    subtitleText:SetPoint("TOPLEFT", CONTENT_INSET, -24 - Style.Size.hero - 8)

    -- A text glyph rather than a bordered button: a boxed X in the corner
    -- competes with the two real actions in the footer.
    --
    -- A plain ASCII X, not the typographic multiplication sign it started as:
    -- the game's fonts carry almost nothing outside basic Latin, so the nicer
    -- glyph drew as blank space and the window had no visible close button.
    local close = Style.Button(frame, "X", {
        variant = "link", width = 28, height = 28,
        onClick = function() Wizard:Hide() end,
    })
    close:SetPoint("TOPRIGHT", -10, -10)

    local headerRule = Style.Hairline(frame, Style.Rule.chrome)
    headerRule:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    headerRule:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT)

    ----------------------------------------------------------------------------
    -- Content
    --
    -- The container each step's page frame is parented to. It is never emptied
    -- itself; moving between steps swaps the page inside it - see NewPage.
    ----------------------------------------------------------------------------
    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", CONTENT_INSET, -(HEADER_HEIGHT + 12))
    contentFrame:SetPoint("BOTTOMRIGHT", -CONTENT_INSET, FOOTER_HEIGHT + 8)

    ----------------------------------------------------------------------------
    -- Footer
    ----------------------------------------------------------------------------
    local footerRule = Style.Hairline(frame, Style.Rule.chrome)
    footerRule:SetPoint("BOTTOMLEFT", 0, FOOTER_HEIGHT)
    footerRule:SetPoint("BOTTOMRIGHT", 0, FOOTER_HEIGHT)

    -- Where you are, in words. The row of dots this replaces was a web motif
    -- that said the same thing less clearly, in the accent, which belongs to
    -- selection and the primary action alone.
    stepText = Style.Label(frame, "", Style.Size.section, Style.Alpha.muted)
    stepText:SetPoint("BOTTOMLEFT", CONTENT_INSET, 24)

    nextButton = Style.Button(frame, "Next", {
        variant = "primary", width = 120,
        onClick = function() Wizard:Next() end,
    })
    nextButton:SetPoint("BOTTOMRIGHT", -CONTENT_INSET, 13)

    backButton = Style.Button(frame, "Back", {
        variant = "secondary", width = 100,
        onClick = function() Wizard:Back() end,
    })
    backButton:SetPoint("RIGHT", nextButton, "LEFT", -8, 0)

    skipButton = Style.Button(frame, "Not now", {
        variant = "link", width = 84,
        onClick = function() Wizard:Hide() end,
    })
    skipButton:SetPoint("RIGHT", backButton, "LEFT", -6, 0)

    frame:Hide()
end

--------------------------------------------------------------------------------
-- Content lifecycle
--
-- WoW has no way to destroy a frame, so a step's widgets can only be hidden and
-- forgotten. Doing that widget by widget is a mess - font strings and textures
-- are regions rather than children, and the two are enumerated separately - so
-- instead each step draws into a page frame of its own. Dropping one page drops
-- everything on it in a single move, with no chance of leaving a stray label
-- behind on top of the next step.
--------------------------------------------------------------------------------
local currentPage ---@type Frame|nil

local function NewPage()
    if currentPage then
        currentPage:Hide()
        currentPage:ClearAllPoints()
        currentPage:SetParent(nil)
    end

    currentPage = CreateFrame("Frame", nil, contentFrame)
    currentPage:SetAllPoints(contentFrame)
    return currentPage
end

--------------------------------------------------------------------------------
-- Where you are
--
-- "Step 3 of 5", small and dim in the corner of the footer. It answers "how
-- much more of this is there" before anybody has to ask, which is most of what
-- makes a wizard tolerable - and it answers it in words rather than in a row of
-- coloured dots nobody has to decode.
--------------------------------------------------------------------------------
local function UpdateRail()
    if not stepText then return end
    stepText:SetText(("STEP %d OF %d"):format(Wizard.stepIndex, #PUI.Steps.order))
end

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

function Wizard:CurrentStep()
    local key = PUI.Steps.order[self.stepIndex]
    return key and PUI.Steps.list[key] or nil
end

function Wizard:Render()
    local step = self:CurrentStep()
    if not step then return end

    local page = NewPage()

    local ok, err = pcall(step.Build, step, page, self.choices)
    if not ok then
        -- A step that throws would otherwise leave a blank panel and no
        -- explanation, because WoW eats Lua errors unless the player has turned
        -- them on. Say so on the panel itself.
        local message = Style.Label(page,
            "This page failed to draw: " .. tostring(err) ..
            "\n\nThe rest of the installer still works - use Back, or close and run /pui.",
            Style.Size.value, Style.Alpha.primary, {
                color = C.danger,
                width = FRAME_WIDTH - (CONTENT_INSET * 2) - 20,
                wrap = true,
            })
        message:SetPoint("TOPLEFT", 0, -8)
    end

    -- Header and footer are read after Build, not before: a step decides what
    -- it is called and what its buttons say while it draws itself. The review
    -- step is the reason - it is "Ready to install" with an Install button until
    -- it has installed, and "Installed" with a Reload UI button afterwards, and
    -- both faces are the same step object.
    titleText:SetText(step.title or "")
    subtitleText:SetText(step.subtitle or "")

    backButton:SetShown(self.stepIndex > 1 and not step.hideBack)
    skipButton:SetShown(not step.hideSkip)
    skipButton:SetLabel(step.skipLabel or "Not now")
    nextButton:SetLabel(step.nextLabel or "Next")

    UpdateRail()
end

function Wizard:Next()
    local step = self:CurrentStep()

    -- A step can take the click itself - the review step's "Install" is the
    -- same button, and the done step's is "Reload UI".
    if step and step.OnNext then
        local handled = step:OnNext(self.choices)
        if handled then return end
    end

    if self.stepIndex < #PUI.Steps.order then
        self.stepIndex = self.stepIndex + 1
        self:Render()
    else
        self:Hide()
    end
end

function Wizard:Back()
    if self.stepIndex > 1 then
        self.stepIndex = self.stepIndex - 1
        self:Render()
    end
end

-- Jump straight to a step by key. Used by the "done" hand-off and by
-- /pui, which reopens on the layout step for somebody who has already
-- installed once and only wants to change their mind about the look.
function Wizard:GoTo(key)
    for index, stepKey in ipairs(PUI.Steps.order) do
        if stepKey == key then
            self.stepIndex = index
            self:Render()
            return true
        end
    end
    return false
end

-- Steps call this after changing something the footer depends on - ticking the
-- last module off, say - so the buttons can catch up without a full rebuild
-- that would drop focus.
function Wizard:RefreshFooter()
    local step = self:CurrentStep()
    if not step or not nextButton then return end
    nextButton:SetLabel(step.nextLabel or "Next")
end

--------------------------------------------------------------------------------
-- Getting out of the way
--
-- The layout screen swaps the real interface as you click, which is useless
-- while a 760px window is sitting on top of the frames it just moved - and half
-- of Standard is underneath it. So the window can stand aside entirely, leaving
-- one small strip behind.
--
-- The strip is deliberately tiny and deliberately unmissable. Somebody who
-- wandered off has to be able to find their way back to an undo, and the
-- alternative - no marker at all - is how a look-at-this becomes a state you
-- are stuck in without knowing it.
--------------------------------------------------------------------------------

---@class PreviewBar : Frame
---@field label FontString
local previewBar

local function BuildPreviewBar()
    previewBar = CreateFrame("Frame", "PeaversUIPreviewBar", UIParent, "BackdropTemplate") --[[@as PreviewBar]]
    previewBar:SetSize(360, 40)
    previewBar:SetPoint("TOP", UIParent, "TOP", 0, -80)
    previewBar:SetFrameStrata("DIALOG")
    previewBar:SetClampedToScreen(true)
    previewBar:SetMovable(true)
    previewBar:EnableMouse(true)
    previewBar:RegisterForDrag("LeftButton")
    previewBar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    previewBar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    previewBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    previewBar:SetBackdropColor(C.bgBase[1], C.bgBase[2], C.bgBase[3], 0.97)

    local previewBorder = Style.Border(previewBar)
    previewBorder:SetColor(1, 1, 1, Style.Rule.chrome)

    -- The same accent bar a selected row wears, for the same reason: this strip
    -- exists to say a choice is currently being tried on. Outlining the whole
    -- thing in accent said it louder without saying it more clearly.
    local mark = previewBar:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", 0, 0)
    mark:SetPoint("BOTTOMLEFT", 0, 0)
    mark:SetWidth(Style.Row.bar)
    mark:SetColorTexture(Style.Accent[1], Style.Accent[2], Style.Accent[3], 1)

    previewBar.label = Style.Label(previewBar, "", Style.Size.label, Style.Alpha.primary)
    previewBar.label:SetPoint("LEFT", Style.Row.inset, 0)

    local undo = Style.Button(previewBar, "Undo", {
        variant = "link", width = 56, height = 26,
        onClick = function() Wizard:ExitPreview(true) end,
    })
    undo:SetPoint("RIGHT", -10, 0)

    local back = Style.Button(previewBar, "Back to installer", {
        variant = "primary", width = 152, height = 26,
        onClick = function() Wizard:ExitPreview(false) end,
    })
    back:SetPoint("RIGHT", undo, "LEFT", -6, 0)

    previewBar:Hide()
end

-- Stand aside so the layout on screen can actually be seen.
function Wizard:EnterPreview(layoutKey)
    if not previewBar then BuildPreviewBar() end

    local layout = PUI.Layouts:Get(layoutKey)
    previewBar.label:SetText("Trying: " .. (layout and layout.name
        or (layoutKey == PUI.Layouts.CURRENT and "your current setup") or layoutKey))

    if frame then frame:Hide() end
    previewBar:Show()
end

-- Come back to the installer. `revert` puts the old settings back; without it
-- the layout stays on screen behind the window, which is what somebody
-- comparing two of them wants.
function Wizard:ExitPreview(revert)
    if previewBar then previewBar:Hide() end

    if revert then
        PUI.Preview:Revert()
    end

    if frame then
        frame:Show()
        self:Render()
    end
end

--------------------------------------------------------------------------------
-- Show / hide
--------------------------------------------------------------------------------

function Wizard:Show(startStep)
    if not frame then BuildFrame() end

    -- Fresh choices each time it opens: the wizard is a decision, not a form
    -- that half-remembers what you did last month. It does start from what is
    -- currently installed, which is not the same thing.
    self.choices = PUI.Installer:NewChoices(PUI.Config.layout)

    -- Somebody whose modules already hold settings of their own - an existing
    -- user of the addons who has just picked up the pack, or anyone re-running it
    -- over a setup they have since changed - starts on "Keep my current setup",
    -- with the reset off and graphics left alone. Nothing on their screen
    -- changes until they click a layout, and then only as a preview until
    -- Install. New players get the pack as it ships.
    if PUI.Modules:HasExistingSetup() then
        self.choices.existing = true
        self.choices.layout = PUI.Layouts.CURRENT
        self.choices.resetFirst = false
        self.choices.graphicsPreset = "none"
    end

    -- Following future layout updates is only on because somebody ticked it: a
    -- re-run keeps their last answer, a first run starts pinned.
    self.choices.track = PUI.Config.installedVersion and PUI.Config.track
        or PUI.Versioning.PINNED
    PUI.Steps:Reset()

    self.stepIndex = 1
    frame:Show()

    if startStep then
        self:GoTo(startStep)
    else
        self:Render()
    end
end

function Wizard:Hide()
    if frame then frame:Hide() end   -- OnHide does the cleanup
    if previewBar then previewBar:Hide() end
end

-- Everything that has to happen however the window went away.
--
-- Called from the frame's OnHide, so it runs for Escape and the close button
-- alike, and it has to be safe to call more than once: hiding an already hidden
-- frame is a no-op but Hide() also calls frame:Hide() explicitly.
function Wizard:OnClosed()
    if previewBar then previewBar:Hide() end

    -- Closing the installer without finishing is backing out, and a layout left
    -- applied would be exactly the silent change this whole design promises not
    -- to make. Keeping one is a decision, and it has its own button.
    if PUI.Preview:IsActive() then
        PUI.Preview:Revert()
        PeaversCommons.Utils.Print(PUI, "Layout undone - your settings are back as they were.")
    end
end

function Wizard:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Wizard:IsShown()
    return frame ~= nil and frame:IsShown()
end

function Wizard:GetFrame()
    return frame
end

-- Width available to a step's content, so steps do not each guess at it.
function Wizard:ContentWidth()
    return FRAME_WIDTH - (CONTENT_INSET * 2)
end

return Wizard
