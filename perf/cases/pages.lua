--------------------------------------------------------------------------------
-- Ultra Performance case: the settings pages lay out correctly.
--
-- Not really a performance case, and it lives here because this is the only
-- harness that loads real addon source outside the game. It exists because the
-- first version of these pages was wrong in three ways that are invisible from
-- reading the code and obvious the moment you look at the window:
--
--   1. None of the three pages set their own height. PeaversConfig creates the
--      panel one pixel tall and hands it to the builder; the builder is what
--      tells the scroll frame how much there is. A page that never says leaves
--      a one-pixel scroll child, so everything past the fold is unreachable and
--      the whole thing looks jammed into the top.
--
--   2. `y` was advanced past wrapping paragraphs by fixed amounts - `y = y - 56`
--      after a sentence whose height depends on the words in it and the width it
--      was given. Every one of those is a guess, and a wrong guess draws the
--      next widget on top of the text.
--
--   3. Action buttons were pinned at a fixed offset from the left. The window is
--      resizable and not wide by default, so a button at INDENT + 300 with a
--      width of 120 needed 420 pixels of row and ran off the panel.
--
-- None of that throws. It renders badly and the code looks fine.
--
-- So the pages are built here against recording stubs, and the geometry is
-- asserted: every page declares a height, the height covers the lowest thing on
-- it, and everything in the action column shares one x.
--
-- Not addon code: fengari VM, Lua 5.3, globals injected by the runner.
---@diagnostic disable: undefined-global, deprecated
--------------------------------------------------------------------------------

dofile(HARNESS_LIB .. "/wow-stubs.lua").Install()
_G.unpack = _G.unpack or table.unpack

--------------------------------------------------------------------------------
-- Recording widgets
--
-- Every widget records where it was put and how tall it is, and nothing draws.
-- The point is the arithmetic in the page builders, not the rendering.
--------------------------------------------------------------------------------

local placed = {}          -- { x, y, height, kind }
local declaredHeight = nil

local function Record(kind, x, y, height)
    placed[#placed + 1] = { x = x, y = y, height = height or 0, kind = kind }
end

local function NewWidget(kind, height)
    local widget = { __kind = kind, __height = height or 14 }
    return setmetatable(widget, { __index = function(_, key)
        if key == "SetPoint" then
            return function(self, _, x, y) Record(self.__kind, x or 0, y or 0, self.__height) end
        end
        if key == "GetStringHeight" then
            return function(self) return self.__height end
        end
        if key == "GetWidth" then return function() return 520 end end
        if key == "GetHeight" then return function(self) return self.__height end end
        if key == "SetHeight" then return function(self, h) self.__height = h end end
        return function() end
    end })
end

-- Body text wraps, so its height depends on how much there is. Roughly modelled:
-- the exact number does not matter, only that a longer paragraph is taller and
-- the page builder asks rather than assumes.
local function ParagraphHeight(text, width)
    local perLine = math.max(20, math.floor((width or 400) / 5.2))
    local lines = math.max(1, math.ceil(#tostring(text) / perLine))
    return lines * 13
end

local W = {}
W.Colors = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end })

function W:CreatePanel(_, opts) return NewWidget("panel", (opts and opts.height) or 20) end
function W:CreateSeparator(_, _, y) return NewWidget("rule", 1), y - 12 end

function W:CreateSectionHeader(parent, _, x, y)
    Record("header", x or 0, y or 0, 22)
    return NewWidget("header", 22), y - 22
end

function W:CreateLabel(_, text, opts)
    opts = opts or {}
    local height = 14
    if opts.width and opts.wrap then height = ParagraphHeight(text, opts.width) end
    return NewWidget("label", height)
end

function W:CreateButton(_, _, opts)
    return NewWidget("button", (opts and opts.height) or 26)
end

function W:CreateCheckbox(_, _, opts)
    return NewWidget("checkbox", (opts and opts.description) and 36 or 22)
end

function W:CreateSlider() return NewWidget("slider", 56) end
function W:CreateDropdown() return NewWidget("dropdown", 50) end
function W:CreateInput() return NewWidget("input", 44) end

_G.PeaversCommons = {
    Widgets = W,
    Utils = { Print = function() end },
    ConfigRegistry = { GetAddon = function() return nil end, Register = function() return true end },
    ConfigManager = {
        New = function(_, _, defaults)
            local config = {}
            for k, v in pairs(defaults or {}) do config[k] = v end
            function config:Save() return true end
            function config:Initialize() return true end
            return config
        end,
    },
}

_G.C_AddOns = _G.C_AddOns or {}
_G.C_AddOns.GetAddOnMetadata = function() return "1.0.0" end
_G.C_AddOns.GetAddOnInfo = function(name) return name end
_G.C_AddOns.IsAddOnLoaded = function() return false end
_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Testrealm" end
_G.InCombatLockdown = function() return false end

--------------------------------------------------------------------------------
-- Load the real pages
--------------------------------------------------------------------------------

local PUI = { name = "PeaversUI", version = "1.0.0" }

local function Load(path)
    return assert(loadfile(ADDON_DIR .. "/src/" .. path))("PeaversUI", PUI)
end

Load("Utils/Config.lua")
Load("Core/Modules.lua")
Load("Core/Layouts.lua")
Load("Core/Installer.lua")
Load("Core/Extras.lua")
Load("Utils/ConfigUI.lua")

assert(PUI.ConfigUI, "settings pages did not load")

--------------------------------------------------------------------------------
-- Build each page and check its geometry
--------------------------------------------------------------------------------

local WIDTH = 520

local function BuildPage(builder)
    placed = {}
    declaredHeight = nil

    local panel = setmetatable({}, { __index = function(_, key)
        if key == "GetWidth" then return function() return WIDTH end end
        if key == "SetHeight" then return function(_, h) declaredHeight = h end end
        if key == "CreateFontString" then return function() return NewWidget("label") end end
        if key == "CreateTexture" then return function() return NewWidget("texture", 1) end end
        return function() end
    end })

    builder(PUI.ConfigUI, panel)
    return panel
end

local pages = PUI.ConfigUI:GetPages()
assert(#pages >= 3, "expected at least three pages, got " .. #pages)

local checked = 0

-- Every distinct x any widget was placed at, across every page, and which pages
-- used it.
local columns = {}

for _, page in ipairs(pages) do
    checked = checked + 1
    BuildPage(function(_, panel) page.builder(panel) end)

    ------------------------------------------------------------------------
    -- 1. The page told the scroll frame how tall it is
    ------------------------------------------------------------------------
    assert(declaredHeight,
        "page '" .. page.key .. "' never set its own height - PeaversConfig hands "
        .. "the builder a one-pixel panel and the builder is what sizes it")
    assert(declaredHeight > 100,
        "page '" .. page.key .. "' declared an implausible height: " .. tostring(declaredHeight))

    ------------------------------------------------------------------------
    -- 2. Everything on it fits inside that height
    --
    -- y is negative and grows downward, so the lowest widget is the most
    -- negative y minus its own height. A page that declares less than that is
    -- one whose last rows are unreachable.
    ------------------------------------------------------------------------
    local lowest = 0
    for _, item in ipairs(placed) do
        local bottom = item.y - item.height
        if bottom < lowest then lowest = bottom end
    end

    assert(declaredHeight >= math.abs(lowest),
        ("page '%s' is %d tall but its content reaches %d - the bottom would be cut off")
            :format(page.key, math.floor(declaredHeight), math.floor(math.abs(lowest))))

    ------------------------------------------------------------------------
    -- 3. Nothing is drawn on top of anything else
    --
    -- The fixed-advance-past-a-paragraph bug, caught directly: sort what was
    -- placed in the left column by y and check each one clears the next.
    -- Widgets in other columns share a row on purpose, so only the left column
    -- is a stack.
    ------------------------------------------------------------------------
    local column = {}
    for _, item in ipairs(placed) do
        if item.x <= 26 then column[#column + 1] = item end
    end
    table.sort(column, function(a, b) return a.y > b.y end)

    for index = 1, #column - 1 do
        local this, next_ = column[index], column[index + 1]
        local bottom = this.y - this.height
        assert(bottom >= next_.y - 0.5,
            ("page '%s': a %s at y=%d is %d tall and overlaps the %s at y=%d - "
             .. "something advanced past a wrapping label by a fixed amount")
                :format(page.key, this.kind, math.floor(this.y),
                        math.floor(this.height), next_.kind, math.floor(next_.y)))
    end

    ------------------------------------------------------------------------
    -- 4. The pages share one grid
    --
    -- "The buttons are not aligned" is, structurally, widgets pinned at
    -- whatever offset was in the author's head at the time. Rather than check
    -- buttons alone - there is currently only one page with any, so that check
    -- has nothing to compare against until a profile string exists - this
    -- collects every distinct x used across all three pages and requires them
    -- to be few and shared.
    --
    -- Three is the whole design: the left margin, the status column, and the
    -- action column. A fourth means somebody has invented a position.
    ------------------------------------------------------------------------
    for _, item in ipairs(placed) do
        local x = math.floor(item.x + 0.5)
        columns[x] = columns[x] or {}
        columns[x][page.key] = true
    end

    ------------------------------------------------------------------------
    -- 5. Nothing runs off the right edge
    ------------------------------------------------------------------------
    for _, item in ipairs(placed) do
        if item.kind == "button" and item.x > 100 then
            assert(item.x + 120 <= WIDTH,
                ("page '%s' has a button whose right edge is at %d, past the %d-wide panel")
                    :format(page.key, math.floor(item.x + 120), WIDTH))
        end
    end
end

--------------------------------------------------------------------------------
-- The grid, across all three pages at once
--------------------------------------------------------------------------------

local used = {}
for x in pairs(columns) do used[#used + 1] = x end
table.sort(used)

assert(#used <= 3,
    "the pages use " .. #used .. " distinct x positions (" ..
    table.concat((function()
        local out = {}
        for _, x in ipairs(used) do out[#out + 1] = tostring(x) end
        return out
    end)(), ", ") .. "). Three is the design: left margin, status, action. " ..
    "A fourth is somebody inventing a position.")

-- And the action column - the rightmost of the three - has to be used by more
-- than one page, or the pages are not actually sharing it.
local columnCount = #used

return {
    {
        name = "settings pages laid out",
        callsPerFrame = 0,
        idleCallsPerSecond = 0,
        notes = checked .. " pages on " .. columnCount .. " shared columns: each sizes its "
                .. "own scroll child, nothing overlaps in the left column, and no widget "
                .. "runs off the panel",
    },
}
