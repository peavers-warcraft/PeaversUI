--------------------------------------------------------------------------------
-- PeaversUI layouts
--
-- Pure data: three complete looks, each one a set of overrides written into the
-- module addons' own configs. There is no code here on purpose. A layout is
-- something a person should be able to read, disagree with, and change by
-- editing a number - not a function that has to be traced through.
--
-- The overrides are applied as a deep merge over whatever the module already
-- has, so a layout only has to name what it actually changes. Anything it stays
-- quiet about keeps the value the module shipped with.
--
-- Coordinates: PeaversUnitFrames positions every frame as an offset from the
-- centre of UIParent, in UI units. UI units are only the same size on every
-- screen when the UI scale is, which is why each layout also pins the scale -
-- see "The canvas every layout is drawn on" at the bottom. PeaversMiniMap and
-- PeaversSystemBars anchor to a screen corner or edge instead, because a
-- minimap belongs in a corner at every resolution rather than at a fixed
-- distance from the middle.
--
-- Each layout also names a graphics preset and an auto-switch plan. Those are
-- *suggestions* the wizard pre-selects on its graphics screen, never something
-- applied behind the player's back: changing CVars is the one thing in here that
-- touches the game rather than the interface, so it always gets its own
-- explicit yes on a screen that says what it will do.
--
-- `autoSwitch` is what makes this pack worth more than a pile of position
-- values. A preset you pick once is a compromise between the raid you want to
-- survive and the open world you want to look at; a preset per context is not a
-- compromise at all. The keys and the values are PeaversPerformance's own -
-- "none" leaves that context alone, "restore" puts back the settings from
-- before any preset was applied, anything else is a preset key.
--
-- ONE RULE ABOUT MEDIA: a layout never names a font or a bar texture that ships
-- with somebody else's addon. A path into Details or DandersFrames renders as a
-- missing texture for anyone who does not have them, and a UI pack that looks
-- broken on a clean install is worse than one that looks plain.
--
-- Neither fonts nor bar textures are set here at all. PeaversCommons bundles
-- both, and every module falls back to them when `fontFace` or `barTexture` is
-- unset, so the right media arrives by default rather than by three layouts each
-- naming a path. That keeps the house style a one-line change over there rather
-- than a search across this file - and it is why a layout can be a transcription
-- of a screen that used a font and a texture from two other addons without
-- carrying either dependency with it.
--------------------------------------------------------------------------------

local _, PUI = ...

local Layouts = {}
PUI.Layouts = Layouts

-- Familiar first, then the one most people arrive at on their own, then the
-- author's. Somebody opening this screen for the first time should meet the
-- arrangement they already know before they meet anybody's taste.
Layouts.order = { "traditional", "modern", "peavers" }

-- What a fresh account starts on, and what anything handed an unusable key falls
-- back to. The pack's own layout rather than the first card: somebody who went
-- and installed something called PeaversUI has already expressed a preference,
-- and the two above it are there for when it turns out not to suit them.
Layouts.DEFAULT = "peavers"

--------------------------------------------------------------------------------
-- Layouts that used to exist, and what replaced each one
--
-- Compact, Cinematic and Raid were three more variations on one idea - frames
-- low and centred, drawn tighter or looser - which made the layout screen a set
-- of near-misses rather than a choice. They are gone, and the three above answer
-- the question people were actually asking: do I want what I am used to, what
-- the game does now, or what this pack was built as.
--
-- A key nobody can reach any more is still written in somebody's saved
-- variables, so every one of them maps to its nearest survivor. That keeps
-- /pui apply raid working, keeps the settings page able to name what is
-- installed, and is what Versioning:MigrateRetired rewrites an account to -
-- pinned, so the substitution is recorded without anything being applied to a
-- screen somebody was happy with.
--------------------------------------------------------------------------------
Layouts.retired = {
    -- Renamed rather than retired: same layout, honest name.
    standard  = "peavers",
    -- All three were low-and-centred, which is what Modern is.
    compact   = "modern",
    cinematic = "modern",
    raid      = "modern",
}

-- The retired keys that are the same layout wearing a new name, rather than one
-- layout standing in for another. An account on one of these is not being
-- substituted and has nothing to be told: it keeps its revision and its track,
-- and its screen is already exactly what the new key describes.
Layouts.renamed = {
    standard = true,
}

--- The living key an account's stored layout refers to.
--- @param key string|nil
--- @return string|nil
function Layouts:Resolve(key)
    if key == nil or key == self.CURRENT then return key end
    if self.list[key] then return key end
    return self.retired[key]
end

--------------------------------------------------------------------------------
-- The house style, shared by every layout
--
-- Chat and tooltips are the two surfaces where all three layouts agree, and they
-- agree completely: the same flat black window in the same corner, the same
-- parked tooltip. A layout is an arrangement of unit frames and a minimap, not a
-- different opinion about where chat goes.
--
-- Shared by reference rather than copied into each one, which is safe because
-- nothing ever writes into a layout's own table - Layouts:OverridesFor hands out
-- a deep copy and the installer merges that. Three verbatim copies of 45 chat
-- settings is not data, it is three chances for two of them to drift.
--------------------------------------------------------------------------------

local HOUSE_CHAT = {
        enabled = true,
        -- The same flat black the unit frames are painted with, so the
        -- corner of the screen reads as one surface rather than two.
        bgColor = { r = 0, g = 0, b = 0 },
        -- Fully opaque and borderless. Chat sits in a corner over the
        -- world for hours; at 0.6 the world behind it competes with the
        -- text, and the hairline is one more edge to see past.
        background = true,
        bgAlpha = 1.0,
        border = false,
        edgeToEdge = true,
        fontSize = 12,
        fontOutline = "NONE",
        shadow = true,
        fading = false,
        timeVisible = 120,
        maxLines = 1000,
        styleTabs = true,
        tabsInside = true,
        -- Plain tab labels: mixed case and no accent underline. The
        -- selected tab is told apart by its white text alone, which is
        -- quieter than a coloured rule under a word in capitals.
        tabUppercase = false,
        tabUnderline = false,
        tabFontSize = 10,
        -- Arial Narrow ships with the game. Small tabs need a condensed
        -- face or they run into each other.
        tabFont = "Fonts\\ARIALN.TTF",
        paddingLeft = 7,
        paddingRight = 5,
        paddingTop = 5,
        paddingBottom = 5,
        paddingSplit = true,
        styleEditBox = true,
        editBoxPosition = "bottom",
        editBoxHeight = 22,
        editBoxChannelColor = true,
        -- On: the arrow keys walk chat history rather than the cursor.
        altArrowKeys = true,
        showBottomButton = true,
        urlLinks = true,
        urlBrackets = true,
        copyButton = true,
        copyButtonVisibility = "dim",
        copyIconSize = 11,
        copyStripColors = true,
        -- Off: channel names as Blizzard prints them. Abbreviating them
        -- rewrites a hyperlink's display text, and that is what broke
        -- chat in Mythic+ - see PeaversChat's Main.lua.
        shortChannelNames = false,
        timestamps = "default",
        -- Flush into the bottom-left corner. edgeToEdge above is what
        -- makes x = 0 reachable; this is what actually puts it there.
        positionEnabled = true,
        chatPoint = "BOTTOMLEFT",
        chatX = 0,
        -- Off the bottom edge by more than the 22 it was dragged to on
        -- retail: at that height the box reads as sitting on the floor
        -- of the screen rather than resting above it.
        chatY = 60,
        chatWidth = 430,
        chatHeight = 180,
}

local HOUSE_TOOLTIP = {
        enabled = true,
        scale = 1.0,
        fontSize = 12,
        bgAlpha = 0.94,
        borderByQuality = true,
        borderByReaction = true,
        -- Parked, not on the cursor. A tooltip that follows the mouse is
        -- the single biggest thing covering the middle of the screen,
        -- and the middle of the screen is where the fight is.
        anchorMode = "anchor",
        anchorPoint = "BOTTOMRIGHT",
        anchorX = 0,
        anchorY = 224,
        -- Off: the unit frames already carry health, and a second bar
        -- saying the same thing in a different place is noise.
        healthBar = false,
        healthBarPosition = "bottom",
        healthBarHeight = 6,
        healthBarColorByUnit = true,
        healthBarText = "none",
        classColorNames = true,
        showTarget = true,
        showItemID = false,
        showSpellID = false,
        showIcon = false,
        hideInCombat = "never",
}

Layouts.list = {

    ----------------------------------------------------------------------------
    -- Peavers UI
    --
    -- Not a set of defaults: this is the author's own interface, transcribed from
    -- a live install. That is the point of it. Anyone can invent three plausible
    -- arrangements of frames; the one worth shipping is the one somebody
    -- actually plays with, because every value in it has already survived
    -- contact with a raid night.
    --
    -- The shape of it, in case a number below looks arbitrary: four frames on
    -- one line low on the screen, health bars painted flat black with the class
    -- colour thrown away, no power bars, and almost no auras on the player. It
    -- is a layout for somebody who reads their buffs somewhere else and wants
    -- the unit frames to answer exactly one question quickly.
    --
    -- It is named for the pack rather than called "Standard" because it is not
    -- the standard anything - it is one person's taste, and the two layouts
    -- above it are the ones that look like WoW. Saying so on the card is more
    -- use than implying the other two are departures from it.
    ----------------------------------------------------------------------------
    peavers = {
        name = "Peavers UI",
        tagline = "The layout this pack was built from",
        blurb = "Four frames in a row low on the screen, flat black health bars, " ..
                "no power bars, tooltips parked in the bottom-right. Transcribed " ..
                "from a live install rather than invented.",
        graphics = "quality",
        autoSwitch = {
            enabled = true,
            raid = "quality",
            mythicplus = "performance",
            dungeon = "restore",
            world = "restore",
        },

        overrides = {
            unitframes = {
                hideBlizzardFrames = true,
                units = {
                    -- All four sit on one line at y = -395. The x values are a
                    -- matched pair either side of centre plus an outrigger, so
                    -- the row stays symmetrical at any resolution.
                    player = {
                        enabled = true,
                        x = -429, y = -395, width = 170, height = 40,
                        -- Flat black bars: the colour is carried by how full the
                        -- bar is, not by what class is standing in it.
                        healthColorMode = "custom",
                        healthColor = { r = 0, g = 0, b = 0 },
                        healthBgAlpha = 0.3,

                        showPower = false, powerHeight = 6,
                        -- Nearly bare. Buffs and debuffs on your own frame are
                        -- read from somewhere else in this setup.
                        showBuffs = false, maxBuffs = 1,
                        showDebuffs = false,
                        showCastBar = false, castBarIcon = false,
                        -- Never: a tooltip over your own frame is only ever in
                        -- the way of the thing underneath it.
                        tooltip = "never",
                    },
                    target = {
                        enabled = true,
                        x = 429, y = -395, width = 170, height = 40,
                        healthColorMode = "custom",
                        healthColor = { r = 0, g = 0, b = 0 },
                        healthBgAlpha = 0.3,

                        showPower = false, powerHeight = 6,
                        -- Only your own debuffs. On a target covered in twenty
                        -- of everyone's, yours are the ones you can act on.
                        debuffSource = "mine",
                        tooltip = "ooc",
                    },
                    targettarget = {
                        enabled = true,
                        x = 600, y = -395, width = 124,
                        healthColorMode = "custom",
                        healthColor = { r = 0, g = 0, b = 0 },
                        healthBgAlpha = 0.26,

                        healthText = "percent",
                        powerHeight = 6,
                        maxBuffs = 8, maxDebuffs = 8, auraSize = 20,
                        castBarHeight = 14, castBarIcon = false,
                        tooltip = "ooc",
                    },
                    focus = {
                        -- Off, but fully configured, so switching it on from the
                        -- settings puts it in the right place first time rather
                        -- than in the middle of the screen.
                        enabled = false,
                        x = -600, y = -395, width = 170, height = 40,
                        healthColorMode = "custom",
                        healthColor = { r = 0, g = 0, b = 0 },
                        healthBgAlpha = 0.3,

                        showPower = false, powerHeight = 6,
                        showBuffs = true, maxBuffs = 8, maxDebuffs = 8,
                        auraSize = 20,
                        showCastBar = false, castBarIcon = false,
                    },
                },
            },
            minimap = {
                enabled = true,
                squareShape = true,
                size = 155,
                scale = 1,
                borderSize = 0,
                anchorEnabled = true,
                anchor = "TOPRIGHT",
                offsetX = 0,
                offsetY = 0,
                zoneTextMode = "hidden",
                hideZoomButtons = true,
                objectiveTracker = "detach",
                -- Blizzard's own minimap furniture: the calendar, the tracking
                -- cone and the addon compartment are all reachable elsewhere and
                -- all take up a corner. The queue eye stays, because there is
                -- nowhere else to see that you are in a queue.
                widgets = {
                    calendar = "hidden",
                    tracking = "hidden",
                    compartment = "hidden",
                    queueStatus = "corner",
                },
                widgetLayout = {
                    difficulty  = { point = "TOPRIGHT", x = 0, y = 0, scale = 0.75 },
                    indicators  = { point = "TOPLEFT", x = 0, y = 2 },
                    queueStatus = { point = "BOTTOMLEFT", x = 0, y = 0 },
                },
                collectButtons = true,
                visibility = "toggle",
                growDirection = "LEFT",
                buttonSize = 26,
                buttonSpacing = 2,
                buttonsPerRow = 2,
                barBackground = false,
            },
            chat = HOUSE_CHAT,
            tooltip = HOUSE_TOOLTIP,
            castbar = {
                -- Transcribed with the rest of Standard. The player's bar takes
                -- the Cooldown Manager's width and parks under it, which is why
                -- it carries no icon of its own - the row above it is already a
                -- line of icons.
                --
                -- The positions below are the fallback for a client with no
                -- Cooldown Manager to anchor to, which is every Classic client.
                -- They keep the heights from the live install and centre the x,
                -- because the x it was dragged to on retail is an artefact of
                -- the anchor: with the anchor gone it would put the bar out at
                -- the left of the screen rather than under the player.
                units = {
                    player = {
                        enabled = true,
                        width = 220, height = 24,
                        matchCooldownManager = true,
                        anchorToCooldownManager = true,
                        cooldownManagerFrame = "UtilityCooldownViewer",
                        anchorGap = 0,
                        showIcon = false,
                        showSpellName = true, showCastTime = true,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = 0, frameY = -81,
                        hideBlizzard = true,
                    },
                    -- Off, but positioned, so switching one on from Edit Mode
                    -- puts it somewhere sensible rather than wherever the last
                    -- person to drag it left it.
                    target = {
                        enabled = false, width = 193, height = 22,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = 0, frameY = 15, hideBlizzard = true,
                    },
                    focus = {
                        enabled = false, width = 180, height = 20,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = 0, frameY = 43, hideBlizzard = true,
                    },
                    pet = { enabled = false },
                },
            },
            systembars = {
                -- No position here, in this layout or any other: the bars are
                -- docked under the minimap by the loop at the bottom of this
                -- file, which is what puts them at TOPRIGHT, 0, -155, 157 wide.
                barHeight = 13,
                -- Negative spacing overlaps the bars by a pixel, which closes
                -- the seam between them into one solid stack.
                barSpacing = -1,
                bgAlpha = 1.0,
                barBgAlpha = 0.35,

                fontSize = 10,
                showTitleBar = false,
                showFrameBackground = true,
                showStatNames = true,
                showStatValues = true,
                customColors = {
                    -- A dim green for FPS: legible against the dark bar without
                    -- reading as an alert the way a bright colour would.
                    FPS = { r = 0.180, g = 0.408, b = 0.180 },
                },
            },
        },
    },

    ----------------------------------------------------------------------------
    -- Traditional
    --
    -- Where WoW has put the unit frames since 2004: your own frame in the top
    -- left corner, the target beside it, target-of-target beside that. Anybody
    -- who has played this game has read that corner ten thousand times, and the
    -- muscle memory is worth more than any arrangement this pack could invent.
    --
    -- Styled rather than reproduced. The positions are Blizzard's; the flat
    -- bars, the house font and the square minimap are the pack's. The point is
    -- to look like the game you already know rather than like a different one.
    --
    -- Placed from the corner rather than from the centre - see "Frames placed
    -- from a screen edge" further down. This is the layout that needs it: a
    -- top-left frame written as a centre offset is in the corner on the author's
    -- monitor and floating somewhere near the middle on an ultrawide.
    --
    -- Buffs are off on every frame here, and that is a consequence rather than a
    -- preference. PeaversUnitFrames stacks the buff row *above* the frame it
    -- belongs to, so a frame this close to the top of the screen would push its
    -- own buffs off it. Debuffs hang below and are kept, which is the row that
    -- matters on a target anyway - and Blizzard's own buff frame in the opposite
    -- corner is still there, still showing yours.
    ----------------------------------------------------------------------------
    traditional = {
        name = "Traditional",
        tagline = "Frames in the top-left, the way they have always been",
        blurb = "Your frame in the corner, target beside it, the way WoW has laid " ..
                "it out since the beginning - with flat bars and a tidier minimap. " ..
                "Class colours, power bars, nothing to relearn.",
        graphics = "balanced",
        autoSwitch = {
            enabled = true,
            raid = "performance",
            mythicplus = "performance",
            dungeon = "none",
            world = "restore",
        },

        overrides = {
            unitframes = {
                hideBlizzardFrames = true,
                units = {
                    -- A 230-wide frame 32 units in from the left and 36 down
                    -- from the top, so the corner has air around it rather than
                    -- being jammed into it the way Blizzard's own is.
                    player = {
                        enabled = true,
                        edge = "TOPLEFT", edgeX = 147, edgeY = 60,
                        width = 230, height = 48,
                        healthColorMode = "class",
                        healthBgAlpha = 0.25,
                        showPower = true, powerHeight = 6,
                        healthText = "both", fontSize = 11,
                        showCastBar = false,
                        showBuffs = false, maxBuffs = 6,
                        showDebuffs = true, maxDebuffs = 6, auraSize = 20,
                        -- Never on your own frame: it is the one tooltip that
                        -- can only ever cover something you needed to see.
                        tooltip = "never",
                    },
                    -- Beside the player with a 24 unit gap, tops aligned.
                    target = {
                        enabled = true,
                        edge = "TOPLEFT", edgeX = 401, edgeY = 60,
                        width = 230, height = 48,
                        healthColorMode = "class",
                        healthBgAlpha = 0.25,
                        showPower = true, powerHeight = 6,
                        healthText = "both", fontSize = 11,
                        showCastBar = true, castBarHeight = 18, castBarIcon = true,
                        showBuffs = false,
                        -- Only your own, on the frame you are attacking: on a
                        -- boss wearing twenty of everybody's, yours are the ones
                        -- you can do anything about.
                        showDebuffs = true, debuffSource = "mine",
                        maxDebuffs = 8, auraSize = 20,
                        tooltip = "ooc",
                    },
                    targettarget = {
                        enabled = true,
                        edge = "TOPLEFT", edgeX = 601, edgeY = 60,
                        width = 130, height = 30,
                        healthColorMode = "class",
                        healthBgAlpha = 0.25,
                        showPower = false,
                        healthText = "none", fontSize = 10,
                        showCastBar = false,
                        showBuffs = false, showDebuffs = false,
                        maxBuffs = 4, maxDebuffs = 4, auraSize = 16,
                        tooltip = "ooc",
                    },
                    -- Off, but placed, so switching it on from Edit Mode puts it
                    -- under the player rather than in the middle of the screen.
                    -- Below the player's debuff row, not beside it: the top row
                    -- is full by the time you get this far.
                    focus = {
                        enabled = false,
                        edge = "TOPLEFT", edgeX = 127, edgeY = 143,
                        width = 190, height = 38,
                        healthColorMode = "class",
                        healthBgAlpha = 0.25,
                        showPower = true, powerHeight = 5,
                        healthText = "percent", fontSize = 10,
                        showCastBar = true, castBarHeight = 14, castBarIcon = false,
                        showBuffs = false,
                        showDebuffs = true, maxDebuffs = 6, auraSize = 18,
                    },
                },
            },
            minimap = {
                enabled = true,
                -- The one layout that keeps the circle. Squaring it is the
                -- single most obvious sign that an addon has been at the
                -- interface, and this is the layout for somebody who would
                -- rather it did not look like one.
                squareShape = false,
                size = 170,
                scale = 1,
                borderSize = 0,
                anchorEnabled = true,
                anchor = "TOPRIGHT",
                offsetX = 0,
                offsetY = 0,
                zoneTextMode = "hidden",
                hideZoomButtons = true,
                objectiveTracker = "detach",
                widgets = {
                    calendar = "hidden",
                    tracking = "hidden",
                    compartment = "hidden",
                    queueStatus = "corner",
                },
                widgetLayout = {
                    difficulty  = { point = "TOPRIGHT", x = 0, y = 0, scale = 0.75 },
                    indicators  = { point = "TOPLEFT", x = 0, y = 2 },
                    queueStatus = { point = "BOTTOMLEFT", x = 0, y = 0 },
                },
                collectButtons = true,
                visibility = "toggle",
                growDirection = "LEFT",
                buttonSize = 26,
                buttonSpacing = 2,
                buttonsPerRow = 2,
                barBackground = false,
            },
            chat = HOUSE_CHAT,
            tooltip = HOUSE_TOOLTIP,
            castbar = {
                -- The player's bar goes where Blizzard has always drawn it:
                -- centred, a little below the middle of the screen, nowhere near
                -- the frames. The target's is on the target frame instead, which
                -- is why there is no separate bar for it here.
                units = {
                    player = {
                        enabled = true,
                        width = 230, height = 24,
                        matchCooldownManager = false,
                        anchorToCooldownManager = false,
                        anchorGap = 0,
                        showIcon = true,
                        showSpellName = true, showCastTime = true,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = 0, frameY = -190,
                        hideBlizzard = true,
                    },
                    target = {
                        enabled = false, width = 200, height = 22,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = 0, frameY = 15, hideBlizzard = true,
                    },
                    focus = {
                        enabled = false, width = 180, height = 20,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = 0, frameY = 43, hideBlizzard = true,
                    },
                    pet = { enabled = false },
                },
            },
            systembars = {
                barHeight = 14,
                barSpacing = -1,
                bgAlpha = 1.0,
                barBgAlpha = 0.35,
                fontSize = 10,
                showTitleBar = false,
                showFrameBackground = true,
                showStatNames = true,
                showStatValues = true,
            },
        },
    },

    ----------------------------------------------------------------------------
    -- Modern
    --
    -- Where Blizzard moved the frames when it finally let people move them: a
    -- pair low and centred, close enough to the middle of the screen that
    -- reading your own health is not a glance away from the fight. It is what
    -- retail's Edit Mode gives you out of the box, and it is the arrangement
    -- most people who have rearranged their UI arrived at independently.
    --
    -- Centre-relative, unlike Traditional, and correctly so: these frames are
    -- meant to sit either side of the middle, so an offset from the middle is
    -- the honest way to write them. They land in the same place on a 4:3 monitor
    -- and a 21:9 one.
    --
    -- The difference from Peavers UI, which is also low and centred: this keeps
    -- everything Blizzard would have shown you. Class colours rather than flat
    -- black, power bars, health as a number and a percentage, buffs on the
    -- frames. Peavers UI is the same real estate stripped to one question.
    ----------------------------------------------------------------------------
    modern = {
        name = "Modern",
        tagline = "Low and centred, the way Edit Mode arranges it",
        blurb = "A pair of frames low either side of centre, close to the fight " ..
                "rather than off in a corner. Class colours, power bars, health " ..
                "in numbers - everything the game would have shown you.",
        graphics = "quality",
        autoSwitch = {
            enabled = true,
            raid = "balanced",
            mythicplus = "performance",
            dungeon = "none",
            world = "restore",
        },

        overrides = {
            unitframes = {
                hideBlizzardFrames = true,
                units = {
                    player = {
                        enabled = true,
                        x = -310, y = -420, width = 250, height = 50,
                        healthColorMode = "class",
                        healthBgAlpha = 0.25,
                        showPower = true, powerHeight = 7,
                        healthText = "both", fontSize = 12,
                        showCastBar = false,
                        showBuffs = true, maxBuffs = 8,
                        showDebuffs = true, maxDebuffs = 8, auraSize = 20,
                        tooltip = "never",
                    },
                    target = {
                        enabled = true,
                        x = 310, y = -420, width = 250, height = 50,
                        healthColorMode = "class",
                        healthBgAlpha = 0.25,
                        showPower = true, powerHeight = 7,
                        healthText = "both", fontSize = 12,
                        showCastBar = true, castBarHeight = 18, castBarIcon = true,
                        showBuffs = true, maxBuffs = 8, showMount = true,
                        showDebuffs = true, debuffSource = "mine",
                        maxDebuffs = 8, auraSize = 20,
                        tooltip = "ooc",
                    },
                    targettarget = {
                        enabled = true,
                        x = 545, y = -420, width = 130, height = 30,
                        healthColorMode = "class",
                        healthBgAlpha = 0.25,
                        showPower = false,
                        healthText = "none", fontSize = 10,
                        showCastBar = false,
                        showBuffs = false, showDebuffs = false,
                        maxBuffs = 4, maxDebuffs = 4, auraSize = 16,
                        tooltip = "ooc",
                    },
                    focus = {
                        enabled = false,
                        x = -545, y = -420, width = 190, height = 38,
                        healthColorMode = "class",
                        healthBgAlpha = 0.25,
                        showPower = true, powerHeight = 5,
                        healthText = "percent", fontSize = 10,
                        showCastBar = true, castBarHeight = 14, castBarIcon = false,
                        showBuffs = false,
                        showDebuffs = true, maxDebuffs = 6, auraSize = 18,
                    },
                },
            },
            minimap = {
                enabled = true,
                squareShape = true,
                size = 160,
                scale = 1,
                borderSize = 0,
                anchorEnabled = true,
                anchor = "TOPRIGHT",
                offsetX = 0,
                offsetY = 0,
                zoneTextMode = "hidden",
                hideZoomButtons = true,
                objectiveTracker = "detach",
                widgets = {
                    calendar = "hidden",
                    tracking = "hidden",
                    compartment = "hidden",
                    queueStatus = "corner",
                },
                widgetLayout = {
                    difficulty  = { point = "TOPRIGHT", x = 0, y = 0, scale = 0.75 },
                    indicators  = { point = "TOPLEFT", x = 0, y = 2 },
                    queueStatus = { point = "BOTTOMLEFT", x = 0, y = 0 },
                },
                collectButtons = true,
                visibility = "toggle",
                growDirection = "LEFT",
                buttonSize = 24,
                buttonSpacing = 2,
                buttonsPerRow = 3,
                barBackground = false,
            },
            chat = HOUSE_CHAT,
            tooltip = HOUSE_TOOLTIP,
            castbar = {
                -- Under the player frame rather than out in the middle: the
                -- frames are already low and central here, so a bar in the
                -- middle of the screen would be a third thing to look at in
                -- roughly the same place.
                units = {
                    player = {
                        enabled = true,
                        width = 250, height = 24,
                        matchCooldownManager = true,
                        anchorToCooldownManager = true,
                        cooldownManagerFrame = "UtilityCooldownViewer",
                        anchorGap = 0,
                        showIcon = true,
                        showSpellName = true, showCastTime = true,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = -310, frameY = -478,
                        hideBlizzard = true,
                    },
                    target = {
                        enabled = false, width = 200, height = 22,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = 0, frameY = 15, hideBlizzard = true,
                    },
                    focus = {
                        enabled = false, width = 180, height = 20,
                        framePoint = "CENTER", frameRelativePoint = "CENTER",
                        frameX = 0, frameY = 43, hideBlizzard = true,
                    },
                    pet = { enabled = false },
                },
            },
            systembars = {
                barHeight = 14,
                barSpacing = -1,
                bgAlpha = 1.0,
                barBgAlpha = 0.35,
                fontSize = 10,
                showTitleBar = false,
                showFrameBackground = true,
                showStatNames = true,
                showStatValues = true,
            },
        },
    },

}

--------------------------------------------------------------------------------
-- System bars dock to the minimap
--
-- The one piece of arithmetic in this file, and the reason it is arithmetic
-- rather than four more numbers: in every layout the bars sit directly against
-- the minimap's inner edge, so the corner reads as a single block of
-- instrumentation whichever card was clicked. Typed by hand, that relationship
-- lasted exactly until somebody changed one layout's minimap size and not its
-- bars - which is how three of the four ended up with bars floating at the
-- right edge of the screen, nowhere near the map.
--
-- Mirrors PeaversMiniMap's own placement (Square:Apply): the cluster is pinned
-- to `anchor` on UIParent, its offsets point inward from that corner, and its
-- scale applies to the offsets as well as the size. PeaversSystemBars positions
-- its frame against UIParent too, so the bars take the same corner and step
-- past the map by its scaled size - below it for a top corner, above it for a
-- bottom one.
--
-- The bars overhang the map by two pixels. That is transcribed, not invented:
-- it is what the Standard install was set to by eye, and matching it keeps every
-- layout looking like that screen rather than like a slightly different one.
--
-- Locked, because the position is a consequence of the minimap's and dragging
-- the bars away breaks the only thing it is for. Edit Mode can still move them.
--------------------------------------------------------------------------------

local DOCK_OVERHANG = 2

-- Which way "inward" is from each corner. The same table PeaversMiniMap keeps
-- as Square.ANCHORS, restated because this file loads without that addon.
local CORNERS = {
    TOPRIGHT    = { x = -1, y = -1 },
    TOPLEFT     = { x = 1,  y = -1 },
    BOTTOMRIGHT = { x = -1, y = 1 },
    BOTTOMLEFT  = { x = 1,  y = 1 },
}

-- Write the docked position into a layout's systembars block.
function Layouts.DockSystemBars(minimap, bars)
    local corner = CORNERS[minimap.anchor] and minimap.anchor or "TOPRIGHT"
    local inward = CORNERS[corner]
    local scale = minimap.scale or 1
    local edge = (minimap.size or 155) * scale

    bars.framePoint = corner
    bars.frameX = (minimap.offsetX or 0) * scale * inward.x
    bars.frameY = ((minimap.offsetY or 0) * scale + edge) * inward.y
    bars.frameWidth = edge + DOCK_OVERHANG
    bars.lockPosition = true
end

--------------------------------------------------------------------------------
-- The canvas every layout is drawn on
--
-- Every coordinate in this file is in UI units, and how many UI units a screen
-- has depends on its UI scale: 768 tall at a scale of 1.0, 1440 tall at 0.5333.
-- The numbers above were set by eye on a 4K screen running PeaversScaler's 1440p
-- mode, so they describe a canvas 1440 units tall. On a machine left at 1.0 the
-- same numbers put the unit frames at y = -395 on a screen whose bottom edge is
-- at -384, which is how the pack came out "all out of place" on a second PC.
--
-- So the canvas is part of the layout. Each one asks PeaversScaler for the same
-- 1440p mode, which is a fixed scale rather than a resolution-dependent one, and
-- then every position is the same fraction of the screen on any monitor: 1080p,
-- 1440p, 4K or an ultrawide. The trade is honest and worth stating - on a 1080p
-- screen the whole interface is drawn at three quarters of its native size - but
-- a layout that is the right size in the wrong place is not a layout at all.
--
-- A layout may name its own scaler block to use a different canvas; one that
-- does has to be positioned for it.
--
-- And the canvas is a *choice*, not a constant - see "Interface size" below.
-- 1440 units is where the layouts were drawn and what every screenshot of the
-- pack shows, but it is also the reason the pack reads small on a laptop: a
-- 1440-unit canvas on a 15-inch screen is the same interface as on a 27-inch
-- monitor, at half the physical size. Asking for a shorter canvas is how you
-- get a bigger interface, and the positions are re-derived for it rather than
-- left where a 1440-unit screen put them.
--------------------------------------------------------------------------------

Layouts.CANVAS = "1440p"

-- How many UI units tall the screen is when a layout is drawn as designed.
-- Every coordinate above is in units of this canvas; see Layouts:OverridesFor.
Layouts.CANVAS_HEIGHT = 1440

for _, layout in pairs(Layouts.list) do
    local overrides = layout.overrides
    if overrides and overrides.minimap and overrides.systembars then
        Layouts.DockSystemBars(overrides.minimap, overrides.systembars)
    end
    if overrides then
        overrides.scaler = overrides.scaler or {}
        if overrides.scaler.scaleMode == nil then
            overrides.scaler.scaleMode = Layouts.CANVAS
        end
    end
end

--------------------------------------------------------------------------------
-- Interface size
--
-- One number - the canvas height in UI units - put to the player as a percentage
-- of the size the pack was drawn at. A shorter canvas spreads fewer UI units
-- across the same screen, so every unit is more pixels and the interface comes
-- out physically larger: 1080 units is this pack at 133%.
--
-- A canvas needs a UI scale of 768 / height, which is what PeaversScaler is
-- asked for. 200% needs 1.067 and 70% needs 0.373, both inside PeaversScaler's
-- own [0.25, 1.25] - which is where SIZE_MIN and SIZE_MAX come from rather than
-- being picked.
--
-- Always a frozen number, never PeaversScaler's pixelPerfect mode: the positions
-- above are written for one canvas height at install time, and a mode that
-- recomputed later would move the canvas out from under them. The recommendation
-- below is the pixel-perfect scale for the screen it is asked on; it is just
-- frozen rather than followed.
--------------------------------------------------------------------------------

local UI_HEIGHT = 768          -- WoW's virtual screen height, at a scale of 1.0

Layouts.SIZE_MIN = 0.70
Layouts.SIZE_MAX = 2.00
-- One percent, not five. The Laptop canvas is 1440/1080 = 133.3%, and a slider
-- that could only stop on multiples of five would read "135%" the moment you
-- clicked a row labelled 133%.
Layouts.SIZE_STEP = 0.01

--- The canvas height that draws the pack at `size` (1 = as drawn).
function Layouts:CanvasFor(size)
    size = tonumber(size) or 1
    if size < self.SIZE_MIN then size = self.SIZE_MIN end
    if size > self.SIZE_MAX then size = self.SIZE_MAX end
    return self.CANVAS_HEIGHT / size
end

--- The size a canvas height draws the pack at, as a multiplier of "as drawn".
function Layouts:SizeOf(canvas)
    canvas = tonumber(canvas)
    if not canvas or canvas <= 0 then return 1 end
    return self.CANVAS_HEIGHT / canvas
end

--- The UI scale PeaversScaler has to hold for a canvas to be that many units.
function Layouts:ScaleFor(canvas)
    return UI_HEIGHT / (tonumber(canvas) or self.CANVAS_HEIGHT)
end

-- The named sizes, in the order the installer lists them. Canvas heights are
-- round screen numbers rather than the arithmetic result of a percentage,
-- because the canvas is the thing actually being chosen: 1080 is a 1080p screen
-- drawn one UI unit to one pixel, and reads as that rather than as 133.333%.
Layouts.sizes = {
    {
        key = "roomy", canvas = 1800,
        label = "Smaller",
        blurb = "More screen and smaller furniture, for a large monitor you sit close to.",
    },
    {
        key = "drawn", canvas = 1440,
        label = "As drawn",
        blurb = "The size the layouts were positioned at, and what the screenshots show.",
    },
    {
        key = "laptop", canvas = 1080,
        label = "Laptop",
        blurb = "A third larger, for a laptop or a 1080p monitor where the pack reads small.",
    },
    {
        key = "large", canvas = 960,
        label = "Large",
        blurb = "Half again, for a small laptop screen or a television across the room.",
    },
}

Layouts.sizeByKey = {}
for _, size in ipairs(Layouts.sizes) do
    Layouts.sizeByKey[size.key] = size
end

--- The named size matching a canvas exactly, or nil for one set by hand.
function Layouts:SizeKeyFor(canvas)
    for _, size in ipairs(self.sizes) do
        if size.canvas == canvas then return size.key end
    end
    return nil
end

--- "133%", for every readout in the installer.
function Layouts:SizeLabel(canvas)
    return math.floor(self:SizeOf(canvas) * 100 + 0.5) .. "%"
end

--------------------------------------------------------------------------------
-- What to suggest on this screen
--
-- A screen 1440 pixels tall or more keeps the canvas as drawn: the layouts were
-- set by eye at that canvas on a 4K monitor, so a 1440p or better screen is the
-- one they were set for, and suggesting anything else would mean a fresh install
-- no longer matched the pack's own screenshots.
--
-- Below that, the pack is drawn at less than one UI unit per pixel, which is
-- where "everything is way too small on my laptop" comes from. The suggestion is
-- the canvas that matches the screen exactly - 1080 units on a 1080p panel, one
-- unit to one pixel. That is the largest the pack can be drawn without landing
-- hairlines on half pixels, and on those screens it is the Laptop size.
--
-- Outside the game there is nothing to measure, and the canvas as drawn is the
-- only honest answer.
--------------------------------------------------------------------------------
function Layouts:RecommendedCanvas()
    if type(_G.GetPhysicalScreenSize) ~= "function" then
        return self.CANVAS_HEIGHT
    end

    local ok, _, height = pcall(_G.GetPhysicalScreenSize)
    if not ok or type(height) ~= "number" or height <= 0 then
        return self.CANVAS_HEIGHT
    end

    if height >= self.CANVAS_HEIGHT then
        return self.CANVAS_HEIGHT
    end

    -- Clamped through CanvasFor so a very short screen - a windowed client, an
    -- old 1366x768 laptop - cannot ask for a size the slider has no room for.
    local canvas = self:CanvasFor(self:SizeOf(height))

    -- Snap to a named size when it is within a step, so the suggestion lands on
    -- a row somebody can recognise rather than on a custom number a percent away
    -- from one.
    local tolerance = self.SIZE_STEP
    for _, named in ipairs(self.sizes) do
        if math.abs(self:SizeOf(named.canvas) - self:SizeOf(canvas)) < tolerance then
            return named.canvas
        end
    end

    return canvas
end

--------------------------------------------------------------------------------
-- Drawing a layout on a different canvas
--
-- Positions scale with the canvas. Sizes do not. Both halves of that rule are
-- what make a size choice mean "bigger" rather than "the same thing again".
--
-- A coordinate is a fraction of the screen written in UI units: y = -395 on a
-- 1440-unit canvas is 55% of the way down from the middle, and it has to stay
-- there on any other canvas or the row of unit frames slides off the bottom
-- edge. So every position is multiplied by canvas / 1440.
--
-- A width, a font size or an aura size is not a fraction of anything. It is a
-- count of UI units, and a UI unit on a shorter canvas is physically larger -
-- which is the entire change being asked for. Scaling those too would reproduce
-- the layout at exactly the same physical size and achieve nothing.
--
-- The positional keys are named rather than recognised by spelling: a rule like
-- "anything called x or y" would also catch minimap.widgetLayout, whose entries
-- are offsets inside the minimap frame, and drag the difficulty flag off the
-- corner it is pinned to.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Frames placed from a screen edge
--
-- PeaversUnitFrames stores a frame's position as an offset from the centre of
-- UIParent and nothing else, which is the right call for a layout whose frames
-- are meant to sit either side of the middle - Modern and Peavers UI both are,
-- and both land identically on a 4:3 monitor and a 21:9 one.
--
-- It is the wrong call for a corner. The canvas is a fixed number of units tall
-- but its *width* is the aspect ratio times that, so half a screen is 960 units
-- on 4:3 and 1680 on 21:9. A top-left frame written as a centre offset is in the
-- corner on the monitor it was authored on and floating near the middle of the
-- screen on a wider one - which is the whole layout, wrong.
--
-- So a unit may say where it sits relative to a screen edge instead, and the
-- centre offset the module wants is worked out here against the screen the
-- installer is actually running on. edgeX and edgeY are the frame's centre
-- measured inward from that corner.
--
-- Baked at install time, like the canvas, and for the same reason: these become
-- ordinary x and y in another addon's saved variables, which Edit Mode can then
-- move. Someone who changes to a monitor of a different shape re-runs /pui, the
-- same as they would for a change of resolution.
--------------------------------------------------------------------------------

local DEFAULT_ASPECT = 16 / 9

-- Whole units, mirrored around zero. Almost every coordinate in this file is
-- negative, and math.floor(x + 0.5) on a negative is not rounding but rounding
-- down: -296.25 would become -297 while its positive twin became 296. Half a UI
-- unit is the difference between a hairline drawn once and drawn twice.
local function Round(value)
    if value >= 0 then return math.floor(value + 0.5) end
    return -math.floor(-value + 0.5)
end

-- Which way is inward from each corner, and which edge each sign belongs to.
local EDGES = {
    TOPLEFT     = { x = -1, y =  1 },
    TOPRIGHT    = { x =  1, y =  1 },
    BOTTOMLEFT  = { x = -1, y = -1 },
    BOTTOMRIGHT = { x =  1, y = -1 },
}

--- The shape of this screen, as width over height. 16:9 when there is nothing to
--- ask - outside the game, or on a client without the API - because a guess that
--- is right for most monitors beats refusing to place the frame at all.
function Layouts:ScreenAspect()
    if type(_G.GetPhysicalScreenSize) ~= "function" then return DEFAULT_ASPECT end

    local ok, width, height = pcall(_G.GetPhysicalScreenSize)
    if not ok or type(width) ~= "number" or type(height) ~= "number" or height <= 0 then
        return DEFAULT_ASPECT
    end
    return width / height
end

-- Turn every `edge` unit in a block into the x and y the module understands, and
-- take the edge keys back out. They have to go: the installer deep-merges this
-- into a live config, and three keys PeaversUnitFrames has never heard of would
-- sit in somebody's saved variables forever doing nothing.
local function ResolveEdges(units, canvas, aspect)
    if type(units) ~= "table" then return end

    local halfWidth = (canvas * aspect) / 2
    local halfHeight = canvas / 2

    -- The inset is NOT scaled by the canvas, unlike a centre offset, and the
    -- difference is the whole reason this is a separate idea.
    --
    -- A centre offset is a fraction of the screen and scales so the frame stays
    -- the same fraction along it. An inset is the margin around a frame, and the
    -- frame's own width and height are deliberately left in fixed UI units so a
    -- shorter canvas draws them larger. Scaling the margin while not scaling the
    -- thing it surrounds pulls a growing frame towards a shrinking gap: at 200%
    -- the top-left frame ends up six units off the edge of the screen.
    --
    -- Fixed, the corner cluster keeps exactly the same relationship to the
    -- corner at every interface size, which is what a corner is for.
    for _, unit in pairs(units) do
        local edge = type(unit) == "table" and EDGES[unit.edge or ""]
        if edge then
            local insetX = tonumber(unit.edgeX) or 0
            local insetY = tonumber(unit.edgeY) or 0

            unit.x = Round(edge.x * (halfWidth - insetX))
            unit.y = Round(edge.y * (halfHeight - insetY))

            unit.edge, unit.edgeX, unit.edgeY = nil, nil, nil
        end
    end
end

-- "*" stands for every child table: each unit under `units`, whatever it is
-- called, without this file holding another addon's roster.
local POSITIONAL = {
    unitframes = { units = { ["*"] = { "x", "y" } } },
    castbar    = { units = { ["*"] = { "frameX", "frameY" } } },
    minimap    = { "offsetX", "offsetY" },
    chat       = { "chatX", "chatY" },
    tooltip    = { "anchorX", "anchorY" },
    -- systembars is deliberately absent. Its position is derived from the
    -- minimap's by DockSystemBars, re-run below once the minimap block has been
    -- scaled; scaling it here too would apply the factor twice and undock the
    -- bars at every size but the one they were docked at.
}

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do out[key] = DeepCopy(inner) end
    return out
end

Layouts.DeepCopy = DeepCopy

-- Walk `block` against a spec from POSITIONAL, multiplying what the spec names.
local function ScalePositions(block, spec, factor)
    if type(block) ~= "table" or type(spec) ~= "table" then return end

    for _, key in ipairs(spec) do
        local value = tonumber(block[key])
        if value then
            block[key] = Round(value * factor)
        end
    end

    for key, inner in pairs(spec) do
        if type(key) == "string" and type(inner) == "table" then
            if key == "*" then
                for _, child in pairs(block) do
                    ScalePositions(child, inner, factor)
                end
            else
                ScalePositions(block[key], inner, factor)
            end
        end
    end
end

--- A layout's overrides, drawn for a canvas of `canvas` UI units.
---
--- Always a copy, never the shipped table: the installer deep-merges what it is
--- handed into another addon's live config, and handing over the layout itself
--- would let one install's arithmetic leak into the next.
---
--- @param layoutKey string
--- @param canvas number|nil  canvas height in UI units; nil means as drawn
--- @return table overrides
function Layouts:OverridesFor(layoutKey, canvas)
    local layout = self:Get(layoutKey)
    if not layout or not layout.overrides then return {} end

    canvas = tonumber(canvas) or self.CANVAS_HEIGHT
    local overrides = DeepCopy(layout.overrides)

    if canvas ~= self.CANVAS_HEIGHT then
        local factor = canvas / self.CANVAS_HEIGHT
        for key, spec in pairs(POSITIONAL) do
            ScalePositions(overrides[key], spec, factor)
        end
        if overrides.minimap and overrides.systembars then
            self.DockSystemBars(overrides.minimap, overrides.systembars)
        end
    end

    -- After the scaling, not before, and unconditionally. An edge-placed unit
    -- has no x or y for ScalePositions to find, and the offsets this writes are
    -- final - running it first would hand the factor to numbers that already
    -- account for it. Unconditional because a corner is a corner at every size,
    -- including the one the layouts were drawn at.
    if overrides.unitframes then
        ResolveEdges(overrides.unitframes.units, canvas, self:ScreenAspect())
    end

    overrides.scaler = overrides.scaler or {}
    if canvas == self.CANVAS_HEIGHT then
        -- The one canvas PeaversScaler has a preset for. Naming it keeps that
        -- addon's settings page reading "1440p" rather than a bare number, and
        -- it is what every install from before sizes existed already holds.
        overrides.scaler.scaleMode = self.CANVAS
    else
        overrides.scaler.scaleMode = "custom"
        overrides.scaler.scale = self:ScaleFor(canvas)
    end

    return overrides
end

--------------------------------------------------------------------------------
-- Revisions
--
-- A layout's revision goes up whenever a change to it would look different on
-- somebody's screen. An install records the revision it applied, and nothing
-- newer is ever written unless the player chose to follow the latest layout -
-- see Core/Versioning.lua.
--
-- Bump a layout by adding the next number here, in the same commit as the
-- change, with one sentence a player would understand: it is printed in chat
-- when the update is applied. Revision 1 is everything installed before
-- revisions existed.
--------------------------------------------------------------------------------

local BLACK_CHAT = "Chat window painted the same flat black as the unit frames."
local CAST_BARS = "Cast bars are part of the pack now: PeaversCastBar is installed and arranged with everything else."

-- Peavers UI keeps Standard's history unbroken, and gains no revision for the
-- rename. The rule above is that a revision means somebody's screen looks
-- different, and a card with a new name on it does not.
Layouts.changelog = {
    peavers = {
        [1] = "First release.",
        [2] = "Plain chat tabs with full channel names, and the UI scale pinned to " ..
              "1440p so positions match on any screen.",
        [3] = BLACK_CHAT,
        [4] = CAST_BARS .. " The chat window sits a little higher.",
    },
    traditional = { [1] = "First release." },
    modern      = { [1] = "First release." },
}

for key, layout in pairs(Layouts.list) do
    local revision = 0
    for number in pairs(Layouts.changelog[key] or {}) do
        if number > revision then revision = number end
    end
    layout.revision = revision
end

function Layouts:ChangesFor(key, revision)
    local log = self.changelog[key]
    return log and log[revision] or nil
end

-- Not a layout. The wizard's "keep my current setup" choice, stored where a layout
-- key would be: no overrides, no revision, nothing to update.
Layouts.CURRENT = "current"

-- Resolving retired keys here rather than at each call site is what keeps an
-- account installed on a layout that no longer exists from reading as an account
-- installed on nothing: the settings page can still name it, the wizard can
-- still preselect its replacement, and /pui apply raid still does something
-- sensible instead of printing usage.
function Layouts:Get(key)
    return self.list[key] or self.list[self.retired[key or ""] or ""]
end

-- Manifest order, as a list. Used by the wizard so the cards always appear in
-- the same order rather than in whatever order pairs() felt like.
function Layouts:Sorted()
    local out = {}
    for _, key in ipairs(self.order) do
        local layout = self.list[key]
        if layout then
            out[#out + 1] = { key = key, layout = layout }
        end
    end
    return out
end

-- The auto-switch plan a layout suggests, as a fresh table the caller may edit.
-- Copied rather than handed over: the wizard lets people change a context on the
-- graphics screen, and doing that to the layout table itself would quietly
-- rewrite the shipped layout for the rest of the session.
--
-- Only the contexts this client has. The layouts above name all four, but a
-- plan carrying "mythicplus" on a client with no timed dungeons would be a
-- setting nobody can see, change or use.
function Layouts:AutoSwitchFor(key)
    local layout = self:Get(key)
    local plan = layout and layout.autoSwitch

    local keys = { "raid", "mythicplus", "dungeon", "world" }
    if PUI.Installer and PUI.Installer.AutoSwitchContexts then
        keys = {}
        for _, ctx in ipairs(PUI.Installer:AutoSwitchContexts()) do
            keys[#keys + 1] = ctx.key
        end
    end

    local out = { enabled = plan and plan.enabled and true or false }
    for _, ctxKey in ipairs(keys) do
        out[ctxKey] = plan and plan[ctxKey] or "none"
    end
    return out
end

return Layouts
