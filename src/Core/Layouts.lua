--------------------------------------------------------------------------------
-- PeaversUI layouts
--
-- Pure data: four complete looks, each one a set of overrides written into the
-- module addons' own configs. There is no code here on purpose. A layout is
-- something a person should be able to read, disagree with, and change by
-- editing a number - not a function that has to be traced through.
--
-- The overrides are applied as a deep merge over whatever the module already
-- has, so a layout only has to name what it actually changes. Anything it stays
-- quiet about keeps the value the module shipped with.
--
-- Coordinates: PeaversUnitFrames positions every frame as an offset from the
-- centre of UIParent, so the numbers below are resolution independent and mean
-- the same thing on 1080p and on an ultrawide. PeaversMiniMap and
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
-- unset, so the right media arrives by default rather than by four layouts each
-- naming a path. That keeps the house style a one-line change over there rather
-- than a search across this file - and it is why a layout can be a transcription
-- of a screen that used a font and a texture from two other addons without
-- carrying either dependency with it.
--------------------------------------------------------------------------------

local _, PUI = ...

local Layouts = {}
PUI.Layouts = Layouts

Layouts.order = { "standard", "compact", "cinematic", "raid" }

Layouts.list = {

    ----------------------------------------------------------------------------
    -- Standard
    --
    -- Not a set of defaults: this is the author's own interface, transcribed from
    -- a live install. That is the point of it. Anyone can invent four plausible
    -- arrangements of frames; the one worth shipping is the one somebody
    -- actually plays with, because every value in it has already survived
    -- contact with a raid night.
    --
    -- The shape of it, in case a number below looks arbitrary: four frames on
    -- one line low on the screen, health bars painted flat black with the class
    -- colour thrown away, no power bars, and almost no auras on the player. It
    -- is a layout for somebody who reads their buffs somewhere else and wants
    -- the unit frames to answer exactly one question quickly.
    ----------------------------------------------------------------------------
    standard = {
        name = "Standard",
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
            chat = {
                enabled = true,
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
                tabUppercase = true,
                tabUnderline = true,
                tabFontSize = 10,
                -- Arial Narrow ships with the game. Small uppercase tabs need a
                -- condensed face or they run into each other.
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
                shortChannelNames = true,
                timestamps = "default",
                -- Flush into the bottom-left corner. edgeToEdge above is what
                -- makes x = 0 reachable; this is what actually puts it there.
                positionEnabled = true,
                chatPoint = "BOTTOMLEFT",
                chatX = 0,
                chatY = 22,
                chatWidth = 430,
                chatHeight = 180,
            },
            tooltip = {
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
            },
            systembars = {
                -- Tucked under the minimap in the top-right corner rather than
                -- floating at the right edge, so the whole corner reads as one
                -- block of instrumentation.
                framePoint = "TOPRIGHT",
                frameX = 0,
                frameY = -155,
                frameWidth = 157,
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
    -- Compact
    --
    -- The same idea drawn smaller and pulled inwards. This is what a 1440p or
    -- 4K screen usually wants: at those resolutions the default sizes are not
    -- too big in pixels, they are too far apart in degrees, and the fix is to
    -- move things towards the middle rather than to scale everything up.
    ----------------------------------------------------------------------------
    compact = {
        name = "Compact",
        tagline = "Smaller, closer, less to look away for",
        blurb = "Everything drawn tighter and pulled in towards the middle of the " ..
                "screen. Suits high resolutions, where the default spread means " ..
                "taking your eyes off your character to read your own health.",
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
                    player = {
                        enabled = true,
                        x = -210, y = -160, width = 200, height = 38,
                        fontSize = 10, castBarHeight = 16, auraSize = 18,
                        maxBuffs = 6, maxDebuffs = 6, powerHeight = 4,
                    },
                    target = {
                        enabled = true,
                        x = 210, y = -160, width = 200, height = 38,
                        fontSize = 10, castBarHeight = 16, auraSize = 18,
                        maxBuffs = 6, maxDebuffs = 6, powerHeight = 4,
                    },
                    targettarget = {
                        enabled = true,
                        x = 390, y = -160, width = 110, height = 24,
                        fontSize = 9, auraSize = 14,
                    },
                    focus = {
                        enabled = true,
                        x = -390, y = -160, width = 150, height = 30,
                        fontSize = 10, castBarHeight = 14, auraSize = 16,
                        maxBuffs = 5, maxDebuffs = 5,
                    },
                },
            },
            minimap = {
                enabled = true,
                squareShape = true,
                size = 130,
                anchor = "TOPRIGHT",
                zoneTextMode = "hidden",
                hideZoomButtons = true,
                collectButtons = true,
                visibility = "toggle",
                growDirection = "LEFT",
                buttonSize = 22,
                buttonsPerRow = 3,
            },
            chat = {
                enabled = true,
                bgAlpha = 0.55,
                fontSize = 11,
                tabFontSize = 11,
                paddingLeft = 6,
                paddingRight = 4,
                paddingTop = 4,
                paddingBottom = 4,
                maxLines = 1000,
                positionEnabled = true,
                chatPoint = "BOTTOMLEFT",
                chatX = 0,
                chatY = 20,
                chatWidth = 360,
                chatHeight = 150,
            },
            tooltip = {
                enabled = true,
                scale = 0.9,
                fontSize = 11,
                anchorMode = "cursor",
                healthBar = true,
                healthBarHeight = 5,
            },
            systembars = {
                framePoint = "RIGHT",
                frameX = -14,
                frameY = 0,
                frameWidth = 150,
                barHeight = 14,
                showTitleBar = false,
                showFrameBackground = true,
                showStatNames = true,
            },
        },
    },

    ----------------------------------------------------------------------------
    -- Cinematic
    --
    -- Chrome out of the way, world in view. The trade is real and worth stating:
    -- target-of-target goes off, the chat window fades, and the addon buttons
    -- hide until you point at them. That is less information on screen, not the
    -- same information arranged more prettily.
    --
    -- The one thing it does *not* do is hide anything you need in a fight. Cast
    -- bars stay, debuffs on your target stay, and tooltips move to a fixed
    -- corner rather than switching off.
    ----------------------------------------------------------------------------
    cinematic = {
        name = "Cinematic",
        tagline = "Chrome out of the way, world in view",
        blurb = "The quiet one. Frames low and close, chat faded back, addon " ..
                "buttons hidden until you point at them, tooltips parked in the " ..
                "bottom-right instead of following the mouse. Target-of-target " ..
                "is switched off.",
        graphics = "quality",
        -- The one layout that leaves the open world alone rather than restoring
        -- it: somebody who picked Cinematic is there to look at the game, and
        -- Quality is already the setting they would have chosen standing still.
        autoSwitch = {
            enabled = true,
            raid = "balanced",
            mythicplus = "performance",
            dungeon = "none",
            world = "none",
        },

        overrides = {
            unitframes = {
                hideBlizzardFrames = true,
                units = {
                    player = {
                        enabled = true,
                        x = -260, y = -240, width = 220, height = 40,
                        healthText = "percent", showBuffs = false,
                        showDebuffs = true, maxDebuffs = 6, auraSize = 20,
                        tooltip = "ooc",
                    },
                    target = {
                        enabled = true,
                        x = 260, y = -240, width = 220, height = 40,
                        healthText = "percent", showBuffs = true, maxBuffs = 6,
                        showDebuffs = true, maxDebuffs = 6, auraSize = 20,
                        tooltip = "ooc",
                    },
                    -- Off, not resized. Target-of-target is the frame most
                    -- people never read, and the one taking up the most room
                    -- for the least information.
                    targettarget = { enabled = false },
                    focus = {
                        enabled = true,
                        x = -460, y = -240, width = 150, height = 30,
                        healthText = "none", showBuffs = false, maxDebuffs = 4,
                        auraSize = 16, tooltip = "ooc",
                    },
                },
            },
            minimap = {
                enabled = true,
                squareShape = true,
                size = 140,
                anchor = "TOPRIGHT",
                zoneTextMode = "hidden",
                hideZoomButtons = true,
                collectButtons = true,
                visibility = "hover",
                growDirection = "LEFT",
                buttonsPerRow = 2,
            },
            chat = {
                enabled = true,
                background = true,
                bgAlpha = 0.35,
                border = false,
                fontSize = 12,
                fading = true,
                timeVisible = 60,
                showBottomButton = false,
                tabUnderline = true,
                positionEnabled = true,
                chatPoint = "BOTTOMLEFT",
                chatX = 0,
                chatY = 20,
                chatWidth = 380,
                chatHeight = 150,
            },
            tooltip = {
                enabled = true,
                scale = 0.95,
                anchorMode = "anchor",
                anchorPoint = "BOTTOMRIGHT",
                anchorX = -230,
                anchorY = 230,
                healthBar = true,
                healthBarPosition = "bottom",
            },
            systembars = {
                framePoint = "BOTTOMRIGHT",
                frameX = -12,
                frameY = 12,
                frameWidth = 120,
                barHeight = 8,
                showTitleBar = false,
                showFrameBackground = false,
                showStatNames = false,
                showStatValues = true,
            },
        },
    },

    ----------------------------------------------------------------------------
    -- Raid
    --
    -- Built for a night where the answer to "what happened" has to be on screen
    -- already. Bigger frames, longer aura rows, readouts in numbers as well as
    -- percentages, a chat buffer you can actually scroll back through, and unit
    -- tooltips suppressed in combat so nothing sits over the boss.
    ----------------------------------------------------------------------------
    raid = {
        name = "Raid",
        tagline = "Everything on screen, nothing in the way",
        blurb = "Information dense. Larger frames, longer aura rows, health in " ..
                "numbers and percent, a 2,000 line chat buffer - and unit " ..
                "tooltips suppressed in combat so nothing sits over the boss.",
        graphics = "performance",
        -- The only layout that drops the dungeon too. Somebody who picked Raid
        -- is optimising for frames in group content generally, not just on the
        -- two nights a week that are actually a raid.
        autoSwitch = {
            enabled = true,
            raid = "performance",
            mythicplus = "performance",
            dungeon = "performance",
            world = "restore",
        },

        overrides = {
            unitframes = {
                hideBlizzardFrames = true,
                units = {
                    player = {
                        enabled = true,
                        x = -300, y = -180, width = 260, height = 52,
                        healthText = "both", fontSize = 12,
                        showPower = true, powerHeight = 6,
                        castBarHeight = 20,
                        showBuffs = true, maxBuffs = 10,
                        showDebuffs = true, maxDebuffs = 10,
                        auraSize = 22, tooltip = "ooc",
                    },
                    target = {
                        enabled = true,
                        x = 300, y = -180, width = 260, height = 52,
                        healthText = "both", fontSize = 12,
                        showPower = true, powerHeight = 6,
                        castBarHeight = 20,
                        showBuffs = true, maxBuffs = 10,
                        showDebuffs = true, maxDebuffs = 10,
                        auraSize = 22, tooltip = "ooc",
                    },
                    targettarget = {
                        enabled = true,
                        x = 520, y = -180, width = 130, height = 30,
                        healthText = "percent", fontSize = 10,
                        tooltip = "ooc",
                    },
                    focus = {
                        enabled = true,
                        x = -520, y = -180, width = 200, height = 42,
                        healthText = "percent", fontSize = 11,
                        showCastBar = true, castBarHeight = 16,
                        showDebuffs = true, maxDebuffs = 8,
                        -- The focus frame is where a dispel gets noticed, so
                        -- its debuff row is narrowed to what you can act on.
                        debuffCategory = "dispellable",
                        auraSize = 20, tooltip = "ooc",
                    },
                },
            },
            minimap = {
                enabled = true,
                squareShape = true,
                size = 150,
                anchor = "TOPRIGHT",
                zoneTextMode = "hidden",
                collectButtons = true,
                -- Always visible: on a progression night the boss mod and the
                -- log uploader are buttons you actually click mid-pull.
                visibility = "always",
                growDirection = "LEFT",
                buttonsPerRow = 2,
            },
            chat = {
                enabled = true,
                bgAlpha = 0.65,
                fontSize = 12,
                maxLines = 2000,
                fading = false,
                shortChannelNames = true,
                positionEnabled = true,
                chatPoint = "BOTTOMLEFT",
                chatX = 0,
                chatY = 22,
                chatWidth = 460,
                chatHeight = 240,
            },
            tooltip = {
                enabled = true,
                scale = 1.0,
                anchorMode = "anchor",
                anchorPoint = "BOTTOMRIGHT",
                anchorX = -230,
                anchorY = 230,
                healthBar = true,
                healthBarText = "percent",
                -- Units only. Item tooltips still work mid-fight, which is what
                -- you want when loot drops; unit tooltips are the ones that end
                -- up parked over the encounter.
                hideInCombat = "units",
            },
            systembars = {
                framePoint = "RIGHT",
                frameX = -20,
                frameY = 0,
                frameWidth = 180,
                barHeight = 16,
                showTitleBar = false,
                showFrameBackground = true,
                showStatNames = true,
                showStatValues = true,
            },
        },
    },
}

function Layouts:Get(key)
    return self.list[key]
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
function Layouts:AutoSwitchFor(key)
    local layout = self:Get(key)
    local plan = layout and layout.autoSwitch

    if not plan then
        return { enabled = false, raid = "none", mythicplus = "none",
                 dungeon = "none", world = "none" }
    end

    return {
        enabled = plan.enabled and true or false,
        raid = plan.raid or "none",
        mythicplus = plan.mythicplus or "none",
        dungeon = plan.dungeon or "none",
        world = plan.world or "none",
    }
end

return Layouts
