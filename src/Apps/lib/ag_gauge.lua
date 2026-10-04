-- ag_gauge.lua — dial geometry and drawing helpers for round gauges.
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Shared module (constitution VII): no mutable state. newDial, newCircle,
-- point and scaleStep are pure and may be called anywhere. face, arc, band,
-- mark and tick draw with lcd and may only be called from a registered print
-- function. Callers set the color with lcd.setColor before each draw call and
-- pass in their own renderer from lcd.renderer().
--
-- A dial is a table { n = steps, cx = {...}, sy = {...} } of unit cos / sin
-- values for steps + 1 points. sy is already flipped for screen coordinates
-- (y grows downward), so a point is (x + cx[i] * r, y + sy[i] * r).

local M = {}

-- Candidate major tick steps, in display units (constant).
local STEPS = { 10, 20, 25, 50, 100, 200, 250, 500 }

local function clamp01(f)
  if f < 0 then
    return 0
  elseif f > 1 then
    return 1
  end
  return f
end

-- Points going clockwise on screen from startDeg (math angle, 0 = right,
-- 90 = up) over sweepDeg degrees. Defaults: 270° dial, zero at lower-left.
function M.newDial(steps, startDeg, sweepDeg)
  steps = steps or 54
  startDeg = startDeg or 225
  sweepDeg = sweepDeg or 270
  local cx, sy = {}, {}
  for i = 0, steps do
    local a = math.rad(startDeg - sweepDeg * i / steps)
    cx[i + 1] = math.cos(a)
    sy[i + 1] = -math.sin(a)
  end
  return { n = steps, cx = cx, sy = sy }
end

-- A closed unit circle, for filled faces.
function M.newCircle(points)
  return M.newDial(points or 72, 0, 360)
end

-- Unit cos / sin at fraction f (0..1) along the dial, interpolated.
local function point(dial, f)
  local n = dial.n
  if f <= 0 then
    return dial.cx[1], dial.sy[1]
  elseif f >= 1 then
    return dial.cx[n + 1], dial.sy[n + 1]
  end
  local p = f * n
  local i = math.floor(p)
  local t = p - i
  local c1, s1 = dial.cx[i + 1], dial.sy[i + 1]
  return c1 + (dial.cx[i + 2] - c1) * t, s1 + (dial.sy[i + 2] - s1) * t
end
M.point = point

-- Smallest major tick step giving at most 8 intervals up to fullScale.
function M.scaleStep(fullScale)
  for i = 1, #STEPS do
    if fullScale / STEPS[i] <= 8 then
      return STEPS[i]
    end
  end
  return STEPS[#STEPS]
end

-- Filled polygon of the unit circle scaled to radius. If maxY is given, the
-- circle is cut flat there: the renderer does not clip to the window, so a
-- face reaching past the visible area would draw over the window border.
function M.face(r, circle, cx, cy, radius, maxY)
  r:reset()
  for k = 1, circle.n + 1 do
    local y = cy + circle.sy[k] * radius
    if maxY and y > maxY then
      y = maxY
    end
    r:addPoint(cx + circle.cx[k] * radius, y)
  end
  r:renderPolygon()
end

-- Arc from fraction f0 to f1 at radius, drawn as one anti-aliased polyline.
-- alpha (0..1, default 1) makes it translucent, e.g. for glow bands.
function M.arc(r, dial, cx, cy, radius, f0, f1, width, alpha)
  f0 = clamp01(f0)
  f1 = clamp01(f1)
  if f1 <= f0 then
    return
  end
  local n = dial.n
  r:reset()
  local c, s = point(dial, f0)
  r:addPoint(cx + c * radius, cy + s * radius)
  -- Table points strictly between f0 and f1 (point k sits at k / n).
  for k = math.floor(f0 * n) + 1, math.ceil(f1 * n) - 1 do
    r:addPoint(cx + dial.cx[k + 1] * radius, cy + dial.sy[k + 1] * radius)
  end
  c, s = point(dial, f1)
  r:addPoint(cx + c * radius, cy + s * radius)
  r:renderPolyline(width, alpha or 1)
end

-- Most dial steps in one band polygon. JETI Studio crashed drawing a
-- 90-step (about 184-point) band; DFM-InsP's live arcs stay near 24 steps
-- (about 50 points) on the transmitter. 18 steps is at most 40 points.
local BAND_STEPS = 18

-- One polygon of a band: the outer edge forward, the inner edge back.
local function bandPart(r, dial, cx, cy, rOuter, rInner, f0, f1, alpha)
  local n = dial.n
  local k0, k1 = math.floor(f0 * n) + 1, math.ceil(f1 * n) - 1
  r:reset()
  local c, s = point(dial, f0)
  r:addPoint(cx + c * rOuter, cy + s * rOuter)
  for k = k0, k1 do
    r:addPoint(cx + dial.cx[k + 1] * rOuter, cy + dial.sy[k + 1] * rOuter)
  end
  c, s = point(dial, f1)
  r:addPoint(cx + c * rOuter, cy + s * rOuter)
  r:addPoint(cx + c * rInner, cy + s * rInner)
  for k = k1, k0, -1 do
    r:addPoint(cx + dial.cx[k + 1] * rInner, cy + dial.sy[k + 1] * rInner)
  end
  c, s = point(dial, f0)
  r:addPoint(cx + c * rInner, cy + s * rInner)
  r:renderPolygon(alpha or 1)
end

-- Filled ring segment between radii rOuter and rInner, from fraction f0 to
-- f1. Unlike a wide polyline it covers each pixel once, with no overlapping
-- joints, so a translucent band has no bright seams and both edges follow
-- the circle (added after transmitter testing, 2026-10-03). Drawn as pieces
-- of at most BAND_STEPS dial steps each. alpha 0..1, default 1.
function M.band(r, dial, cx, cy, rOuter, rInner, f0, f1, alpha)
  f0 = clamp01(f0)
  f1 = clamp01(f1)
  local n = dial.n
  while f1 > f0 do
    local fb = math.min(f1, (math.floor(f0 * n) + BAND_STEPS) / n)
    bandPart(r, dial, cx, cy, rOuter, rInner, f0, fb, alpha)
    f0 = fb
  end
end

-- Anti-aliased radial line at fraction f between radii r1 and r2.
function M.mark(r, dial, cx, cy, r1, r2, f, width)
  local c, s = point(dial, clamp01(f))
  r:reset()
  r:addPoint(cx + c * r1, cy + s * r1)
  r:addPoint(cx + c * r2, cy + s * r2)
  r:renderPolyline(width)
end

-- Plain radial line at fraction f; cheaper than mark, for scale ticks.
function M.tick(dial, cx, cy, r1, r2, f)
  local c, s = point(dial, clamp01(f))
  lcd.drawLine(math.floor(cx + c * r1 + 0.5), math.floor(cy + s * r1 + 0.5),
    math.floor(cx + c * r2 + 0.5), math.floor(cy + s * r2 + 0.5))
end

return M
