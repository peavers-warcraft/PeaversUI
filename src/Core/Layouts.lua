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
-- quiet about keeps the value the module shipped with, which is what makes
-- "Standard" a short table rather than a copy of six defaults files.
--
-- Coordinates: PeaversUnitFrames positions every frame as an offset from the
-- centre of UIParent, so the numbers below are resolution independent and mean
-- the same thing on 1080p and on an ultrawide. PeaversMiniMap and
-- PeaversSystemBars anchor to a screen corner or edge instead, because a
-- minimap belongs in a corner at every resolution rather than at a fixed
-- distance from the middle.
--
-- Each layout also names a graphics preset. That is a *suggestion* the wizard
-- pre-selects on the next step, never something applied behind the player's
-- back: changing CVars is the one thing in here that touches the game rather
-- than the interface, so it always gets its own explicit yes.
--------------------------------------------------------------------------------

local _, PUI = ...

local Layouts = {}
PUI.Layouts = Layouts

Layouts.order = { "standard", "compact", "cinematic", "raid" }

Layouts.list = {

    ----------------------------------------------------------------------------
    -- Standard
    --
    -- The suite as its authors run it. Deliberately close to each module's own
    -- defaults: this is the layout that should look like nothing happened to
    -- somebody who already liked the individual addons, and it is the one a
    -- reset goes back to.
    ----------------------------------------------------------------------------
    standard = {
        name = "Standard",
        tagline = "The suite as it ships",
        blurb = "Frames flanking the centre, minimap squared into the top-right, " ..
                "tooltips on the cursor. If you are not sure, this is the one.",
        graphics = "balanced",

        overrides = {
            unitframes = {
                hideBlizzardFrames = true,
                units = {
                    player       = { x = -270, y = -200, width = 240, height = 46, healthText = "percent" },
                    target       = { x =  270, y = -200, width = 240, height = 46, healthText = "percent" },
                    targettarget = { x =  470, y = -200, width = 120, height = 28 },
                    focus        = { x = -470, y = -200, width = 180, height = 36 },
                },
            },
            minimap = {
                enabled = true,
                squareShape = true,
                size = 155,
                anchorEnabled = true,
                anchor = "TOPRIGHT",
                offsetX = 0,
                offsetY = 0,
                zoneTextMode = "hidden",
                collectButtons = true,
                visibility = "toggle",
                growDirection = "LEFT",
                buttonsPerRow = 2,
            },
            chat = {
                enabled = true,
                bgAlpha = 0.60,
                fontSize = 13,
                maxLines = 1000,
                fading = false,
            },
            tooltip = {
                enabled = true,
                scale = 1.0,
                anchorMode = "cursor",
                healthBar = true,
                healthBarPosition = "bottom",
                hideInCombat = "never",
            },
            systembars = {
                framePoint = "RIGHT",
                frameX = -20,
                frameY = 0,
                frameWidth = 200,
                barHeight = 20,
                showTitleBar = true,
                showFrameBackground = true,
                showStatNames = true,
                showStatValues = true,
            },
        },
    },

    ----------------------------------------------------------------------------
    -- Compact
    --
    -- The same layout drawn smaller and pulled inwards. This is what a 1440p or
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

        overrides = {
            unitframes = {
                hideBlizzardFrames = true,
                units = {
                    player = {
                        x = -210, y = -160, width = 200, height = 38,
                        fontSize = 10, castBarHeight = 16, auraSize = 18,
                        maxBuffs = 6, maxDebuffs = 6, powerHeight = 4,
                    },
                    target = {
                        x = 210, y = -160, width = 200, height = 38,
                        fontSize = 10, castBarHeight = 16, auraSize = 18,
                        maxBuffs = 6, maxDebuffs = 6, powerHeight = 4,
                    },
                    targettarget = {
                        x = 390, y = -160, width = 110, height = 24,
                        fontSize = 9, auraSize = 14,
                    },
                    focus = {
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
    -- corner rather than switching off - a tooltip that follows the cursor is
    -- the single biggest thing covering the middle of the screen.
    ----------------------------------------------------------------------------
    cinematic = {
        name = "Cinematic",
        tagline = "Chrome out of the way, world in view",
        blurb = "The quiet one. Frames low and close, chat faded back, addon " ..
                "buttons hidden until you point at them, tooltips parked in the " ..
                "bottom-right instead of following the mouse. Target-of-target " ..
                "is switched off.",
        graphics = "quality",

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

return Layouts
