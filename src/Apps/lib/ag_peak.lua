-- ag_peak.lua — spike-filtered session maximum.
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Shared module (constitution VII): no mutable state. The caller owns the
-- state table from new() and passes it, with the current time in ms, to
-- update() and reset(). No lcd, form or system calls.
--
-- A reading raises the max only once it is confirmed (Speed Gauge research
-- R5): by a second, different reading (the lower of the two counts), or by
-- staying unchanged for HOLD_MS. A single-sample spike therefore never
-- becomes the max, and a perfectly steady value still registers.

local M = {}

local HOLD_MS = 1000

---@return table st { max, prev, prevT }
function M.new()
  return { max = 0, prev = nil, prevT = 0 }
end

---@param st table state from M.new()
---@param value number a valid reading
---@param nowMs integer system.getTimeCounter()
---@return number max
---@return boolean rose true when this reading raised the max
function M.update(st, value, nowMs)
  local prev = st.prev
  local candidate = nil
  if prev == nil then
    st.prev, st.prevT = value, nowMs
  elseif value ~= prev then
    candidate = math.min(prev, value)
    st.prev, st.prevT = value, nowMs
  elseif nowMs - st.prevT >= HOLD_MS then
    candidate = value
  end
  if candidate ~= nil and candidate > st.max then
    st.max = candidate
    return st.max, true
  end
  return st.max, false
end

---@param st table state from M.new()
function M.reset(st)
  st.max, st.prev, st.prevT = 0, nil, 0
end

return M
