-- PROBE.lua — measures the transmitter's Lua drawing areas. Dev tool, not an app.
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Copy to the emulator's (or a test transmitter's) Apps folder, add
-- "Screen Probe" in Applications > User Applications, then put its windows on
-- the desktop via Timers/Sensors > Displayed telemetry. An app may register
-- only two windows, so each run measures one pair (set MODE below):
--   MODE = 1: "Probe small" (size 1) and "Probe large" (size 2)
--   MODE = 2: "Probe full+bar" (size 3, keeps the status bar) and
--             "Probe full" (size 4, whole screen)
--   MODE = 3: "Probe auto" (size 0, documented only as "auto") and
--             "Probe small" (size 1, for comparison). Check whether the
--             desktop lets you place "Probe auto" at single or double size.
--   MODE = 4: like MODE 3, but window 1 has an empty title (""). Shows
--             whether the DS-24 II desktop drops the title bar without one.
-- A ruler down the right edge (tick every 10 px, number every 20 px) shows
-- how much of the reported height is actually visible: the DS-24 II desktop
-- draws a title bar inside each window and clips the bottom of the canvas.
-- Open the app's form ("Screen Probe" in the Applications menu) to see the
-- form canvas size.
-- Every size is shown on screen and printed once to the Lua debug console.
-- It also prints system.isPlayback() at start and whenever it changes.

local MODE = 2

local reported = {}

local function report(tag, w, h)
  if reported[tag] ~= w * 10000 + h then
    reported[tag] = w * 10000 + h
    print("PROBE " .. tag .. ": " .. w .. " x " .. h)
  end
end

local function drawRuler(w, h)
  for y = 0, h, 10 do
    lcd.drawLine(w - 6, y, w - 1, y)
    if y % 20 == 0 then
      local label = tostring(y)
      lcd.drawText(w - 8 - lcd.getTextWidth(FONT_MINI, label), y - 5, label, FONT_MINI)
    end
  end
end

local function drawInfo(tag, w, h)
  report(tag, w, h)
  drawRuler(w, h)
  lcd.drawRectangle(0, 0, w, h)
  lcd.drawLine(0, 0, w - 1, h - 1)
  lcd.drawText(4, 2, tag .. " " .. w .. "x" .. h, FONT_BOLD)
  lcd.drawText(4, 2 + lcd.getTextHeight(FONT_BOLD), "fonts N/B/M/Mx: "
    .. lcd.getTextHeight(FONT_NORMAL) .. "/" .. lcd.getTextHeight(FONT_BIG)
    .. "/" .. lcd.getTextHeight(FONT_MINI) .. "/" .. lcd.getTextHeight(FONT_MAXI), FONT_MINI)
end

local function printSmall(w, h) drawInfo("small", w, h) end
local function printLarge(w, h) drawInfo("large", w, h) end
local function printFullBar(w, h) drawInfo("full+bar", w, h) end
local function printFull(w, h) drawInfo("full", w, h) end
local function printAuto(w, h) drawInfo("auto", w, h) end
local function printForm(w, h) drawInfo("form", w, h) end

local lastPlayback = "unset"

local function loop()
  local p = tostring(system.isPlayback())
  if p ~= lastPlayback then
    lastPlayback = p
    print("PROBE isPlayback: " .. p .. " at " .. system.getTimeCounter() .. " ms")
  end
end

local function init()
  print("PROBE device: " .. tostring(system.getDeviceType())
    .. ", firmware " .. tostring(system.getVersion()))
  if MODE == 1 then
    system.registerTelemetry(1, "Probe small", 1, printSmall)
    system.registerTelemetry(2, "Probe large", 2, printLarge)
  elseif MODE == 3 then
    system.registerTelemetry(1, "Probe auto", 0, printAuto)
    system.registerTelemetry(2, "Probe small", 1, printSmall)
  elseif MODE == 4 then
    print("PROBE empty-title register result: "
      .. tostring(system.registerTelemetry(1, "", 0, printAuto)))
    system.registerTelemetry(2, "Probe small", 1, printSmall)
  else
    system.registerTelemetry(1, "Probe full+bar", 3, printFullBar)
    system.registerTelemetry(2, "Probe full", 4, printFull)
  end
  system.registerForm(1, MENU_APPS, "Screen Probe", nil, nil, printForm)
end

return { init = init, loop = loop, author = "Aaron George", version = "1.4", name = "Screen Probe" }
