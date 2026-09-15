--------------------------------------------------------------------------------
-- PeaversUI layout versioning
--
-- The rule this file exists to enforce: a pack update never changes somebody's
-- interface unless they asked it to. Addons have lost their whole user base by
-- rearranging screens behind people's backs, and a UI pack is the addon most
-- able to do that.
--
-- Every layout has a revision (Layouts.changelog). An install records the one it
-- applied, and the account is on one of two tracks:
--
--   pinned  The default, always. Updating the pack changes nothing on screen. A
--           newer revision is mentioned, never applied.
--   latest  Chosen by ticking a box or typing /pui follow. When the pack ships a
--           newer revision of the installed layout, it is re-applied at login -
--           the whole layout, over every setting it names - and announced, with
--           /pui undo to reverse it.
--
-- "Keep my current setup" is not a layout, so it has no revision and nothing to
-- follow.
--------------------------------------------------------------------------------

local _, PUI = ...

local Versioning = {}
PUI.Versioning = Versioning

Versioning.PINNED = "pinned"
Versioning.LATEST = "latest"

local function Say(message)
    local commons = _G.PeaversCommons
    if commons and commons.Utils and commons.Utils.Print then
        commons.Utils.Print(PUI, message)
    end
end

--- What this account is on, and whether the pack has anything newer.
function Versioning:Status()
    local config = PUI.Config
    local key = config.layout
    local layout = PUI.Layouts:Get(key)
    local installed = config.installedVersion ~= nil
    local revision = installed and config.layoutRevision or nil
    local latest = layout and layout.revision or nil

    return {
        installed = installed,
        layout = key,
        name = layout and layout.name or nil,
        keepsCurrent = key == PUI.Layouts.CURRENT,
        revision = revision,
        latest = latest,
        track = config.track == self.LATEST and self.LATEST or self.PINNED,
        behind = revision ~= nil and latest ~= nil and revision < latest,
    }
end

--------------------------------------------------------------------------------
-- Installs from before revisions existed
--
-- They were made with revision 1 of whatever layout they chose, and they are
-- pinned: nobody who installed the pack agreed to follow changes that did not
-- exist yet. The notice flag makes the next login say so, once.
--------------------------------------------------------------------------------
function Versioning:Migrate()
    local config = PUI.Config
    if not config.installedVersion or config.layoutRevision ~= nil then return false end
    if config.layout == PUI.Layouts.CURRENT then return false end

    config.layoutRevision = 1
    config.track = self.PINNED
    config.versioningNoticeShown = false
    config:Save()
    return true
end

function Versioning:NoticeDue()
    return PUI.Config.installedVersion ~= nil and PUI.Config.versioningNoticeShown == false
end

function Versioning:ShowNotice()
    local status = self:Status()
    PUI.Config.versioningNoticeShown = true
    PUI.Config:Save()

    local text = "layouts now have versions. Your interface is pinned to what you " ..
                 "installed, and pack updates will never change it on their own."
    if status.behind then
        text = text .. (" A newer %s layout exists (revision %d, you have %d): " ..
            "/pui update applies it once, /pui follow applies it and keeps it up to " ..
            "date, /pui settings shows what changed."):format(status.name, status.latest, status.revision)
    elseif status.name then
        text = text .. " /pui follow keeps the " .. status.name ..
            " layout up to date with future releases instead."
    end
    Say(text)
end

function Versioning:SetTrack(track)
    PUI.Config.track = track == self.LATEST and self.LATEST or self.PINNED
    PUI.Config:Save()
end

--- True only for an account that chose to follow the latest layout and is behind.
function Versioning:UpdateDue()
    local status = self:Status()
    return status.installed and not status.keepsCurrent
        and status.track == self.LATEST and status.behind
end

--------------------------------------------------------------------------------
-- A layout, and nothing else
--
-- The choices for applying a layout outside the wizard: /pui apply, the settings
-- page, and updates. Modules stay as switched on, nothing is reset first, and
-- graphics are left out entirely - a nil preset and a nil plan are how
-- Installer:ApplyGraphics knows it was never asked. The track is left alone.
--------------------------------------------------------------------------------
function Versioning:ChoicesFor(layoutKey)
    local choices = PUI.Installer:NewChoices(layoutKey)
    for _, module in ipairs(PUI.Modules:OfRole("display")) do
        choices.modules[module.key] = PUI.Modules:IsAvailable(module)
            and PUI.Modules:IsEnabled(module)
            or false
    end
    choices.resetFirst = false
    choices.graphicsPreset = nil
    choices.autoSwitch = nil
    choices.track = nil
    return choices
end

--- Apply the newest revision of the installed layout, with an undo.
--- @return boolean applied, string|nil reason
function Versioning:ApplyLatest()
    local status = self:Status()
    if not status.name then
        return false, "You kept your own setup, so there is no pack layout to update."
    end
    if status.revision and status.latest and status.revision >= status.latest then
        return false, "You already have the latest " .. status.name .. " layout."
    end

    local ok, reason = PUI.Preview:ApplyUpdate(status.layout, self:ChoicesFor(status.layout))
    if not ok then return false, reason end

    Say(("%s layout updated to revision %d. /pui undo puts your previous settings back.")
        :format(status.name, status.latest))
    local changes = PUI.Layouts:ChangesFor(status.layout, status.latest)
    if changes then Say("What changed: " .. changes) end
    return true
end

--- Follow the latest layout from now on, catching up straight away if behind.
function Versioning:Follow()
    self:SetTrack(self.LATEST)
    if self:UpdateDue() then
        return self:ApplyLatest()
    end
    local status = self:Status()
    Say("Following the latest " .. (status.name or "pack") .. " layout. A pack update " ..
        "that changes it will re-apply it when you log in; /pui pin stops that.")
    return true
end

--- Reverse the last layout update, and pin so it is not simply re-applied.
function Versioning:Undo()
    local stored = PUI.Config.updateRestore
    if type(stored) ~= "table" then return false end

    local ok, reason = PUI.Preview:UndoUpdate()
    if not ok then return false, reason end

    PUI.Config.layout = stored.layout or PUI.Config.layout
    PUI.Config.layoutRevision = stored.fromRevision
    PUI.Config.track = self.PINNED
    PUI.Config:Save()

    Say("Layout update undone and your settings put back. You are pinned now, so it " ..
        "will not come back - /pui follow if you change your mind.")
    return true
end

return Versioning
