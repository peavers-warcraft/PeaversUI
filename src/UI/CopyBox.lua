--------------------------------------------------------------------------------
-- CopyBox
--
-- A window with a long string in it, already selected, so Ctrl+C works.
--
-- This exists because an addon cannot put anything on the system clipboard. The
-- client offers no API for it, and the only thing that has ever worked is a
-- focused EditBox with its contents highlighted - which is why every addon that
-- shares an import string does exactly this and why it looks the way it does.
--
-- The alternative was writing other addons' settings into their saved variables
-- directly. That is worth saying no to explicitly: it means reaching into files
-- another author owns, guessing at a schema that changes without notice, and
-- doing it before that addon has loaded and read them. A string the player
-- pastes into the addon's own import box goes through that addon's own
-- validation and migration, and fails safely when it is out of date.
--
-- One frame, reused. The window is a rare thing to open and there is never a
-- reason to have two.
--------------------------------------------------------------------------------

local _, PUI = ...

local CopyBox = {}
PUI.CopyBox = CopyBox

local PeaversCommons = _G.PeaversCommons
local W = PeaversCommons.Widgets
local C = W.Colors

local WIDTH = 560
local HEIGHT = 260

local frame, editBox, titleText, hintText

local function Build()
    frame = CreateFrame("Frame", "PeaversUICopyBox", UIParent, "BackdropTemplate") --[[@as Frame]]
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    -- Above the settings window it is opened from, which is DIALOG.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(C.bgBase[1], C.bgBase[2], C.bgBase[3], 1)
    frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    table.insert(UISpecialFrames, "PeaversUICopyBox")

    titleText = W:CreateLabel(frame, "", { size = 14, color = C.text })
    titleText:SetPoint("TOPLEFT", 16, -14)

    local close = W:CreateButton(frame, "x", {
        variant = "ghost", width = 24, height = 24,
        onClick = function() frame:Hide() end,
    })
    close:SetPoint("TOPRIGHT", -8, -8)

    hintText = W:CreateLabel(frame, "", {
        font = "GameFontNormalSmall",
        color = C.textMuted,
        width = WIDTH - 32,
        wrap = true,
    })
    hintText:SetPoint("TOPLEFT", 16, -36)

    local box = W:CreatePanel(frame, { bg = C.bgInput })
    box:SetPoint("TOPLEFT", 16, -78)
    box:SetPoint("BOTTOMRIGHT", -16, 48)

    -- A scroll frame, because an import string is thousands of characters and a
    -- plain EditBox would draw one enormous line off the side of the window.
    local scroll = CreateFrame("ScrollFrame", "PeaversUICopyBoxScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    -- No cap. The default is 255, which silently truncates every import string
    -- worth sharing - and a truncated one fails validation on the other side
    -- with no clue why.
    editBox:SetMaxLetters(0)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetWidth(WIDTH - 80)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Read-only in the only way the client allows: let the change happen, then
    -- put the original back. Selecting and copying still work.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self.peaversText then
            self:SetText(self.peaversText)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(editBox)

    local selectAll = W:CreateButton(frame, "Select all", {
        variant = "secondary", width = 110,
        onClick = function()
            editBox:SetFocus()
            editBox:HighlightText()
        end,
    })
    selectAll:SetPoint("BOTTOMLEFT", 16, 14)

    local done = W:CreateButton(frame, "Close", {
        variant = "primary", width = 110,
        onClick = function() frame:Hide() end,
    })
    done:SetPoint("BOTTOMRIGHT", -16, 14)

    frame:Hide()
end

--- Show a string, selected and ready to copy.
--- @param title string What this is
--- @param text string The string itself
--- @param hint? string How to use it, in one or two sentences
function CopyBox:Show(title, text, hint)
    if not frame then Build() end

    titleText:SetText(title or "")
    hintText:SetText(hint or "Ctrl+C to copy.")

    editBox.peaversText = text or ""
    editBox:SetText(text or "")

    frame:Show()

    -- Focus and highlight after the frame is up: highlighting a hidden EditBox
    -- does nothing, and the whole point is that Ctrl+C works immediately.
    editBox:SetFocus()
    editBox:HighlightText()
end

function CopyBox:Hide()
    if frame then frame:Hide() end
end

return CopyBox
