-- HELLO.lua — style reference app for the JETI DS-24 (Lua 5.3).
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- A switch-driven flight timer that shows in a small desktop telemetry window
-- and announces elapsed minutes. It exercises the app lifecycle, a settings
-- form, persistence, a telemetry window and audio, without touching anything
-- that affects flight (constitution principle I).
--
-- Not deployed: it lives in docs/examples/style/ as the pattern real apps
-- follow. To try it, copy it to the emulator's Apps folder (a real app would
-- be named AG-xxxxx.lua) and add it in Applications > User Applications.

local APP_NAME = "Hello Timer"
local APP_VERSION = "0.1.0"

-- Persisted settings (per model). pSave stores integers/strings/SwitchItems only.
local KEY_SWITCH = "sw"
local KEY_ANNOUNCE_MIN = "annMin"

local startSwitch = nil     ---@type SwitchItem|nil
local announceMinutes = 1   -- 0 disables announcements

-- Runtime state, rebuilt on every model change (principle IV).
local running = false
local elapsedMs = 0
local lastTick = 0
local lastShownSec = -1
local lastAnnouncedMin = 0
local timeText = "00:00"    -- cached so the print function never formats (principle VI)

local TICK_MS = 100         -- work at most 10x per second, not every 20-30 ms loop

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

local function refreshTimeText(totalSec)
  local minutes = totalSec // 60
  local seconds = totalSec % 60
  timeText = string.format("%02d:%02d", minutes, seconds)
end

local function switchIsOn()
  if startSwitch == nil then
    return false
  end
  local value = system.getInputsVal(startSwitch)
  return value ~= nil and value > 0
end

------------------------------------------------------------------------------
-- Settings form
------------------------------------------------------------------------------

local function onSwitchChanged(value)
  startSwitch = value
  system.pSave(KEY_SWITCH, value)
end

local function onAnnounceChanged(value)
  announceMinutes = value
  system.pSave(KEY_ANNOUNCE_MIN, value)
end

local function initForm()
  form.addRow(2)
  form.addLabel({ label = "Start switch", width = 180 })
  form.addInputbox(startSwitch, false, onSwitchChanged)

  form.addRow(2)
  form.addLabel({ label = "Announce every (min)", width = 220 })
  form.addIntbox(announceMinutes, 0, 30, 1, 0, 1, onAnnounceChanged)

  form.addRow(1)
  form.addLabel({ label = "0 = no announcements", font = FONT_MINI })

  form.setButton(1, "Reset", ENABLED)
end

local function keyForm(keyCode)
  if keyCode == KEY_1 then
    elapsedMs = 0
    lastShownSec = -1
    lastAnnouncedMin = 0
    refreshTimeText(0)
  end
end

------------------------------------------------------------------------------
-- Telemetry window (the only place lcd.* is allowed)
------------------------------------------------------------------------------

local function printTelemetry(width, height)
  local font = FONT_MAXI
  local textWidth = lcd.getTextWidth(font, timeText)
  local textHeight = lcd.getTextHeight(font)
  lcd.drawText((width - textWidth) // 2, (height - textHeight) // 2, timeText, font)
  if not running then
    lcd.drawText(4, 2, "stopped", FONT_MINI)
  end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local function init()
  startSwitch = system.pLoad(KEY_SWITCH)
  announceMinutes = system.pLoad(KEY_ANNOUNCE_MIN, 1)

  running = false
  elapsedMs = 0
  lastShownSec = -1
  lastAnnouncedMin = 0
  lastTick = system.getTimeCounter()
  refreshTimeText(0)

  system.registerForm(1, MENU_APPS, APP_NAME, initForm, keyForm)
  system.registerTelemetry(1, APP_NAME, 1, printTelemetry)
end

local function loop()
  local now = system.getTimeCounter()
  local delta = now - lastTick
  if delta < TICK_MS then
    return
  end
  lastTick = now

  running = switchIsOn()
  if not running then
    return
  end

  elapsedMs = elapsedMs + delta
  local totalSec = elapsedMs // 1000
  if totalSec ~= lastShownSec then
    lastShownSec = totalSec
    refreshTimeText(totalSec)
  end

  if announceMinutes > 0 then
    local totalMin = totalSec // 60
    if totalMin > lastAnnouncedMin and totalMin % announceMinutes == 0 then
      lastAnnouncedMin = totalMin
      system.playNumber(totalMin, 0, "min")
    end
  end
end

local function destroy()
  running = false
end

---@type JetiApp
return {
  init = init,
  loop = loop,
  destroy = destroy,
  author = "Aaron George",
  version = APP_VERSION,
  name = APP_NAME,
}
