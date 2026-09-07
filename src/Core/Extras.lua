--------------------------------------------------------------------------------
-- Extras
--
-- The addons this pack does not ship but plays well with, and where a profile
-- has been shared, the string that sets one up the way the pack's author runs
-- it.
--
-- Pure data. Nothing here is installed, downloaded, enabled or written to - the
-- pack has no way to do any of those things and should not pretend otherwise.
-- What it can do is tell you what exists, whether you already have it, and hand
-- you a string to paste into that addon's own import box.
--
-- WHY A STRING AND NOT A WRITE
--
-- The obvious implementation is to write these settings into the other addon's
-- saved variables directly. It is worth saying no to that explicitly, because it
-- looks like the helpful option:
--
--   * It means reaching into a file another author owns, against a schema that
--     changes without notice and has no compatibility promise to us.
--   * It has to happen before that addon loads and reads them, so a mistake is
--     invisible until their settings are already gone.
--   * There is no undo. Their own profile system has one.
--
-- A string pasted into the addon's own import box goes through that addon's
-- validation and migration, and fails safely and legibly when it is out of
-- date. It is slower by one paste and better in every other way.
--
-- ADDING A PROFILE STRING
--
-- `profile.text` is the shared string, and it is nil for everything until
-- somebody puts one there. To add one:
--
--   1. Set the addon up the way it should ship.
--   2. Export from that addon's own UI - `how` below is the exact path.
--   3. Paste the string as `profile.text`, as a long-bracket string so nothing
--      in it needs escaping:  text = [==[ ... ]==]
--
-- A missing string is not a problem: the entry still lists the addon, still
-- says whether it is installed, and still explains what it is for. The page
-- just does not offer a Copy button for it.
--
-- LINKS
--
-- A url is only given where the project's address is known for certain. An
-- invented CurseForge slug 404s, which is worse than no link at all - so
-- several entries below deliberately have none, and name the addon instead.
--------------------------------------------------------------------------------

local _, PUI = ...

local Extras = {}
PUI.Extras = Extras

local CURSE = "https://www.curseforge.com/wow/addons/"

Extras.categories = { "frames", "combat", "dungeon", "quality" }

Extras.categoryNames = {
    frames  = "Frames and bars",
    combat  = "Combat",
    dungeon = "Dungeons and raids",
    quality = "Quality of life",
}

Extras.list = {
    ----------------------------------------------------------------------------
    -- Frames and bars
    ----------------------------------------------------------------------------
    {
        key = "dandersframes",
        name = "DandersFrames",
        folders = { "DandersFrames" },
        category = "frames",
        blurb = "Raid and party frames.",
        why = "The one piece of the interface this pack deliberately does not " ..
              "replace. Group frames are where healing decisions get made and " ..
              "they deserve a specialist.",
        -- Address not confirmed; naming it rather than guessing a slug.
        url = nil,
        profile = {
            how = "DandersFrames options - Profiles - Import.",
            text = nil,
        },
    },
    {
        key = "bartender4",
        name = "Bartender4",
        folders = { "Bartender4" },
        category = "frames",
        blurb = "Action bars.",
        why = "Blizzard's own bars are fine until you want them somewhere " ..
              "specific. The pack leaves action bars alone precisely so this " ..
              "can own them.",
        url = CURSE .. "bartender4",
        profile = {
            how = "/bt - Profiles - and use the profile list. Bartender shares " ..
                  "profiles between characters rather than by string, so this " ..
                  "one is settings to copy rather than a string to paste.",
            text = nil,
        },
    },
    {
        key = "cooldownmanagercentered",
        name = "CooldownManagerCentered",
        folders = { "CooldownManagerCentered" },
        category = "frames",
        blurb = "Moves the built-in Cooldown Manager where you want it.",
        why = "The client's own Cooldown Manager is good and is stuck where " ..
              "Blizzard put it. PeaversCastBar matches its width, so the two " ..
              "line up once this has moved it.",
        url = nil,
        profile = { how = "Its own options panel.", text = nil },
    },

    ----------------------------------------------------------------------------
    -- Combat
    ----------------------------------------------------------------------------
    {
        key = "details",
        name = "Details! Damage Meter",
        folders = { "Details" },
        category = "combat",
        blurb = "Damage meter.",
        why = "The meter everything else assumes you are running. Worth setting " ..
              "up once so it looks like the rest of the screen rather than a " ..
              "spreadsheet parked on top of it.",
        url = CURSE .. "details",
        profile = {
            how = "/details - Profiles - Import Profile, paste, then Import.",
            text = nil,
        },
    },
    {
        key = "plater",
        name = "Plater Nameplates",
        folders = { "Plater" },
        category = "combat",
        blurb = "Nameplates.",
        why = "Nameplates are the other half of what you actually look at in a " ..
              "pull, and the pack does not touch them.",
        url = CURSE .. "plater-nameplates",
        profile = {
            how = "/plater - Profiles - Import Profile.",
            text = nil,
        },
    },
    {
        key = "dbm",
        name = "Deadly Boss Mods",
        folders = { "DBM-Core" },
        category = "combat",
        blurb = "Boss timers and warnings.",
        why = "Non-negotiable for group content. The settings worth sharing are " ..
              "the ones that stop it shouting over everything else.",
        url = CURSE .. "deadly-boss-mods",
        profile = {
            how = "/dbm - Profiles. DBM shares by profile rather than by string, " ..
                  "so this is a list of what to change rather than something to " ..
                  "paste.",
            text = nil,
        },
    },

    ----------------------------------------------------------------------------
    -- Dungeons and raids
    ----------------------------------------------------------------------------
    {
        key = "warpdeplete",
        name = "WarpDeplete",
        folders = { "WarpDeplete" },
        category = "dungeon",
        blurb = "Mythic+ timer and forces.",
        why = "Replaces the default keystone timer with something you can read " ..
              "at a glance. Pairs with PeaversSplits, which answers a different " ..
              "question - how far ahead of the pace you are, boss by boss.",
        url = CURSE .. "warpdeplete",
        profile = {
            how = "/wd - Profiles.",
            text = nil,
        },
    },
    {
        key = "raiderio",
        name = "RaiderIO",
        folders = { "RaiderIO" },
        category = "dungeon",
        blurb = "Mythic+ scores in tooltips and the group finder.",
        why = "Mostly useful for the group finder. Worth turning most of the " ..
              "rest of it off.",
        url = CURSE .. "raiderio",
        profile = { how = "/rio - its own options.", text = nil },
    },

    ----------------------------------------------------------------------------
    -- Quality of life
    ----------------------------------------------------------------------------
    {
        key = "prat",
        name = "Prat",
        folders = { "Prat-3.0" },
        category = "quality",
        blurb = "Chat features.",
        why = "PeaversChat restyles the chat window and adds links, copy and a " ..
              "position. Prat is what to add if you want the deeper chat " ..
              "features on top - the two coexist.",
        url = CURSE .. "prat-3-0",
        profile = { how = "/prat - Profiles.", text = nil },
    },
    {
        key = "blizzmove",
        name = "BlizzMove",
        folders = { "BlizzMove" },
        category = "quality",
        blurb = "Makes Blizzard's own windows draggable.",
        why = "Small and permanently useful. Every frame the game refuses to let " ..
              "you move, you can move.",
        url = CURSE .. "blizzmove",
        profile = { how = "Its own options panel.", text = nil },
    },
    {
        key = "leatrixplus",
        name = "Leatrix Plus",
        folders = { "Leatrix_Plus" },
        category = "quality",
        blurb = "A large collection of small fixes.",
        why = "Automations and annoyance removals rather than a look. Nothing in " ..
              "it competes with this pack.",
        url = CURSE .. "leatrix-plus",
        profile = { how = "/ltp - and its own settings pages.", text = nil },
    },
}

Extras.byKey = {}
for _, entry in ipairs(Extras.list) do
    Extras.byKey[entry.key] = entry
end

--------------------------------------------------------------------------------
-- Presence
--
-- The same three-valued answer the pack's own modules get, and for the same
-- reason: "installed but not enabled at the character screen" is a different
-- problem from "not installed", and only one of them is solved by downloading
-- something.
--------------------------------------------------------------------------------

-- "loaded" | "disabled" | "missing"
function Extras:Status(entry)
    for _, folder in ipairs(entry.folders or {}) do
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(folder) then
            return "loaded"
        end
    end

    for _, folder in ipairs(entry.folders or {}) do
        if C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(folder) then
            return "disabled"
        end
    end

    return "missing"
end

--- The string behind an entry's Copy button, and where it came from.
---
--- Two sources. `shipped` is what is written into this file and reaches
--- everybody. `captured` is what Harvest asked this machine's own addons for,
--- and is what the author is looking at while they build a pack - so it wins
--- when both exist, or capturing your settings would appear to do nothing.
--- @return string|nil text, string|nil origin  "captured" | "shipped"
function Extras:ProfileText(entry)
    local captured = PUI.Config and PUI.Config.shared and PUI.Config.shared[entry.key]
    if type(captured) == "string" and captured ~= "" then
        return captured, "captured"
    end

    local shipped = entry.profile and entry.profile.text
    if type(shipped) == "string" and shipped ~= "" then
        return shipped, "shipped"
    end

    return nil, nil
end

-- True when there is a string worth offering a Copy button for.
function Extras:HasProfile(entry)
    return (self:ProfileText(entry)) ~= nil
end

-- Entries of one category, in the order they are written above.
function Extras:OfCategory(category)
    local out = {}
    for _, entry in ipairs(self.list) do
        if entry.category == category then out[#out + 1] = entry end
    end
    return out
end

-- How many of these the player already runs, for the page to open with a line
-- that is about them rather than about the list.
function Extras:CountInstalled()
    local installed, total = 0, 0
    for _, entry in ipairs(self.list) do
        total = total + 1
        if self:Status(entry) == "loaded" then installed = installed + 1 end
    end
    return installed, total
end

return Extras
