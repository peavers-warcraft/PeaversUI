--------------------------------------------------------------------------------
-- PeaversUI layout preview
--
-- A small schematic of the screen, drawn from the layout data itself. Pick a
-- layout on the left, see where its frames land on the right.
--
-- Drawn rather than photographed, on purpose. Screenshots are the obvious way to
-- illustrate a UI pack and they are the wrong one here: they are megabytes, they
-- go stale the first time a number in Layouts.lua changes, and they show
-- somebody else's screen at somebody else's resolution. A schematic generated
-- from the same table the installer applies cannot drift, costs nothing, and -
-- because it is scaled against the real UIParent - is drawn at the aspect ratio
-- of the monitor the player is actually looking at. A layout that fits on
-- ultrawide and crowds on 16:9 shows that here, before it is applied.
--
-- It also reflects the choices already made: a module switched off on the
-- previous screen is not drawn, and a module that is not installed is not drawn
-- either. The picture is of what this player would get, not of the layout in the
-- abstract.
--
-- What it is not: a render. The boxes are where the frames go and how big they
-- are, not what they look like. Anyone wanting the real thing has the Preview
-- button underneath, which applies the layout to the actual screen.
--------------------------------------------------------------------------------

local _, PUI = ...

local LayoutPreview = {}
PUI.LayoutPreview = LayoutPreview

local PeaversCommons = _G.PeaversCommons
local W = PeaversCommons.Widgets
local C = W.Colors

local Modules = PUI.Modules
local Layouts = PUI.Layouts

-- Fallbacks for reading a value the layout does not set and the module is not
-- around to be asked. Only the handful the schematic needs geometry from.
local FALLBACK = {
    unit = { width = 240, height = 46, x = 0, y = 0 },
    minimap = { size = 155, anchor = "TOPRIGHT", offsetX = 0, offsetY = 0 },
    systembars = { framePoint = "RIGHT", frameX = -20, frameY = 0,
                   frameWidth = 200, barHeight = 20, barSpacing = 2,
                   showTitleBar = true },
    tooltip = { anchorPoint = "BOTTOMRIGHT", anchorX = -230, anchorY = 230 },
}

local UNIT_ORDER = { "player", "target", "targettarget", "focus" }
local UNIT_SHORT = { player = "You", target = "Target", targettarget = "ToT", focus = "Focus" }

--------------------------------------------------------------------------------
-- Reading a value
--
-- Layout first, then whatever the module currently holds, then the fallback.
-- That order is what makes the schematic honest about a partial layout: Compact
-- does not mention the minimap's button grid, so the preview shows the grid the
-- player already has rather than pretending the layout decides it.
--------------------------------------------------------------------------------

local function Read(overrides, config, key, fallback)
    if overrides and overrides[key] ~= nil then return overrides[key] end
    if config and config[key] ~= nil then return config[key] end
    return fallback
end

local function ReadUnit(overrides, config, unitKey, key)
    local layoutUnit = overrides and overrides.units and overrides.units[unitKey]
    if layoutUnit and layoutUnit[key] ~= nil then return layoutUnit[key] end

    if config and config.GetUnit then
        local ok, unit = pcall(config.GetUnit, config, unitKey)
        if ok and unit and unit[key] ~= nil then return unit[key] end
    end

    return FALLBACK.unit[key]
end

--------------------------------------------------------------------------------
-- Geometry
--
-- Everything is converted into one coordinate system: offsets from the centre of
-- the screen, which is how PeaversUnitFrames already thinks and what the preview
-- box scales directly.
--------------------------------------------------------------------------------

-- Where a frame anchored `point` to UIParent's own `point`, offset by (ox, oy),
-- ends up - returned as the centre of the frame.
local function AnchorToCentre(point, ox, oy, w, h, screenW, screenH)
    point = point or "CENTER"

    local ax, ay = 0, 0
    if point:find("LEFT") then ax = -screenW / 2 elseif point:find("RIGHT") then ax = screenW / 2 end
    if point:find("TOP") then ay = screenH / 2 elseif point:find("BOTTOM") then ay = -screenH / 2 end

    local cx, cy = ax + (ox or 0), ay + (oy or 0)

    -- The anchor sits on the frame's own edge, so step inward to its centre.
    if point:find("LEFT") then cx = cx + w / 2 elseif point:find("RIGHT") then cx = cx - w / 2 end
    if point:find("TOP") then cy = cy - h / 2 elseif point:find("BOTTOM") then cy = cy + h / 2 end

    return cx, cy
end

-- How many bars PeaversSystemBars will draw. Asked rather than assumed, because
-- the stat list is that addon's to change.
local function SystemBarCount()
    local ref = Modules:Ref(Modules.byKey.systembars)
    local order = ref and ref.SystemStats and ref.SystemStats.STAT_ORDER
    return order and #order or 4
end

-- Every box the schematic should draw, in screen-centre coordinates.
-- @return table of { key, label, x, y, w, h, kind }
function LayoutPreview:Boxes(layoutKey, choices, screenW, screenH)
    local layout = Layouts:Get(layoutKey)
    local overrides = layout and layout.overrides or {}
    local boxes = {}

    local function wants(moduleKey)
        local module = Modules.byKey[moduleKey]
        if not module or not Modules:IsAvailable(module) then return false end
        if choices and choices.modules and choices.modules[moduleKey] == false then return false end
        return true
    end

    ----------------------------------------------------------------------------
    -- Unit frames
    ----------------------------------------------------------------------------
    if wants("unitframes") then
        local config = Modules:ConfigOf(Modules.byKey.unitframes)
        local uf = overrides.unitframes

        for _, unitKey in ipairs(UNIT_ORDER) do
            local enabled = ReadUnit(uf, config, unitKey, "enabled")
            if enabled ~= false then
                boxes[#boxes + 1] = {
                    key = unitKey,
                    label = UNIT_SHORT[unitKey],
                    x = ReadUnit(uf, config, unitKey, "x") or 0,
                    y = ReadUnit(uf, config, unitKey, "y") or 0,
                    w = ReadUnit(uf, config, unitKey, "width") or 200,
                    h = ReadUnit(uf, config, unitKey, "height") or 40,
                    kind = "frame",
                }
            end
        end
    end

    ----------------------------------------------------------------------------
    -- Minimap
    ----------------------------------------------------------------------------
    if wants("minimap") then
        local config = Modules:ConfigOf(Modules.byKey.minimap)
        local mm = overrides.minimap
        local size = Read(mm, config, "size", FALLBACK.minimap.size)
        local anchor = Read(mm, config, "anchor", FALLBACK.minimap.anchor)
        local ox = Read(mm, config, "offsetX", 0)
        local oy = Read(mm, config, "offsetY", 0)

        -- offsetX/offsetY are insets measured inward from the corner, so the
        -- sign is derived from the anchor rather than carried in the value.
        local sx = anchor:find("RIGHT") and -ox or ox
        local sy = anchor:find("TOP") and -oy or oy

        local cx, cy = AnchorToCentre(anchor, sx, sy, size, size, screenW, screenH)
        boxes[#boxes + 1] = { key = "minimap", label = "Map", x = cx, y = cy,
                              w = size, h = size, kind = "chrome" }
    end

    ----------------------------------------------------------------------------
    -- System bars
    ----------------------------------------------------------------------------
    if wants("systembars") then
        local config = Modules:ConfigOf(Modules.byKey.systembars)
        local sb = overrides.systembars
        local width = Read(sb, config, "frameWidth", FALLBACK.systembars.frameWidth)
        local barHeight = Read(sb, config, "barHeight", FALLBACK.systembars.barHeight)
        local spacing = Read(sb, config, "barSpacing", FALLBACK.systembars.barSpacing)
        local titleBar = Read(sb, config, "showTitleBar", FALLBACK.systembars.showTitleBar)

        local count = SystemBarCount()
        local height = count * (barHeight + spacing) + (titleBar and 20 or 0)

        local cx, cy = AnchorToCentre(
            Read(sb, config, "framePoint", FALLBACK.systembars.framePoint),
            Read(sb, config, "frameX", FALLBACK.systembars.frameX),
            Read(sb, config, "frameY", FALLBACK.systembars.frameY),
            width, height, screenW, screenH)

        boxes[#boxes + 1] = { key = "systembars", label = "FPS", x = cx, y = cy,
                              w = width, h = height, kind = "chrome" }
    end

    ----------------------------------------------------------------------------
    -- Tooltip
    --
    -- Only when it is parked. In cursor mode there is no fixed place to draw,
    -- and a box in the middle of the schematic would be a lie about where it
    -- appears - the caption says so instead.
    ----------------------------------------------------------------------------
    if wants("tooltip") then
        local config = Modules:ConfigOf(Modules.byKey.tooltip)
        local tt = overrides.tooltip
        if Read(tt, config, "anchorMode", "cursor") == "anchor" then
            local w, h = 220, 130
            local cx, cy = AnchorToCentre(
                Read(tt, config, "anchorPoint", FALLBACK.tooltip.anchorPoint),
                Read(tt, config, "anchorX", FALLBACK.tooltip.anchorX),
                Read(tt, config, "anchorY", FALLBACK.tooltip.anchorY),
                w, h, screenW, screenH)
            boxes[#boxes + 1] = { key = "tooltip", label = "Tip", x = cx, y = cy,
                                  w = w, h = h, kind = "ghost" }
        end
    end

    ----------------------------------------------------------------------------
    -- Chat
    --
    -- Drawn faintly and always in the same place, because PeaversChat restyles
    -- the chat window without moving it - where it sits is still Blizzard's, and
    -- yours if you have dragged it. Showing it keeps the schematic honest about
    -- what else is on screen; drawing it like the others would claim the layout
    -- decides something it does not.
    ----------------------------------------------------------------------------
    if wants("chat") then
        local w, h = 430, 170
        local cx, cy = AnchorToCentre("BOTTOMLEFT", 24, 30, w, h, screenW, screenH)
        boxes[#boxes + 1] = { key = "chat", label = "Chat", x = cx, y = cy,
                              w = w, h = h, kind = "ghost" }
    end

    return boxes
end

--------------------------------------------------------------------------------
-- The widget
--------------------------------------------------------------------------------

-- @param parent Frame
-- @param opts table { width = number }
-- @return Frame with :SetLayout(layoutKey, choices)
function LayoutPreview:Create(parent, opts)
    opts = opts or {}
    local width = opts.width or 360

    -- Match the player's own screen. A 16:9 box would misrepresent an ultrawide
    -- exactly where it matters most: how far apart the frames end up.
    local screenW = UIParent:GetWidth() or 1024
    local screenH = UIParent:GetHeight() or 768
    local height = math.floor(width * (screenH / screenW) + 0.5)

    local frame = W:CreatePanel(parent, {
        width = width,
        height = height,
        bg = C.bgNested,
    })

    -- A faint horizon so the box reads as a screen rather than an empty panel,
    -- and so "low on the screen" is something you can see rather than infer.
    local horizon = frame:CreateTexture(nil, "ARTWORK")
    horizon:SetPoint("LEFT", 1, 0)
    horizon:SetPoint("RIGHT", -1, 0)
    horizon:SetHeight(1)
    horizon:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.6)

    local centreMark = frame:CreateTexture(nil, "ARTWORK")
    centreMark:SetSize(1, 9)
    centreMark:SetPoint("CENTER", 0, 0)
    centreMark:SetColorTexture(C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.35)

    local pool = {}
    local scale = width / screenW

    local KIND = {
        frame  = { fill = { C.accent[1], C.accent[2], C.accent[3], 0.28 }, edge = C.accent },
        chrome = { fill = { C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.22 }, edge = C.textMuted },
        ghost  = { fill = { C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.08 }, edge = C.border },
    }

    local function Acquire(index)
        local box = pool[index]
        if box then return box end

        box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        box.label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        box.label:SetPoint("CENTER", 0, 0)
        pool[index] = box
        return box
    end

    -- @param layoutKey string
    -- @param choices table|nil  so the picture reflects the modules still ticked
    function frame:SetLayout(layoutKey, choices)
        local boxes = LayoutPreview:Boxes(layoutKey, choices, screenW, screenH)

        for index, spec in ipairs(boxes) do
            local box = Acquire(index)
            local style = KIND[spec.kind] or KIND.chrome

            local w = math.max(6, spec.w * scale)
            local h = math.max(4, spec.h * scale)

            box:SetSize(w, h)
            box:ClearAllPoints()
            box:SetPoint("CENTER", frame, "CENTER", spec.x * scale, spec.y * scale)
            box:SetBackdropColor(unpack(style.fill))
            box:SetBackdropBorderColor(style.edge[1], style.edge[2], style.edge[3], 0.9)

            -- Only label a box with room for the word. A clipped caption is
            -- worse than none: it reads as a rendering bug.
            if w >= 34 and h >= 12 then
                box.label:SetText(spec.label)
                box.label:SetTextColor(C.text[1], C.text[2], C.text[3], 0.85)
                box.label:Show()
            else
                box.label:Hide()
            end

            box:Show()
        end

        for index = #boxes + 1, #pool do
            pool[index]:Hide()
        end
    end

    -- The one thing the boxes cannot say, said in words underneath.
    function frame:Caption(layoutKey)
        local layout = Layouts:Get(layoutKey)
        local overrides = layout and layout.overrides or {}
        local notes = {}

        local tt = overrides.tooltip
        if tt and tt.anchorMode == "cursor" then
            notes[#notes + 1] = "tooltips follow the cursor"
        elseif tt and tt.anchorMode == "anchor" then
            notes[#notes + 1] = "tooltips parked"
        end

        local mm = overrides.minimap
        if mm and mm.visibility == "hover" then
            notes[#notes + 1] = "addon buttons on hover"
        elseif mm and mm.visibility == "always" then
            notes[#notes + 1] = "addon buttons always shown"
        end

        if #notes == 0 then return "" end
        return table.concat(notes, " - ")
    end

    return frame
end

return LayoutPreview
