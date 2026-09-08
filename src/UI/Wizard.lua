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

-- Wide enough for the graphics screen, which is the only two-column page and
-- therefore the one that sets the floor: a preset card and a context dropdown
-- side by side both need room for a sentence.
local FRAME_WIDTH = 760
local FRAME_HEIGHT = 560
local CONTENT_INSET = 24
local FOOTER_HEIGHT = 54
local HEADER_HEIGHT = 76

local frame          ---@type Frame
local contentFrame   ---@type Frame
local titleText      ---@type FontString
local subtitleText   ---@type FontString
local stepRail       ---@type Frame
local backButton     ---@type Button
local nextButton     ---@type Button
local skipButton     ---@type Button
local railDots = {}

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

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(C.bgBase[1], C.bgBase[2], C.bgBase[3], C.bgBase[4])
    frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

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
    local eyebrow = W:CreateLabel(frame, "PEAVERS UI", {
        font = "GameFontNormalSmall",
        color = C.accent,
    })
    eyebrow:SetPoint("TOPLEFT", CONTENT_INSET, -18)

    titleText = W:CreateLabel(frame, "", { size = 18, color = C.text })
    titleText:SetPoint("TOPLEFT", CONTENT_INSET, -36)

    subtitleText = W:CreateLabel(frame, "", {
        font = "GameFontNormalSmall",
        color = C.textMuted,
        width = FRAME_WIDTH - (CONTENT_INSET * 2) - 40,
        wrap = true,
    })
    subtitleText:SetPoint("TOPLEFT", CONTENT_INSET, -58)

    local close = W:CreateButton(frame, "x", {
        variant = "ghost",
        width = 24,
        height = 24,
        onClick = function() Wizard:Hide() end,
    })
    close:SetPoint("TOPRIGHT", -8, -8)

    local headerRule = frame:CreateTexture(nil, "ARTWORK")
    headerRule:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    headerRule:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT)
    headerRule:SetHeight(1)
    headerRule:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)

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
    local footerRule = frame:CreateTexture(nil, "ARTWORK")
    footerRule:SetPoint("BOTTOMLEFT", 0, FOOTER_HEIGHT)
    footerRule:SetPoint("BOTTOMRIGHT", 0, FOOTER_HEIGHT)
    footerRule:SetHeight(1)
    footerRule:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)

    stepRail = CreateFrame("Frame", nil, frame)
    stepRail:SetPoint("BOTTOMLEFT", CONTENT_INSET, 18)
    stepRail:SetSize(200, 18)

    nextButton = W:CreateButton(frame, "Next", {
        variant = "primary",
        width = 110,
        onClick = function() Wizard:Next() end,
    })
    nextButton:SetPoint("BOTTOMRIGHT", -CONTENT_INSET, 14)

    backButton = W:CreateButton(frame, "Back", {
        variant = "secondary",
        width = 90,
        onClick = function() Wizard:Back() end,
    })
    backButton:SetPoint("RIGHT", nextButton, "LEFT", -8, 0)

    skipButton = W:CreateButton(frame, "Not now", {
        variant = "ghost",
        width = 90,
        onClick = function() Wizard:Hide() end,
    })
    skipButton:SetPoint("RIGHT", backButton, "LEFT", -4, 0)

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
-- Step rail
--
-- Five dots, the current one filled and widened into a pill. The point is to
-- answer "how much more of this is there" before the player has to ask, which
-- is most of what makes a wizard tolerable.
--------------------------------------------------------------------------------
local function UpdateRail()
    local steps = PUI.Steps.order
    local x = 0

    for i = 1, #steps do
        local dot = railDots[i]
        if not dot then
            dot = stepRail:CreateTexture(nil, "ARTWORK")
            dot:SetHeight(4)
            railDots[i] = dot
        end

        local isCurrent = (i == Wizard.stepIndex)
        local isDone = (i < Wizard.stepIndex)

        dot:ClearAllPoints()
        dot:SetPoint("LEFT", stepRail, "LEFT", x, 0)
        dot:SetWidth(isCurrent and 20 or 8)

        if isCurrent then
            dot:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        elseif isDone then
            dot:SetColorTexture(C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.8)
        else
            dot:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        end

        dot:Show()
        x = x + (isCurrent and 20 or 8) + 6
    end

    for i = #steps + 1, #railDots do
        railDots[i]:Hide()
    end
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
        local message = W:CreateLabel(page,
            "This page failed to draw: " .. tostring(err) ..
            "\n\nThe rest of the installer still works - use Back, or close and run /pui.", {
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

    previewBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    previewBar:SetBackdropColor(C.bgBase[1], C.bgBase[2], C.bgBase[3], 0.97)
    previewBar:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)

    previewBar.label = W:CreateLabel(previewBar, "", { color = C.text })
    previewBar.label:SetPoint("LEFT", 12, 0)

    local undo = W:CreateButton(previewBar, "Undo", {
        variant = "secondary",
        width = 70,
        height = 24,
        onClick = function() Wizard:ExitPreview(true) end,
    })
    undo:SetPoint("RIGHT", -10, 0)

    local back = W:CreateButton(previewBar, "Back to installer", {
        variant = "primary",
        width = 130,
        height = 24,
        onClick = function() Wizard:ExitPreview(false) end,
    })
    back:SetPoint("RIGHT", undo, "LEFT", -6, 0)

    previewBar:Hide()
end

-- Stand aside so the layout on screen can actually be seen.
function Wizard:EnterPreview(layoutKey)
    if not previewBar then BuildPreviewBar() end

    local layout = PUI.Layouts:Get(layoutKey)
    previewBar.label:SetText("Trying: " .. (layout and layout.name or layoutKey))

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
