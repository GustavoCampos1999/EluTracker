-- mem_log.lua
--
-- STANDALONE, TEMPORARY memory-usage diagnostic logger. This exists purely
-- to answer one question -- "is RAM climbing over a play session, and if
-- so how fast" -- and is meant to be deleted once that's answered.
--
-- On purpose, this does NOT touch crash_alert.lua or settings_manager.lua
-- at all: it keeps its own tiny save file (elu_mem_log.lua) and its own
-- require/OnLoad/OnUnload/OnUpdate footprint in main.lua, so removing it
-- later is a 2-step job:
--   1. Delete this file (mem_log.lua) and, if you don't want the collected
--      data anymore either, elu_mem_log.lua next to it.
--   2. In main.lua, remove the 5 lines each tagged "-- MEM LOGGER (temporary)".
-- That's it -- nothing else in the addon references this module.
--
-- What it does: once a minute, it samples api.GetMemoryUsage() (the same
-- call crash_alert.lua already uses for its own warnings) and appends one
-- {elapsed, mb} entry to a table saved via api.File:Write. "elapsed" is
-- HH:MM:SS since THIS addon loaded (from api.Time:GetUiMsec(), the same
-- clock used everywhere else in Elu Tracker) -- not wall-clock time, since
-- the addon API doesn't give a reliable wall-clock read. To line entries up
-- with ArcheAge.log's own <HH:MM:SS> timestamps, add the elapsed time to
-- the very first timestamp in that session's ArcheAge.log.

local api = require('api')

local mem_log_addon = {}

local LOG_FILE = "elu_mem_log.lua"
local SAMPLE_INTERVAL_MS = 60000 -- once a minute -- frequent enough to see a trend, light enough to ignore
local MAX_ENTRIES = 1500 -- ~25h of 1/min samples; oldest entries drop off past this so the file can't grow forever

local entries = {}
local timeSinceLastSample = 0
local startUiMsec = 0

local function LoadLog()
    local data = api.File:Read(LOG_FILE)
    if type(data) == "table" then
        entries = data
    end
end

local function SaveLog()
    api.File:Write(LOG_FILE, entries)
end

local function AppendEntry(entry)
    table.insert(entries, entry)
    if #entries > MAX_ENTRIES then
        table.remove(entries, 1)
    end
    SaveLog()
end

local function FormatElapsed(ms)
    local totalSec = math.floor((ms or 0) / 1000)
    if totalSec < 0 then totalSec = 0 end
    local h = math.floor(totalSec / 3600)
    local m = math.floor((totalSec % 3600) / 60)
    local s = totalSec % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- Same MB-vs-bytes normalization crash_alert.lua already uses for this same
-- api.GetMemoryUsage() call (some builds return MB directly, others bytes).
local function ReadMemoryMB()
    local ok, mem = pcall(function() return api.GetMemoryUsage() end)
    if not ok or type(mem) ~= "number" then
        return nil
    end
    local isMB = (mem < 100000)
    return math.floor(isMB and mem or (mem / 1024 / 1024))
end

local function Sample()
    local mb = ReadMemoryMB()
    if not mb then
        return
    end
    local elapsedMs = api.Time:GetUiMsec() - startUiMsec
    AppendEntry({ elapsed = FormatElapsed(elapsedMs), mb = mb })
end

function mem_log_addon:OnLoad()
    startUiMsec = api.Time:GetUiMsec()
    timeSinceLastSample = 0
    LoadLog()
    -- Mark where a new play session starts in the saved log, so entries
    -- from different sessions aren't mistaken for one continuous climb.
    AppendEntry({ elapsed = "00:00:00", mb = ReadMemoryMB(), sessionStart = true })
end

function mem_log_addon:OnUnload()
    timeSinceLastSample = 0
end

function mem_log_addon:OnUpdate(dt)
    timeSinceLastSample = timeSinceLastSample + (type(dt) == "number" and dt or 1000)
    if timeSinceLastSample >= SAMPLE_INTERVAL_MS then
        timeSinceLastSample = 0
        Sample()
    end
end

return mem_log_addon
