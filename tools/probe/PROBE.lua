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
-- Open the app's form ("Screen Probe" in the Applications menu) to see the
-- form canvas size.
-- Every size is shown on screen and printed once to the Lua debug console.

local MODE = 2

local reported = {}

local function report(tag, w, h)
  if reported[tag] ~= w * 10000 + h then
    reported[tag] = w * 10000 + h
    print("PROBE " .. tag .. ": " .. w .. " x " .. h)
  end
end

local function drawInfo(tag, w, h)
  report(tag, w, h)
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
local function printForm(w, h) drawInfo("form", w, h) end

local function init()
  print("PROBE device: " .. tostring(system.getDeviceType())
    .. ", firmware " .. tostring(system.getVersion()))
  if MODE == 1 then
    system.registerTelemetry(1, "Probe small", 1, printSmall)
    system.registerTelemetry(2, "Probe large", 2, printLarge)
  else
    system.registerTelemetry(1, "Probe full+bar", 3, printFullBar)
    system.registerTelemetry(2, "Probe full", 4, printFull)
  end
  system.registerForm(1, MENU_APPS, "Screen Probe", nil, nil, printForm)
end

return { init = init, loop = nil, author = "Aaron George", version = "1.1", name = "Screen Probe" }
