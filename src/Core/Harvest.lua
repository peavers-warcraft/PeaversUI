--------------------------------------------------------------------------------
-- Harvest
--
-- Asks the third-party addons on this machine for their own export strings, so
-- the pack can share the author's settings without anybody typing anything.
--
-- WHY THIS EXISTS
--
-- The More stuff page offers a Copy button per addon, and the string behind it
-- has to come from somewhere. Three ways were considered:
--
--   1. Generate it offline from the saved variables on disk. Possible in
--      principle - the compression is LibDeflate and AceSerializer, both pure
--      Lua - and rejected. It means reimplementing each addon's profile
--      assembly against a format with no compatibility promise, and there is no
--      way to test the result short of importing it and looking. A malformed
--      string that imports and is subtly wrong is worse than no button.
--
--   2. Write into their saved variables directly. See the note in Extras.lua.
--
--   3. Ask the addon. Every string produced here comes from that addon's own
--      export function, so it is correct by construction and in the exact format
--      its own import expects. If they change the format, their exporter changes
--      with it and this keeps working.
--
-- Only functions verified to exist in the shipped source of each addon are
-- called, and every one is guarded anyway: an addon that is not installed, or
-- has moved its API, is skipped with a reason rather than throwing.
--
-- WHAT IT IS FOR
--
-- Two audiences, one mechanism. The author runs it to capture their setup and
-- paste it into Extras.lua so it ships. Anybody else who runs it gets a Copy
-- button for their own settings, which is a reasonable thing to want on its own.
--------------------------------------------------------------------------------

local _, PUI = ...

local Harvest = {}
PUI.Harvest = Harvest

--------------------------------------------------------------------------------
-- Sources
--
-- Keyed to match Extras.list, so a captured string finds its entry.
--
-- `api` is only ever a description for the message when something is missing;
-- the call itself is Export(), which does the checking.
--------------------------------------------------------------------------------

Harvest.sources = {
    dandersframes = {
        api = "DandersFrames_Export()",
        -- A documented global, and the addon's own comment says it is there for
        -- "external addon integration (Wago UI Packs, etc.)" - which is exactly
        -- what this is. No profile key: nil means the current profile.
        Export = function()
            local fn = _G.DandersFrames_Export
            if type(fn) ~= "function" then return nil end
            return fn()
        end,
    },

    details = {
        api = "Details:ExportCurrentProfile()",
        Export = function()
            local Details = _G.Details
            if type(Details) ~= "table" or type(Details.ExportCurrentProfile) ~= "function" then
                return nil
            end
            return Details:ExportCurrentProfile()
        end,
    },

    plater = {
        api = "PlaterAPI:ExportProfile()",
        Export = function()
            local API = _G.PlaterAPI
            if type(API) ~= "table" or type(API.ExportProfile) ~= "function" then
                return nil
            end

            -- Exporting needs a profile key, and the current one is the only
            -- sensible answer. Asked for rather than assumed to be "Global".
            local key = type(API.GetCurrentProfileKey) == "function"
                and API:GetCurrentProfileKey() or nil
            if not key then return nil end

            return API:ExportProfile(key)
        end,
    },
}

--------------------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------------------

-- Anything shorter than this is not a profile. Export functions that fail
-- politely tend to return "" or a stub, and storing one would put a Copy button
-- on the page that hands somebody nothing.
local MIN_LENGTH = 32

--- Ask one addon for its current profile.
--- @return string|nil text, string|nil reason
function Harvest:Capture(key)
    local source = self.sources[key]
    if not source then return nil, "nothing here knows how to export that" end

    local ok, result = pcall(source.Export)
    if not ok then
        return nil, "its exporter errored: " .. tostring(result)
    end

    if type(result) ~= "string" or result == "" then
        return nil, "not installed, or " .. source.api .. " is not there any more"
    end

    if #result < MIN_LENGTH then
        return nil, "returned something too short to be a profile (" .. #result .. " characters)"
    end

    return result
end

--- Ask everything that can be asked.
--- @return table { captured = { {key, bytes} }, skipped = { {key, reason} } }
function Harvest:CaptureAll()
    local result = { captured = {}, skipped = {} }

    if not PUI.Config.shared then PUI.Config.shared = {} end

    -- Walked in Extras order rather than pairs order, so the report reads the
    -- same way twice running.
    for _, entry in ipairs(PUI.Extras.list) do
        if self.sources[entry.key] then
            local text, reason = self:Capture(entry.key)
            if text then
                PUI.Config.shared[entry.key] = text
                result.captured[#result.captured + 1] = { key = entry.key, bytes = #text }
            else
                result.skipped[#result.skipped + 1] = { key = entry.key, reason = reason }
            end
        end
    end

    PUI.Config:Save()
    return result
end

-- Forget everything captured on this machine. The shipped strings in Extras.lua
-- are untouched - they are source, not settings.
function Harvest:Clear()
    PUI.Config.shared = {}
    PUI.Config:Save()
end

--------------------------------------------------------------------------------
-- Shipping
--
-- The author's half of the job: turn what was captured into the exact block of
-- Lua that goes into Extras.lua. Long-bracket strings with a padded delimiter,
-- because an export string can contain anything and nothing in it should ever
-- need escaping.
--------------------------------------------------------------------------------

function Harvest:AsLua()
    local shared = PUI.Config.shared or {}
    local lines = {}

    for _, entry in ipairs(PUI.Extras.list) do
        local text = shared[entry.key]
        if text then
            lines[#lines + 1] = "-- " .. entry.name .. ", captured " ..
                date("%Y-%m-%d") .. ", " .. #text .. " characters"
            lines[#lines + 1] = "-- Paste into the '" .. entry.key .. "' entry in src/Core/Extras.lua"
            lines[#lines + 1] = "text = [==[" .. text .. "]==],"
            lines[#lines + 1] = ""
        end
    end

    if #lines == 0 then
        return nil
    end

    return table.concat(lines, "\n")
end

-- How many addons on this machine can be asked at all. Used by the page to
-- decide whether offering a Capture button makes any sense.
function Harvest:AvailableCount()
    local count = 0
    for key in pairs(self.sources) do
        if select(1, self:Capture(key)) then count = count + 1 end
    end
    return count
end

return Harvest
