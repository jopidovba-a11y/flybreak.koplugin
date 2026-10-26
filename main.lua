local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

-- Difficulty presets: hits needed, delay range between jumps (seconds),
-- and fly size (in dp, scaled to the screen). The first one is the default.
local DIFFICULTIES = {
    { key = "normal", name = _("Normal"), hits = 3, min_delay = 0.4,  max_delay = 0.9, size = 64 },
    { key = "hard",   name = _("Hard"),   hits = 5, min_delay = 0.25, max_delay = 0.6, size = 48 },
}

---------------------------------------------------------------------
-- Overlay: full-screen widget that swallows taps and draws the fly
---------------------------------------------------------------------
local FlyOverlay = InputContainer:extend{
    required_hits = 3,   -- taps on the fly needed to finish it off
    min_delay = 0.4,     -- seconds between jumps (min)
    max_delay = 0.9,     -- seconds between jumps (max)
    size_dp = 64,        -- fly size
    splat_delay = 1.2,   -- seconds the splats stay after the last hit
    tired_after = 30,    -- seconds without any touch before the fly gets tired
}

function FlyOverlay:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.size = Screen:scaleBySize(self.size_dp)
    self.splat_size = math.floor(self.size * 1.5)
    self.margin = Screen:scaleBySize(20)
    self.hits = 0
    self.finished = false
    self.tired = false   -- a tired fly stays still (no more refreshes)
    self.splats = {}     -- one rect per squashed fly, kept until the overlay closes
    self.fly_rect = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }

    -- Use fly.png if present, otherwise a black square as placeholder
    local image_path = self.plugin_path .. "/fly.png"
    if lfs.attributes(image_path, "mode") == "file" then
        self.fly_image = ImageWidget:new{
            file = image_path,
            width = self.size,
            height = self.size,
            alpha = true,
        }
    end

    -- Use splat.png if present, otherwise a gray square as placeholder
    local splat_path = self.plugin_path .. "/splat.png"
    if lfs.attributes(splat_path, "mode") == "file" then
        self.splat_image = ImageWidget:new{
            file = splat_path,
            width = self.splat_size,
            height = self.splat_size,
            alpha = true,
        }
    end

    -- Swallow all taps/swipes/holds so they never reach the book
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        Hold = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }

    self.move_task = function() self:moveFly() end
    self.dismiss_task = function() self:dismiss() end
    self.tired_task = function() self:getTired() end
    self:placeFly()
    self:scheduleMove()
    self:scheduleTired()
end

function FlyOverlay:placeFly()
    local max_x = self.dimen.w - self.size - 2 * self.margin
    local max_y = self.dimen.h - self.size - 2 * self.margin
    self.fly_rect.x = self.margin + math.random(0, max_x)
    self.fly_rect.y = self.margin + math.random(0, max_y)
end

function FlyOverlay:scheduleMove()
    UIManager:unschedule(self.move_task)
    local delay = self.min_delay + math.random() * (self.max_delay - self.min_delay)
    UIManager:scheduleIn(delay, self.move_task)
end

-- (Re)start the inactivity countdown
function FlyOverlay:scheduleTired()
    UIManager:unschedule(self.tired_task)
    UIManager:scheduleIn(self.tired_after, self.tired_task)
end

-- No touch for a while: the fly stops moving to save battery
function FlyOverlay:getTired()
    self.tired = true
    UIManager:unschedule(self.move_task)
end

-- Any touch counts as activity: restart the countdown and wake a tired fly
function FlyOverlay:registerActivity()
    if self.finished then return end
    self:scheduleTired()
    if self.tired then
        self.tired = false
        self:scheduleMove()
    end
end

-- Move the fly to a new spot. extra_rect (optional) is an additional
-- area to refresh, e.g. a splat that was just added.
function FlyOverlay:moveFly(extra_rect)
    local old_rect = self.fly_rect:copy()
    self:placeFly()
    -- Mark the reader dirty (not the overlay) so the page is repainted
    -- under the old fly position, then the overlay paints on top again
    UIManager:setDirty(self.reader_ui, "fast", old_rect)
    if extra_rect then
        UIManager:setDirty(self.reader_ui, "ui", extra_rect:copy())
    end
    UIManager:setDirty(self.reader_ui, "fast", self.fly_rect:copy())
    self:scheduleMove()
end

-- Add a splat centered on the current fly position (clamped inside the screen)
function FlyOverlay:addSplat()
    local cx = self.fly_rect.x + self.size / 2
    local cy = self.fly_rect.y + self.size / 2
    local sx = math.floor(cx - self.splat_size / 2)
    local sy = math.floor(cy - self.splat_size / 2)
    sx = math.max(0, math.min(sx, self.dimen.w - self.splat_size))
    sy = math.max(0, math.min(sy, self.dimen.h - self.splat_size))
    local rect = Geom:new{ x = sx, y = sy, w = self.splat_size, h = self.splat_size }
    table.insert(self.splats, rect)
    return rect
end

-- Last hit: stop the fly and leave only the splats on screen for a moment
function FlyOverlay:finish(splat_rect)
    UIManager:unschedule(self.move_task)
    UIManager:unschedule(self.tired_task)
    self.finished = true
    -- Erase the fly (repaint the page) and draw the last splat on top
    UIManager:setDirty(self.reader_ui, "ui", self.fly_rect:copy())
    UIManager:setDirty(self.reader_ui, "ui", splat_rect:copy())
    UIManager:scheduleIn(self.splat_delay, self.dismiss_task)
end

-- Smallest rect covering the fly and every splat (used to refresh on close)
function FlyOverlay:getCoveredRect()
    local region = self.fly_rect:copy()
    for idx = 1, #self.splats do
        region = region:combine(self.splats[idx])
    end
    return region
end

function FlyOverlay:paintTo(bb, x, y)
    -- Splats first, the fly on top (the fly is hidden once finished)
    for idx = 1, #self.splats do
        local r = self.splats[idx]
        if self.splat_image then
            self.splat_image:paintTo(bb, r.x, r.y)
        else
            bb:paintRect(r.x, r.y, self.splat_size, self.splat_size, Blitbuffer.COLOR_DARK_GRAY)
        end
    end
    if self.finished then return end
    if self.fly_image then
        self.fly_image:paintTo(bb, self.fly_rect.x, self.fly_rect.y)
    else
        bb:paintRect(self.fly_rect.x, self.fly_rect.y, self.size, self.size, Blitbuffer.COLOR_BLACK)
    end
end

function FlyOverlay:onTap(arg, ges)
    -- Ignore taps while the final splats are showing (still consume them)
    if self.finished then return true end
    self:registerActivity()
    if ges and ges.pos and self.fly_rect:contains(ges.pos) then
        self.hits = self.hits + 1
        local splat_rect = self:addSplat()
        if self.hits >= self.required_hits then
            self:finish(splat_rect)
        else
            self:moveFly(splat_rect) -- jump right away after a hit
        end
    end
    return true -- always consume the tap
end

function FlyOverlay:onSwipe()
    self:registerActivity()
    return true
end

function FlyOverlay:onHold()
    self:registerActivity()
    return true
end

-- No "return true" here so the event keeps propagating to other widgets
function FlyOverlay:onSuspend()
    UIManager:unschedule(self.move_task)
    UIManager:unschedule(self.dismiss_task)
    UIManager:unschedule(self.tired_task)
end

function FlyOverlay:onResume()
    if self.finished then
        UIManager:scheduleIn(self.splat_delay, self.dismiss_task)
    else
        -- Waking up the device counts as activity: fresh start
        self.tired = false
        self:scheduleMove()
        self:scheduleTired()
    end
end

function FlyOverlay:dismiss()
    UIManager:unschedule(self.move_task)
    UIManager:unschedule(self.dismiss_task)
    UIManager:unschedule(self.tired_task)
    UIManager:close(self, "ui", self:getCoveredRect())
    if self.on_dismiss then self.on_dismiss() end
end

function FlyOverlay:onCloseWidget()
    UIManager:unschedule(self.move_task)
    UIManager:unschedule(self.dismiss_task)
    UIManager:unschedule(self.tired_task)
    if self.fly_image then
        self.fly_image:free()
        self.fly_image = nil
    end
    if self.splat_image then
        self.splat_image:free()
        self.splat_image = nil
    end
end

---------------------------------------------------------------------
-- Plugin
---------------------------------------------------------------------
local FlyBreak = WidgetContainer:extend{
    name = "flybreak",
    is_doc_only = true, -- only load inside the reader
}

function FlyBreak:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/flybreak.lua")
    self.enabled = self.settings:nilOrTrue("enabled")
    self.interval_min = self.settings:readSetting("interval_min") or 20
    self.difficulty_key = self.settings:readSetting("difficulty") or "normal"
    self.elapsed = 0              -- seconds of reading time already counted
    self.timer_started_at = nil
    self.overlay = nil
    self.show_task = function() self:showFly() end
    math.randomseed(os.time())
    self.ui.menu:registerToMainMenu(self)
end

-- Current difficulty preset (falls back to the first one, "normal",
-- e.g. if an old setting like "easy" is still saved)
function FlyBreak:getDifficulty()
    for idx = 1, #DIFFICULTIES do
        if DIFFICULTIES[idx].key == self.difficulty_key then
            return DIFFICULTIES[idx]
        end
    end
    return DIFFICULTIES[1]
end

-- Start (or resume) the countdown with the remaining reading time
function FlyBreak:startTimer()
    self:stopTimer()
    if not self.enabled or self.overlay then return end
    local remaining = math.max(1, self.interval_min * 60 - self.elapsed)
    self.timer_started_at = os.time()
    UIManager:scheduleIn(remaining, self.show_task)
end

-- Stop the countdown and keep the reading time already counted
function FlyBreak:stopTimer()
    UIManager:unschedule(self.show_task)
    if self.timer_started_at then
        self.elapsed = self.elapsed + (os.time() - self.timer_started_at)
        self.timer_started_at = nil
    end
end

function FlyBreak:showFly()
    self.elapsed = 0
    self.timer_started_at = nil
    if self.overlay then return end
    local d = self:getDifficulty()
    self.overlay = FlyOverlay:new{
        plugin_path = self.path,
        reader_ui = self.ui, -- widget below the overlay, needed to erase the old fly
        required_hits = d.hits,
        min_delay = d.min_delay,
        max_delay = d.max_delay,
        size_dp = d.size,
        on_dismiss = function()
            self.overlay = nil
            self:startTimer()
        end,
    }
    UIManager:show(self.overlay, "fast", self.overlay.fly_rect:copy())
end

function FlyBreak:onReaderReady()
    self.elapsed = 0
    self:startTimer()
end

-- Screen off: pause the count. Screen on: continue where it left off.
function FlyBreak:onSuspend()
    self:stopTimer()
end

function FlyBreak:onResume()
    if not self.overlay then self:startTimer() end
end

function FlyBreak:onCloseDocument()
    self:stopTimer()
    if self.overlay then
        UIManager:close(self.overlay)
        self.overlay = nil
    end
end

function FlyBreak:addToMainMenu(menu_items)
    -- One radio item per difficulty preset
    local difficulty_items = {}
    for idx = 1, #DIFFICULTIES do
        local d = DIFFICULTIES[idx]
        table.insert(difficulty_items, {
            text = d.name,
            radio = true,
            checked_func = function() return self:getDifficulty().key == d.key end,
            callback = function(touchmenu_instance)
                self.difficulty_key = d.key
                self.settings:saveSetting("difficulty", d.key)
                self.settings:flush()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end

    menu_items.fly_break = {
        text = _("Fly Break"),
        sorting_hint = "more_tools",
        sub_item_table = {
            -- 1) Enable / disable
            {
                text = _("Enabled"),
                checked_func = function() return self.enabled end,
                callback = function()
                    self.enabled = not self.enabled
                    self.settings:saveSetting("enabled", self.enabled)
                    self.settings:flush()
                    self:stopTimer()
                    self.elapsed = 0
                    if self.enabled then self:startTimer() end
                end,
            },
            -- 2) Interval, typed with the numeric keyboard
            {
                text_func = function()
                    return T(_("Interval: %1 min"), self.interval_min)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local dialog
                    dialog = InputDialog:new{
                        title = _("Minutes between flies"),
                        input = tostring(self.interval_min),
                        input_type = "number",
                        buttons = {{
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function() UIManager:close(dialog) end,
                            },
                            {
                                text = _("Set"),
                                is_enter_default = true,
                                callback = function()
                                    local value = tonumber(dialog:getInputText())
                                    -- Reject empty or invalid input and keep the dialog open
                                    if not value or value < 1 then
                                        UIManager:show(InfoMessage:new{
                                            text = _("Please enter a number of minutes (1 or more)."),
                                        })
                                        return
                                    end
                                    value = math.floor(value)
                                    UIManager:close(dialog)
                                    self.interval_min = value
                                    self.settings:saveSetting("interval_min", value)
                                    self.settings:flush()
                                    self.elapsed = 0
                                    self:startTimer()
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            },
                        }},
                    }
                    UIManager:show(dialog)
                    dialog:onShowKeyboard()
                end,
            },
            -- 3) Difficulty (radio submenu)
            {
                text_func = function()
                    return T(_("Difficulty: %1"), self:getDifficulty().name)
                end,
                sub_item_table = difficulty_items,
            },
            -- 4) Test: show a fly right away
            {
                text = _("Show fly now (test)"),
                callback = function(touchmenu_instance)
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                    self:stopTimer()
                    UIManager:scheduleIn(1, self.show_task)
                end,
            },
        },
    }
end

return FlyBreak