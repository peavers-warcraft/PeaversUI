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
-- restates one. The system, and why it is that system, is documented in
-- PeaversCommons/src/UI/Style.lua: it is shared with PeaversConfig and with
-- anything else in the collection that draws a settings surface, rather than
-- being a second copy kept here.
local Style = PeaversCommons.Style

-- Wide enough for the graphics screen, which is the only two-column page and
-- therefore the one that sets the floor: a preset card and a context dropdown
-- side by side both need room for a sentence.
local FRAME_WIDTH = 760
-- Deliberately not "tall enough for the longest page", which is what it used to
-- be and what stopped being true the moment the summary grew a row. A window
-- sized to its worst page has to be re-sized every time a page changes, and
-- growing it is not free: at the largest interface sizes the screen is only 720
-- UI units tall, so a taller installer would start hanging off the bottom of the
-- very screens somebody picked a big size to see better.
--
-- So the height is fixed and the content area scrolls. See ContentExtent.
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

-- How far one notch of the wheel moves the page. A row is 30 units, so this is
-- two rows a notch: enough to feel like it moved, small enough to stop on a
-- checkbox you were reading towards.
local SCROLL_STEP = 60

local frame          ---@type Frame
local contentFrame   ---@type ScrollFrame
local scrollTrack    ---@type Texture
local scrollThumb    ---@type Texture
local titleText      ---@type FontString
local subtitleText   ---@type FontString
local stepText       ---@type FontString
local backButton     ---@type Button
local nextButton     ---@type Button

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
    -- The viewport each step's page frame is scrolled inside. It is never
    -- emptied itself; moving between steps swaps the page inside it - see
    -- NewPage.
    --
    -- A ScrollFrame rather than a plain Frame for two reasons, and the first one
    -- matters even on a page that fits. A WoW frame does not clip its children,
    -- so a page taller than this area did not overflow in any visible way - it
    -- simply drew straight through the footer rule, over "STEP 6 OF 6" and
    -- across the Install button. A ScrollFrame clips, so the worst a long page
    -- can now do is end at the bottom of the viewport.
    --
    -- The second is that the page is then reachable: the wheel scrolls it and
    -- the strip down the right edge says there is more.
    ----------------------------------------------------------------------------
    contentFrame = CreateFrame("ScrollFrame", nil, frame) --[[@as ScrollFrame]]
    contentFrame:SetPoint("TOPLEFT", CONTENT_INSET, -(HEADER_HEIGHT + 12))
    contentFrame:SetPoint("BOTTOMRIGHT", -CONTENT_INSET, FOOTER_HEIGHT + 8)
    contentFrame:EnableMouseWheel(true)
    contentFrame:SetScript("OnMouseWheel", function(_, delta)
        Wizard:ScrollBy(-delta * SCROLL_STEP)
    end)

    -- The quietest scrollbar that still counts as one: a hairline track with a
    -- thumb on it, both hidden outright when there is nothing to scroll. It is
    -- an indicator rather than a control - the wheel does the scrolling - so it
    -- takes no clicks and no width from the page.
    scrollTrack = frame:CreateTexture(nil, "ARTWORK")
    scrollTrack:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 3, 0)
    scrollTrack:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 3, 0)
    -- The same three units a selected row's bar is wide, and white rather than
    -- the accent: the accent means "you chose this" everywhere else in the
    -- window, and a scroll position is not a choice.
    scrollTrack:SetWidth(Style.Row.bar)
    scrollTrack:SetColorTexture(1, 1, 1, Style.Rule.chrome)
    scrollTrack:Hide()

    scrollThumb = frame:CreateTexture(nil, "OVERLAY")
    scrollThumb:SetWidth(Style.Row.bar)
    scrollThumb:SetColorTexture(1, 1, 1, Style.Alpha.muted)
    scrollThumb:Hide()

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
    -- There is no third button. "Not now" used to sit here as a bare text link
    -- beside two bordered ones, which read as something half-drawn rather than
    -- as a quieter choice. Escape and the close glyph both leave the installer,
    -- and neither of them has to be styled to be understood.
    backButton:SetPoint("RIGHT", nextButton, "LEFT", -8, 0)

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
local scrollRange = 0

local function NewPage()
    if currentPage then
        currentPage:Hide()
        currentPage:ClearAllPoints()
        currentPage:SetParent(nil)
    end

    currentPage = CreateFrame("Frame", nil, contentFrame)
    -- A scroll child needs a size of its own rather than SetAllPoints: its
    -- height is what the ScrollFrame scrolls through, and it is not known until
    -- the step has drawn itself. The viewport height stands in until then, so a
    -- page that fits needs no second pass to look right.
    currentPage:SetSize(contentFrame:GetWidth(), contentFrame:GetHeight())

    -- No SetPoint of our own. SetScrollChild anchors the child's top left to the
    -- viewport's, and scrolling works by moving that anchor - a point pinned
    -- here as well would be a second opinion about where the page lives, and the
    -- one that does not move.
    contentFrame:SetScrollChild(currentPage)
    contentFrame:SetVerticalScroll(0)
    return currentPage
end

--------------------------------------------------------------------------------
-- How tall the page came out
--
-- Asked of the drawn frame rather than reported by the step, because a step
-- would have to return a number it does not otherwise need - and the number it
-- returned would be a guess about wrapped text, which is the exact habit these
-- pages were rewritten to break. Every widget is already placed by the time this
-- runs, so the answer is available for the asking.
--
-- Recursive, and it has to be. The graphics step draws into two column frames
-- declared one unit tall, so a column's own bottom edge says nothing about the
-- rows hanging off it; only the rows themselves know. Regions are walked as well
-- as children because a font string is a region, and a trailing paragraph with
-- nothing after it is the lowest thing on the summary page.
--------------------------------------------------------------------------------
local function LowestPoint(object, lowest)
    for _, region in ipairs({ object:GetRegions() }) do
        if region.GetBottom and region:IsShown() then
            local bottom = region:GetBottom()
            if bottom and bottom < lowest then lowest = bottom end
        end
    end

    for _, child in ipairs({ object:GetChildren() }) do
        if child:IsShown() then
            local bottom = child:GetBottom()
            if bottom and bottom < lowest then lowest = bottom end
            lowest = LowestPoint(child, lowest)
        end
    end

    return lowest
end

-- How far the page actually drew, or nil when it has no rectangle yet - which
-- happens if a step is rendered while the window is hidden. Nothing is on screen
-- to overflow in that case, and the deferred pass in Render measures properly.
local function ContentExtent(page)
    local top = page:GetTop()
    if not top then return nil end
    return top - LowestPoint(page, top)
end

-- Size the page to what it drew, and say so on the right-hand strip.
local function UpdateScroll()
    if not currentPage then return end

    local viewport = contentFrame:GetHeight()
    -- Measured against the viewport rather than against the page's current
    -- height, which is the value about to be overwritten: taking the larger of
    -- the two would let a page only ever grow, so a step that got shorter - the
    -- review page turning into the shorter result page - would keep a scrollbar
    -- for content that is no longer there.
    local extent = math.max(viewport, ContentExtent(currentPage) or viewport)
    currentPage:SetHeight(extent)

    scrollRange = math.max(0, extent - viewport)

    if scrollRange <= 0 then
        contentFrame:SetVerticalScroll(0)
        scrollTrack:Hide()
        scrollThumb:Hide()
        return
    end

    scrollTrack:Show()
    scrollThumb:Show()

    -- The thumb is as tall a fraction of the track as the viewport is of the
    -- page, with a floor so it stays findable on a very long page.
    local height = math.max(24, viewport * (viewport / extent))
    local offset = contentFrame:GetVerticalScroll()
    local travel = viewport - height

    scrollThumb:SetHeight(height)
    scrollThumb:ClearAllPoints()
    scrollThumb:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 3,
        -(travel * (offset / scrollRange)))
end

function Wizard:ScrollBy(delta)
    if not contentFrame or scrollRange <= 0 then return end

    local offset = contentFrame:GetVerticalScroll() + delta
    if offset < 0 then offset = 0 end
    if offset > scrollRange then offset = scrollRange end

    contentFrame:SetVerticalScroll(offset)
    UpdateScroll()
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
    nextButton:SetLabel(step.nextLabel or "Next")

    -- After Build, and after the error label above, so that whichever of the two
    -- actually drew is what gets measured.
    UpdateScroll()

    -- And again next frame. A frame that was created and anchored in this same
    -- pass can still report no rectangle until the layout settles, and a page
    -- measured as nothing would silently lose its scrollbar. The second pass
    -- costs one frame of nothing and always has real numbers to work with.
    C_Timer.After(0, UpdateScroll)

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

-- Set while the window is being hidden to get out of its own way, rather than
-- because somebody left.
--
-- The cleanup hangs off the frame's OnHide so that Escape and the close glyph
-- both reach it, and standing aside hides the same frame - so without this the
-- button marked "hide the installer and look" reverted the layout it was about
-- to show you, printed "Layout undone", and then raised a strip saying "Trying:
-- Standard" over an interface that was no longer trying anything.
local standingAside = false

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
        variant = "primary", width = 132, height = 26,
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

    -- Bracketed rather than set and left: Hide fires OnHide synchronously, so
    -- the flag is only ever true for the length of that one call.
    standingAside = true
    if frame then frame:Hide() end
    standingAside = false

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

    -- A first install starts on the size this screen wants; every later run
    -- starts on the size this account already holds, which NewChoices has
    -- already filled in.
    --
    -- Only a first install, and deliberately: re-running the wizard on a machine
    -- whose monitor disagrees with the one the pack was set up on must not
    -- quietly resize an interface somebody is happy with. The suggestion is
    -- still marked on the size screen either way, so it is one click away rather
    -- than applied behind them.
    if PUI.Config.canvas == nil and not PUI.Config.installedVersion then
        self.choices.canvas = PUI.Layouts:RecommendedCanvas()
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
    -- The window standing aside so a layout can be looked at is not the window
    -- being closed, and the strip it leaves behind carries the undo.
    if standingAside then return end

    if previewBar then previewBar:Hide() end

    -- Before the revert below, not after: the size step settles its re-apply on
    -- a timer, and one still in flight would land after the restore and put the
    -- layout back on a screen that had just been handed back.
    PUI.Steps:CancelPending()

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
