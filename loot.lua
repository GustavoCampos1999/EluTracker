local api = require("api")

local settingsManager = require('Elu_Tracker/settings_manager')
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local elu_loot_tracker_addon = {
	name = "Loot Tracker",
	author = "Eludelu",
	version = "",
	desc = "Tracks farming/looting sessions: profit, kills and labor spent."
}

--- Item Task Type IDs
--> AAC 9 = harvested wild potato
local ITEM_TASK_ID_FARMED = 9
--> AAC 10 = looted from monsters
local ITEM_TASK_ID_LOOTED_FROM_MONSTER = 10
--> AAC 41 = From dawnsdrop pickaxe
local ITEM_TASK_ID_DAWNSDROP_PICKAXE = 41

local AH_PRICES

-- Top-level windows owned by this module. Each one is created at most once
-- per OnLoad and explicitly freed in OnUnload (see the bottom of this file)
-- -- creating a fresh one every reload/click without freeing the old one is
-- exactly the kind of leak that has previously taken this addon's window
-- count from 30 to 60 in a few seconds (see main.lua's OnLoad guard).
local eluLootEventWindow
local lootTrackerOverlay

-- Set by CreateUI (called once by main.lua's subWindowConstructor guard) so
-- OnLoad/OnUpdate can reach the tab's own widgets directly, without poking
-- through eluDisplayWindow.tab.window[n] -- see fish_tracker.lua / packs.lua
-- for the same module-level-local convention.
local sessionScrollList

-- Session details popup. Built once, lazily, the first time the player
-- actually clicks into a past session (most players click into very few of
-- their sessions) -- and reused after that. The original version of this
-- file called api.Interface:CreateWindow("lootSessionDetailsWindow", ...)
-- on every single click with no cache and no Free(), leaking one full
-- window (plus ~10 child widgets) per click for the lifetime of the
-- session. That was the single biggest source of "extra windows" this
-- tab was creating.
local lootSessionDetailsWindow
local lootSessionItemsList

local lastKnownZone
local currentZone

local currentSession
local pastSessions
local pastSessionsFilename

local laborUsedTimer = 0
local laborUsed = false
local LABOR_USED_TIMER_RATE = 300

local sessionClockRefreshTimer = 0
local SESSION_CLOCK_REFRESH_RATE = 1000

-- BUG FOUND: the live session clock used to accumulate the `dt` passed into
-- OnUpdate every tick ("lootTrackerSessionTimer = lootTrackerSessionTimer +
-- dt"), and every profit/kills-per-hour figure on the live overlay was
-- computed from that same accumulated value. On this client, that ran the
-- clock roughly 2x real speed -- a real 30-minute farming session showed up
-- as ~1h on the overlay, and profit/kills per hour were understated by
-- half to match. stopwatch.lua's own OnUpdate never had this problem
-- because it was written to NOT trust dt for elapsed time at all -- it
-- tracks a wall-clock start timestamp (api.Time:GetUiMsec()) and computes
-- elapsed as a plain timestamp difference every time it needs one instead.
-- This session clock now uses that same proven approach:
--   lootTrackerSessionTimer -- elapsed ms banked from all PREVIOUS running
--                              segments (i.e. frozen at whatever it was the
--                              last time the session was paused, ended, or
--                              first started). Still persisted to disk as
--                              savedSessionTimer, same as before.
--   sessionSegmentStartMs   -- api.Time:GetUiMsec() timestamp of when the
--                              CURRENT running segment began (session
--                              start, resume, or restoring an
--                              already-running session on reload).
-- GetLiveSessionElapsedMs() (below, near OnUpdate) adds the two together
-- only while actually running, exactly mirroring swElapsedMs/startTimeMs/
-- swRunning in stopwatch.lua.
local lootTrackerSessionTimer = 0
local sessionSegmentStartMs = 0
local sessionPaused

local displayRefreshCounter = 0
local DISPLAY_REFRESH_MS = 60000

local pageSize = 20 --> number of sessions on page
-- Cap matches packs.lua's MAX_SESSIONS (pageSize * 10) -- previously hardcoded
-- to 160 here while packs used 200, which meant loot sessions were being
-- silently evicted 40 entries sooner than pack sessions.
local MAX_SESSIONS = pageSize * 10
local maxPage

-- helpers
local function split(s, sep)
    local fields = {}

    sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)

    return fields
end

local function ConvertColor(color)
    return color / 255
end

-- Guards every division below against a zero (or nil) denominator, which
-- the original code did not -- a session ended in the same second it was
-- started (duration == 0), or one with zero labor spent, produced "inf"/
-- "nan" being formatted straight into the UI (e.g. "Profit: 12g (infg/hr)").
local function safeDiv(numerator, denominator)
    numerator = tonumber(numerator) or 0
    denominator = tonumber(denominator)
    if denominator == nil or denominator == 0 then
        return 0
    end
    return numerator / denominator
end

local function differenceBetweenTimestamps(time1, time2)
    local time1Suffix = string.sub(time1, (#time1 - 2) * -1)
    local time2Suffix = string.sub(time2, (#time2 - 2) * -1)
    return tonumber(time1Suffix) - tonumber(time2Suffix)
end

local function displayTimeString(timeInSeconds)
    local minutes = math.floor(timeInSeconds / (1*60)) % 60
    local hours = math.floor(timeInSeconds / (1*60*60)) % 24

    return string.format("%02dh %02dm", hours, minutes)
end

local function displayOverlayTimeString(timeInSeconds)
    local seconds = math.floor(timeInSeconds) % 60
    local minutes = math.floor(timeInSeconds / (1*60)) % 60
    local hours = math.floor(timeInSeconds / (1*60*60)) % 24

    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function safeTimeToDate(timestamp)
    local dateStr = ""
    if api.Time and api.Time.TimeToDate then
        pcall(function() dateStr = api.Time:TimeToDate(timestamp) end)
    end
    return dateStr or ""
end

local function updateLastKnownChannel(channelId, channelName)
    if channelId ~= 1 then
      return
    end
    if currentZone ~= nil then
      lastKnownZone = currentZone
    end
    currentZone = channelName
end

local function getCleanedItemId(itemId)
    -- Remove the first and last characters of the Item ID string
    if string.sub(itemId, 1, 1) == "[" and string.sub(itemId, -1) == "]" then
        return string.sub(itemId, 2, #itemId - 1)
    end
    return itemId
end

local function fillSessionTableData(itemScrollList, pageIndex)
    local startingIndex = 1
    if pageIndex > 1 then
        startingIndex = ((pageIndex - 1) * pageSize) + 1
    end
    local endingIndex = startingIndex + pageSize
    itemScrollList:DeleteAllDatas()

    if pastSessions == nil then return end

    -- ipairs, not pairs: pastSessions.sessions is a proper array (built via
    -- table.insert(...,1,...) / table.remove(...), never given holes), and
    -- the rest of this file already relies on ipairs for it (see
    -- saveCurrentSessionToFile/drawLootSessionDetails below). pairs() over
    -- an array isn't guaranteed to visit 1..n in order, which is exactly
    -- what "count" here needs to line up with the correct page slice and
    -- with the "index" each row hands back to drawLootSessionDetails.
    local count = 1
    for _, sessionObject in ipairs(pastSessions["sessions"]) do
        if count >= startingIndex and count < endingIndex then
            local itemData = {
                -- Sessions data fields
                localTimestamp = sessionObject.localTimestamp,
                endTimestamp = sessionObject.endTimestamp,
                items = sessionObject.items,
                profitTotal = sessionObject.profitTotal,
                laborSpent = sessionObject.laborSpent,
                costTotal = sessionObject.costTotal,
                kills = sessionObject.kills,
                zone = sessionObject.zone,
                index = count,

                -- Required fields
                isViewData = true,
                isAbstention = false
            }
            itemScrollList:InsertData(count, 1, itemData)
        end
        count = count + 1
    end
end

local function refreshSessionList(pageIndex)
    if sessionScrollList == nil then return end
    pageIndex = pageIndex or 1
    if pastSessions ~= nil and pastSessions.sessions ~= nil then
        maxPage = math.ceil(#pastSessions.sessions / pageSize)
    else
        maxPage = 1
    end
    if maxPage == 0 then maxPage = 1 end
    sessionScrollList.pageControl.maxPage = maxPage
    fillSessionTableData(sessionScrollList, pageIndex)
    sessionScrollList.pageControl:SetCurrentPage(pageIndex, true)
end

local function saveCurrentSessionToFile()
    if pastSessions == nil then
        pastSessions = {}
        pastSessions["sessions"] = {}
    end

    local items = currentSession["items"]
    -- Let's fill in the AH prices
    currentSession["profitTotal"] = 0
    for itemId, itemCount in pairs(items) do
        -- item IDs are stored in [itemId] format in the current session
        local cleanedItemId = getCleanedItemId(itemId)
        local itemPrice = AH_PRICES[tonumber(cleanedItemId)]

        if itemPrice ~= nil and itemPrice.average ~= nil then
            itemPrice = itemPrice.average
        else
            itemPrice = 0
        end
        currentSession["profitTotal"] = currentSession["profitTotal"] + (itemPrice * itemCount)
    end
    -- TODO: Fill in loot session costs
    currentSession["endTimestamp"] = api.Time:GetLocalTime()
    currentSession["costTotal"] = "Unknown"

    -- Iterate through old sessions and change their item arrays to use [itemId] format
    for _, pastSession in ipairs(pastSessions.sessions) do
        local oldItems = pastSession.items
        local newItems = {}
        for oldItemId, itemCount in pairs(oldItems) do
            if string.sub(oldItemId, 1, 1) == "[" and string.sub(oldItemId, -1) == "]" then
                newItems[oldItemId] = itemCount
            else
                newItems["[" .. oldItemId .. "]"] = itemCount
            end
        end
        pastSession.items = newItems
    end
    -- Insert it into the top position (to sort by most recent)
    table.insert(pastSessions["sessions"], 1, currentSession)

    while #pastSessions.sessions > MAX_SESSIONS do
        table.remove(pastSessions.sessions)
    end
    api.File:Write(pastSessionsFilename, pastSessions)

    refreshSessionList(1)
end

local function endLootTrackerSession()
    if currentSession == nil then return end
    api.Log:Info("[Loot Tracker] Ending loot tracker session")
    saveCurrentSessionToFile()
    currentSession = nil
    lootTrackerSessionTimer = 0
    EluTrackerSettings.activeLootSession = {}
    SaveEluTrackerSettings()
end

local function startLootTrackerSession()
    api.Log:Info("[Loot Tracker] Starting loot tracker session")
    local sessionToStart = {}
    sessionToStart["localTimestamp"] = api.Time:GetLocalTime()
    sessionToStart["zone"] = currentZone
    sessionToStart["kills"] = 0
    sessionToStart["laborSpent"] = 0
    sessionToStart["profitTotal"] = 0
    sessionToStart["costTotal"] = 0
    sessionToStart["items"] = {}

    -- Before overwriting the old session, if it isn't null, then let's save it.
    endLootTrackerSession()

    currentSession = sessionToStart
    -- New running segment starts right now -- see the comment on
    -- sessionSegmentStartMs near the top of this file.
    sessionSegmentStartMs = api.Time:GetUiMsec()
end

local function addItemToSession(itemId, itemCount)
    if currentSession == nil or sessionPaused then return end
    local cleanItemId = itemId
    itemId = "[" .. itemId .. "]"
    if currentSession["items"][itemId] == nil then
        currentSession["items"][itemId] = itemCount
    else
        currentSession["items"][itemId] = currentSession["items"][itemId] + itemCount
    end

    -- Add to the display for total profit
    local itemPrice = AH_PRICES[tonumber(cleanItemId)]
    if itemPrice ~= nil then
        itemPrice = itemPrice.average
    else
        itemPrice = 0
    end
    currentSession["profitTotal"] = currentSession["profitTotal"] + (itemPrice * itemCount)
end

local function laborPointsChanged(diff, laborPoints)
    -- If labor is spent, start the labor used timer for accurate kill tracking
    if diff < 0 then
        laborUsedTimer = 0
        laborUsed = true
    end

    if diff < 0 and currentSession ~= nil then
        currentSession["laborSpent"] = currentSession["laborSpent"] + (diff*-1)
    end
end

local function trackKill(unitId, expAmount, expString)
    local playerId = api.Unit:GetUnitId("player")
    if playerId == unitId and laborUsed == false then
        if currentSession ~= nil then
            currentSession["kills"] = currentSession["kills"] + 1
        end
    end
end

local function itemIdFromItemLinkText(itemLinkText)
    local itemIdStr = string.sub(itemLinkText, 3)
    itemIdStr = split(itemIdStr, ",")
    itemIdStr = itemIdStr[1]
    return itemIdStr
end

local function removedItem(itemLinkText, itemCount, removeState, itemTaskType, tradeOtherName)
    -- Nothing tracked on removal today -- kept as a hook point (mirrors
    -- packs.lua's own REMOVED_ITEM handling) in case cost-tracking is added
    -- later.
end

local function lootedItem(itemLinkText, itemCount, itemTaskType, tradeOtherName)
    local itemId = itemIdFromItemLinkText(itemLinkText)
    -- Bug fix: the original condition here was
    --   itemTaskType == ITEM_TASK_ID_LOOTED_FROM_MONSTER or itemTaskType == ITEM_TASK_ID_FARMED or ITEM_TASK_ID_DAWNSDROP_PICKAXE
    -- -- missing "itemTaskType ==" on the third check meant it compared a
    -- non-zero constant (41) against nothing, which is always truthy in
    -- Lua. That made the whole condition unconditionally true, so every
    -- single item event (mail, crafting, pack turn-ins, potions used,
    -- everything) was being counted as loot and inflating profit/hr. Fixed
    -- to actually check the task type.
    if itemTaskType == ITEM_TASK_ID_LOOTED_FROM_MONSTER
        or itemTaskType == ITEM_TASK_ID_FARMED
        or itemTaskType == ITEM_TASK_ID_DAWNSDROP_PICKAXE then
        addItemToSession(itemId, itemCount)
    end
end

local function fillInAHPricesForCrates()
    local CRATE_IDS = {
        42074, -- Noble's Crate
        42075, -- Jester's Crate
        42076, -- Prince's Crate
        42077, -- Queen's Crate
        43177, -- Ancestral Crate
    }
    for _, crateId in ipairs(CRATE_IDS) do
        -- Jester's and Noble's
        local sunDustId = 16347
        local moonDustId = 16348
        local starDustId = 16349
        -- Prince's, Queen's and Ancestrals
        local mgpId = 23653 --> Mysterious Garden Powder

        local sunDustPrice = (AH_PRICES[sunDustId] and AH_PRICES[sunDustId].average) or 0
        local moonDustPrice = (AH_PRICES[moonDustId] and AH_PRICES[moonDustId].average) or 0
        local starDustPrice = (AH_PRICES[starDustId] and AH_PRICES[starDustId].average) or 0
        local mgpPrice = (AH_PRICES[mgpId] and AH_PRICES[mgpId].average) or 0

        local brazierPrice = 0.5
        local treePrice = 0.5

        if crateId == 42074 then
            -- Nobles
            AH_PRICES[crateId] = { average = (sunDustPrice * 1.8) + (moonDustPrice * 1.8) + (starDustPrice * 0.9) + (mgpPrice * 0.18) }
        elseif crateId == 42075 then
            -- Jesters
            AH_PRICES[crateId] = { average = (sunDustPrice * 2.2) + (moonDustPrice * 2.2) + (starDustPrice * 1.1) + (mgpPrice * 0.20) }
        elseif crateId == 42076 then
            -- Princes
            AH_PRICES[crateId] = { average = (brazierPrice * 1) + (treePrice * 1) + (mgpPrice * 0.2) }
        elseif crateId == 42077 then
            -- Queens
            AH_PRICES[crateId] = { average = (brazierPrice * 2.25) + (treePrice * 2.25) + (mgpPrice * 0.25) }
        elseif crateId == 43177 then
            -- Ancestrals
            AH_PRICES[crateId] = { average = (brazierPrice * 5) + (treePrice * 5) + (mgpPrice * 0.8) }
        end
    end
end

local function fillInRegradeBrazierPrices()
    local REGRADE_BRAZIER_LOOT_IDS = {
        ["Starpoint Fragment"] = 31085,
        ["Starpoint"] = 31929,
        ["Moonpoint Fragment"] = 28304,
        ["Moonpoint"] = 28302,
        ["Sunpoint Fragment"] = 28303,
        ["Sunpoint"] = 28301,
        ["Lucky Starpoint Shard"] = 39816,
        ["Lucky Starpoint"] = 31930,
        ["Lucky Moonpoint Shard"] = 39815,
        ["Lucky Moonpoint"] = 28308,
        ["Lucky Sunpoint Shard"] = 39814,
        ["Lucky Sunpoint"] = 28300,
    }

    -- Basic Regrade Point Fragments
    local sunpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint"]].average) or 0
    local moonpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint"]].average) or 0
    local starpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint"]].average) or 0
    if sunpointPrice ~= nil then
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]] = { average = sunpointPrice / 10 }
    end
    if moonpointPrice ~= nil then
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]] = { average = moonpointPrice / 10 }
    end
    if starpointPrice ~= nil then
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]] = { average = starpointPrice / 10 }
    end
    -- Lucky Regrade Point Shards
    local luckySunpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint"]].average) or 0
    local luckyMoonpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint"]].average) or 0
    local luckyStarpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint"]].average) or 0
    if luckySunpointPrice ~= nil then
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]] = { average = luckySunpointPrice / 3 }
    end
    if luckyMoonpointPrice ~= nil then
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]] = { average = luckyMoonpointPrice / 3 }
    end
    if luckyStarpointPrice ~= nil then
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]] = { average = luckyStarpointPrice / 3 }
    end
end

local function fillInPureOrePrices()
    local PURE_ORE_CONVERSION_MULTIPLIER = 9
    local PURE_ORE_IDS = {
        ["Pure Iron Ore"] = 8081,
        ["Pure Copper Ore"] = 8067,
        ["Pure Silver Ore"] = 8085,
        ["Pure Gold Ore"] = 8086,
        ["Pure Archeum Ore"] = 17715,
    }

    local ironPrice = ((AH_PRICES[8022] and AH_PRICES[8022].average) or 0) * PURE_ORE_CONVERSION_MULTIPLIER -- Iron Ore
    local copperPrice = ((AH_PRICES[3411] and AH_PRICES[3411].average) or 0) * PURE_ORE_CONVERSION_MULTIPLIER -- Copper Ore
    local silverPrice = ((AH_PRICES[8023] and AH_PRICES[8023].average) or 0) * PURE_ORE_CONVERSION_MULTIPLIER -- Silver Ore
    local goldPrice = ((AH_PRICES[8027] and AH_PRICES[8027].average) or 0) * PURE_ORE_CONVERSION_MULTIPLIER -- Gold Ore
    local archeumPrice = ((AH_PRICES[1386] and AH_PRICES[1386].average) or 0) * PURE_ORE_CONVERSION_MULTIPLIER -- Archeum Ore

    AH_PRICES[PURE_ORE_IDS["Pure Iron Ore"]] = { average = ironPrice }
    AH_PRICES[PURE_ORE_IDS["Pure Copper Ore"]] = { average = copperPrice }
    AH_PRICES[PURE_ORE_IDS["Pure Silver Ore"]] = { average = silverPrice }
    AH_PRICES[PURE_ORE_IDS["Pure Gold Ore"]] = { average = goldPrice }
    AH_PRICES[PURE_ORE_IDS["Pure Archeum Ore"]] = { average = archeumPrice }
end

--- Loot Session Details Window (built once, reused -- see the comment on
--- lootSessionDetailsWindow above)
local function BuildLootSessionDetailsWindow()
    if lootSessionDetailsWindow then return end

    lootSessionDetailsWindow = api.Interface:CreateWindow("lootSessionDetailsWindow", "Loot Session", 0, 0)
    lootSessionDetailsWindow:SetExtent(430, 450)
    lootSessionDetailsWindow:AddAnchor("CENTER", "UIParent", 0, 0)
    lootSessionDetailsWindow:Show(false)
    pcall(function() lootSessionDetailsWindow:SetCloseOnEscape(true) end)

    -- Match the rest of the addon's dark theme (the original popup used
    -- whatever the engine's default window skin is, which stood out next
    -- to every other window in this addon).
    if lootSessionDetailsWindow.titleBar and lootSessionDetailsWindow.titleBar.bg then
        lootSessionDetailsWindow.titleBar.bg:SetColor(ConvertColor(40), ConvertColor(44), ConvertColor(52), 1.0)
    end
    if lootSessionDetailsWindow.bg then
        lootSessionDetailsWindow.bg:SetColor(ConvertColor(24), ConvertColor(26), ConvertColor(31), 0.95)
    end

    -- Zone/date subtitle. The window's own chrome title is set once at
    -- creation and left alone from then on (there is no confirmed API to
    -- rename a window's title bar after creation -- every other cached
    -- popup window in this addon, e.g. main.lua's _fishingSettingsWnd,
    -- follows the same convention of a static chrome title). This label is
    -- what actually changes per-session.
    local lootSessionSubtitleLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionSubtitleLabel", 0, true)
    lootSessionSubtitleLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionSubtitleLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionSubtitleLabel, FONT_COLOR.TITLE)
    lootSessionSubtitleLabel:AddAnchor("TOPLEFT", lootSessionDetailsWindow, 10, 26)
    lootSessionSubtitleLabel:SetAutoResize(true)
    lootSessionDetailsWindow.lootSessionSubtitleLabel = lootSessionSubtitleLabel

    --- Session Summary Statistics
    local lootSessionProfitLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionProfitLabel", 0, true)
    lootSessionProfitLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionProfitLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionProfitLabel, FONT_COLOR.DEFAULT)
    lootSessionProfitLabel:AddAnchor("TOPLEFT", lootSessionDetailsWindow, 10, 50)
    lootSessionDetailsWindow.lootSessionProfitLabel = lootSessionProfitLabel

    local lootSessionDurationLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionDurationLabel", 0, true)
    lootSessionDurationLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionDurationLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionDurationLabel, FONT_COLOR.DEFAULT)
    lootSessionDurationLabel:AddAnchor("TOPLEFT", lootSessionDetailsWindow, 250, 50)
    lootSessionDetailsWindow.lootSessionDurationLabel = lootSessionDurationLabel

    local lootSessionKillsLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionKillsLabel", 0, true)
    lootSessionKillsLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionKillsLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionKillsLabel, FONT_COLOR.DEFAULT)
    lootSessionKillsLabel:AddAnchor("TOPLEFT", lootSessionProfitLabel, 0, 24)
    lootSessionDetailsWindow.lootSessionKillsLabel = lootSessionKillsLabel

    local lootSessionLaborLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionLaborLabel", 0, true)
    lootSessionLaborLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionLaborLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionLaborLabel, FONT_COLOR.DEFAULT)
    lootSessionLaborLabel:AddAnchor("TOPLEFT", lootSessionKillsLabel, 0, 0)
    lootSessionDetailsWindow.lootSessionLaborLabel = lootSessionLaborLabel

    local lootSessionPerKillLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionPerKillLabel", 0, true)
    lootSessionPerKillLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionPerKillLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionPerKillLabel, FONT_COLOR.DEFAULT)
    lootSessionPerKillLabel:AddAnchor("TOPLEFT", lootSessionDurationLabel, 0, 24)
    lootSessionDetailsWindow.lootSessionPerKillLabel = lootSessionPerKillLabel

    local lootSessionPerLaborLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionPerLaborLabel", 0, true)
    lootSessionPerLaborLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionPerLaborLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionPerLaborLabel, FONT_COLOR.DEFAULT)
    lootSessionPerLaborLabel:AddAnchor("TOPLEFT", lootSessionPerKillLabel, 0, 0)
    lootSessionDetailsWindow.lootSessionPerLaborLabel = lootSessionPerLaborLabel

    local lootSessionDeleteLabel = lootSessionDetailsWindow:CreateChildWidget("textbox", "lootSessionDeleteLabel", 0, true)
    lootSessionDeleteLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
    lootSessionDeleteLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionDeleteLabel, FONT_COLOR.RED)
    lootSessionDeleteLabel:AddAnchor("BOTTOMLEFT", lootSessionDetailsWindow, 10, -10)
    lootSessionDeleteLabel:SetText("Deleting a session will remove it permanently. \n This action cannot be undone.")
    lootSessionDeleteLabel:SetExtent(350, 24)

    local lootSessionDeleteBtn = lootSessionDetailsWindow:CreateChildWidget("button", "lootSessionDeleteBtn", 0, true)
    lootSessionDeleteBtn:SetText("Delete Session")
    lootSessionDeleteBtn:AddAnchor("BOTTOMRIGHT", lootSessionDetailsWindow, -20, -10)
    ApplyButtonSkin(lootSessionDeleteBtn, BUTTON_BASIC.DEFAULT)
    lootSessionDetailsWindow.lootSessionDeleteBtn = lootSessionDeleteBtn

    --- Session Details Items List (built once here; refilled per-open below)
    lootSessionItemsList = W_CTRL.CreateScrollListBox("lootSessionItemsList", lootSessionDetailsWindow, "TYPE2")
    lootSessionItemsList:AddAnchor("TOPLEFT", lootSessionDetailsWindow, 10, 100)
    lootSessionItemsList:AddAnchor("BOTTOMRIGHT", lootSessionDetailsWindow, -10, -60)
    lootSessionItemsList:SetExtent(400, 300)
end

--- Refreshes the (already-built, cached) session details window with a
--- specific session's data and shows it -- this used to rebuild the entire
--- window from scratch on every call.
local function drawLootSessionDetails(sessionIndex)
    local session = pastSessions["sessions"][sessionIndex]
    if session == nil then return end

    BuildLootSessionDetailsWindow()

    local zone = session.zone
    if zone == nil then zone = "Unknown" end
    local items = session.items
    local profitTotal = session.profitTotal
    local laborSpent = session.laborSpent
    local kills = session.kills
    local localTimestamp = session.localTimestamp
    local endTimestamp = session.endTimestamp
    local duration = differenceBetweenTimestamps(endTimestamp, localTimestamp)
    local durationStr = displayTimeString(duration)
    local date = safeTimeToDate(localTimestamp)
    local durationHours = duration / 3600
    local profitPerHour = safeDiv(profitTotal, durationHours)
    local killsPerHour = safeDiv(kills, durationHours)
    local laborPerHour = safeDiv(laborSpent, durationHours)
    local silverPerLabor = safeDiv(profitTotal * 100, laborSpent)
    local titleStr = zone .. " (" .. string.format("%02d/%02d/%04d", date.month, date.day, date.year) .. ")"

    lootSessionDetailsWindow.lootSessionSubtitleLabel:SetText(titleStr)
    lootSessionDetailsWindow.lootSessionProfitLabel:SetText("Profit: " .. string.format('%.0f', profitTotal) .. "g" .. " (" .. string.format('%.0f', profitPerHour) .. "g/hr)")
    lootSessionDetailsWindow.lootSessionDurationLabel:SetText("Duration: " .. durationStr)
    lootSessionDetailsWindow.lootSessionKillsLabel:SetText("Kills: " .. tostring(kills) .. " (" .. string.format('%.0f', killsPerHour) .. "/hr)")
    lootSessionDetailsWindow.lootSessionLaborLabel:SetText("Labor: " .. tostring(laborSpent) .. " (" .. string.format('%.0f', laborPerHour) .. "/hr)")
    lootSessionDetailsWindow.lootSessionPerKillLabel:SetText("Profit per Kill: " .. string.format('%.2f', safeDiv(profitTotal, kills)) .. "g")
    lootSessionDetailsWindow.lootSessionPerLaborLabel:SetText("Silver Per Labor: " .. string.format('%.2f', silverPerLabor) .. "s")

    -- Flip flop between labor and kills being displayed based on labor spent being higher than kills
    if laborSpent > kills then
        lootSessionDetailsWindow.lootSessionKillsLabel:Show(false)
        lootSessionDetailsWindow.lootSessionPerKillLabel:Show(false)
        lootSessionDetailsWindow.lootSessionPerLaborLabel:Show(true)
        lootSessionDetailsWindow.lootSessionLaborLabel:Show(true)
    else
        lootSessionDetailsWindow.lootSessionLaborLabel:Show(false)
        lootSessionDetailsWindow.lootSessionPerLaborLabel:Show(false)
        lootSessionDetailsWindow.lootSessionKillsLabel:Show(true)
        lootSessionDetailsWindow.lootSessionPerKillLabel:Show(true)
    end

    function lootSessionDetailsWindow.lootSessionDeleteBtn:OnClick()
        -- Remove the session from the past sessions
        table.remove(pastSessions["sessions"], sessionIndex)
        -- Iterate through old sessions and change their item arrays to use [itemId] format
        for _, pastSession in ipairs(pastSessions.sessions) do
            local oldItems = pastSession.items
            local newItems = {}
            for oldItemId, itemCount in pairs(oldItems) do
                if string.sub(oldItemId, 1, 1) == "[" and string.sub(oldItemId, -1) == "]" then
                    newItems[oldItemId] = itemCount
                else
                    newItems["[" .. oldItemId .. "]"] = itemCount
                end
            end
            pastSession.items = newItems
        end
        -- Finally, write it.
        api.File:Write(pastSessionsFilename, pastSessions)

        lootSessionDetailsWindow:Show(false)
        refreshSessionList(1)
    end
    lootSessionDetailsWindow.lootSessionDeleteBtn:SetHandler("OnClick", lootSessionDetailsWindow.lootSessionDeleteBtn.OnClick)

    -- Sort the list of items by its value, most valuable at the top
    local sortedItemsByAHPrice = {}
    if items then
        for itemId, itemCount in pairs(items) do
            local cleanedItemId = getCleanedItemId(itemId)
            local itemPrice = AH_PRICES[tonumber(cleanedItemId)]
            local totalValue = 0
            if itemPrice ~= nil then
                totalValue = itemCount * (itemPrice.average or 0)
            end
            table.insert(sortedItemsByAHPrice, {itemId = itemId, itemCount = itemCount, totalValue = totalValue})
        end
    end
    table.sort(sortedItemsByAHPrice, function(a, b)
        return a.totalValue > b.totalValue
    end)

    -- Clear whatever was shown for the previously-viewed session before
    -- appending this one's items. Wrapped in pcall: DeleteAllItems is the
    -- documented clear method for this simple list widget type, but if a
    -- future API revision renames/removes it, we'd rather show a stale
    -- (superset) list for one click than hard-error the whole popup.
    pcall(function() lootSessionItemsList:DeleteAllItems() end)
    for count, item in ipairs(sortedItemsByAHPrice) do
        local itemInfo = api.Item:GetItemInfoByType(tonumber(getCleanedItemId(item.itemId)))
        local itemName = itemInfo and itemInfo.name or ("Item " .. tostring(getCleanedItemId(item.itemId)))
        local displayStr = itemName .. " x" .. item.itemCount .. " (" .. string.format('%.0f', item.totalValue) .. "g)"
        lootSessionItemsList:AppendItem(displayStr, count)
    end

    lootSessionDetailsWindow:Show(true)
end

local function isLootWindowOpen()
    if eluDisplayWindow ~= nil and eluDisplayWindow:IsVisible() then
        return true
    end
    return false
end

-- See the comment on lootTrackerSessionTimer/sessionSegmentStartMs near the
-- top of this file -- this is the single source of truth for "how much
-- time has this session actually been running", used both for the overlay
-- display and for the per-hour math, so the two can never drift apart from
-- each other again.
local function GetLiveSessionElapsedMs()
    local elapsed = lootTrackerSessionTimer
    if currentSession ~= nil and sessionPaused ~= true then
        elapsed = elapsed + (api.Time:GetUiMsec() - sessionSegmentStartMs)
    end
    return elapsed
end

local function OnUpdate(dt)
    if isLootWindowOpen() then
        if displayRefreshCounter + dt > DISPLAY_REFRESH_MS then
            displayRefreshCounter = 0
            refreshSessionList(1)
        end
        displayRefreshCounter = displayRefreshCounter + dt
    else
        displayRefreshCounter = DISPLAY_REFRESH_MS
    end

    -- Labor used timer for excluding from kill count
    if laborUsedTimer + dt > LABOR_USED_TIMER_RATE then
        laborUsedTimer = 0
        laborUsed = false
    end
    laborUsedTimer = laborUsedTimer + dt

    if lootTrackerOverlay ~= nil and sessionClockRefreshTimer + dt > SESSION_CLOCK_REFRESH_RATE then
        sessionClockRefreshTimer = 0
        local liveElapsedMs = GetLiveSessionElapsedMs()
        lootTrackerOverlay.timerLabel:SetText(displayOverlayTimeString(liveElapsedMs / 1000))
        if currentSession ~= nil then
            local sessionSeconds = liveElapsedMs / 1000
            local profitPerHour = safeDiv(currentSession["profitTotal"], sessionSeconds) * 3600
            local killsPerHour = safeDiv(currentSession["kills"], sessionSeconds) * 3600
            local silverPerLabor = safeDiv(currentSession["profitTotal"] * 100, currentSession["laborSpent"])

            lootTrackerOverlay.profitLabel:SetText("Profit: " .. string.format('%.0f', currentSession["profitTotal"]) .. "g" .. " (" .. string.format('%.0f', profitPerHour) .. "g/hr)")
            lootTrackerOverlay.killsLabel:SetText("Kills: " .. tostring(currentSession["kills"]) .. " (" .. string.format('%.0f', killsPerHour) .. "/hr)")
            lootTrackerOverlay.laborLabel:SetText("Labor: " .. tostring(currentSession["laborSpent"]) .. " (" .. string.format('%.0f', silverPerLabor) .. "s/labor)")
        else
            lootTrackerOverlay.profitLabel:SetText("Profit: 0g")
            lootTrackerOverlay.killsLabel:SetText("Kills: 0")
            lootTrackerOverlay.laborLabel:SetText("Labor: 0")
        end

        if currentSession ~= nil and sessionPaused ~= true then
            -- Save the FULL live elapsed (banked time plus the current
            -- running segment), not just the banked lootTrackerSessionTimer
            -- -- otherwise a reload mid-segment would silently drop
            -- whatever time has elapsed since the segment started.
            currentSession.savedSessionTimer = liveElapsedMs
            EluTrackerSettings.activeLootSession = currentSession
            SaveEluTrackerSettings()
        end
    end
    sessionClockRefreshTimer = sessionClockRefreshTimer + dt
end

--- Session Scroll List Functions
local function SessionSetFunc(subItem, data, setValue)
    if not setValue then return end

    -- Data Assignments
    local sessionIndex = data.index
    local items = data.items
    local lootZone = data.zone
    local kills = data.kills
    local laborSpent = data.laborSpent or 0
    local profitTotal = data.profitTotal
    local date = safeTimeToDate(data.localTimestamp)
    local duration = differenceBetweenTimestamps(data.endTimestamp, data.localTimestamp)
    local durationStr = displayTimeString(duration)
    local durationHours = duration / 3600

    -- Display Strings
    local leftTextStr = ""
    if items then
        local highestCrateItemId, highestCrateItemCount = nil, 0
        for itemId, itemCount in pairs(items) do
            local cleanedItemId = getCleanedItemId(itemId)
            local itemInfo = api.Item:GetItemInfoByType(tonumber(cleanedItemId))
            if itemInfo and (string.find(string.lower(itemInfo.name), "crate") or string.find(string.lower(itemInfo.name), "research bundle")) and itemCount > highestCrateItemCount then
                highestCrateItemId = itemId
                highestCrateItemCount = itemCount
            end
        end

        if highestCrateItemId then
            local crateItemInfo = api.Item:GetItemInfoByType(tonumber(getCleanedItemId(highestCrateItemId)))
            local cratesPerHour = safeDiv(highestCrateItemCount, durationHours)
            leftTextStr = crateItemInfo.name .. " x" .. tostring(highestCrateItemCount) .. " (" .. string.format('%.0f', cratesPerHour) .. "/hr)"
        else
            leftTextStr = "No crates found"
        end

        local highestCoinpurseItemId, highestCoinpurseItemCount = nil, 0
        for itemId, itemCount in pairs(items) do
            local cleanedItemId = getCleanedItemId(itemId)
            local itemInfo = api.Item:GetItemInfoByType(tonumber(cleanedItemId))
            if itemInfo and string.find(string.lower(itemInfo.name), "coinpurse") and itemCount > highestCoinpurseItemCount then
                highestCoinpurseItemId = itemId
                highestCoinpurseItemCount = itemCount
            end
        end

        if highestCoinpurseItemId then
            local coinpurseItemInfo = api.Item:GetItemInfoByType(tonumber(getCleanedItemId(highestCoinpurseItemId)))
            local coinpursesPerHour = safeDiv(highestCoinpurseItemCount, durationHours)
            leftTextStr = leftTextStr .. "\n" .. coinpurseItemInfo.name .. " x" .. tostring(highestCoinpurseItemCount) .. " (" .. string.format('%.0f', coinpursesPerHour) .. "/hr)"
        else
            leftTextStr = leftTextStr .. "\nNo coinpurses found"
        end
    end

    local rightTextStr = "Profit: " .. tostring(profitTotal)
    if type(profitTotal) == "number" then
        rightTextStr = "Profit: " .. string.format('%.0f', profitTotal) .. "g" .. " (" .. string.format('%.0f', safeDiv(profitTotal, durationHours)) .. "g/hr)"
    end
    if kills > 0 then
        rightTextStr = rightTextStr .. " \n " .. "Kills: " .. tostring(kills) .. " (" .. string.format('%.0f', safeDiv(kills, durationHours)) .. "/hr)"
    else
        rightTextStr = rightTextStr .. " \n " .. "Labor Spent: " .. tostring(laborSpent) .. " (" .. string.format('%.0f', safeDiv(laborSpent, durationHours)) .. "/hr)"
    end

    if items then
        local highestItemId, highestItemCount = nil, 0
        for itemId, itemCount in pairs(items) do
            if itemCount > highestItemCount then
                highestItemId = itemId
                highestItemCount = itemCount
            end
        end
        if highestItemId == nil then
            F_SLOT.SetIconBackGround(subItem.subItemIcon, "game/ui/icon/icon_item_1338.dds")
        else
            local itemInfo = api.Item:GetItemInfoByType(tonumber(getCleanedItemId(highestItemId)))
            if itemInfo ~= nil then
                F_SLOT.SetIconBackGround(subItem.subItemIcon, itemInfo.path)
            end
        end
    end

    local titleStr = "Unknown Zone Loot Session"
    if kills > laborSpent then
        -- Larceny session, depicted by more kills than labor spent
        if lootZone ~= nil then
            titleStr = lootZone .. " Loot Session"
        end
        subItem.bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
    else
        -- Harvesting session
        if lootZone ~= nil then
            titleStr = lootZone .. " Harvesting Session"
        end
        subItem.bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
    end
    titleStr = titleStr .. " (".. durationStr .. ") "

    subItem.textboxLeft:SetText(leftTextStr)
    subItem.textboxRight:SetText(rightTextStr)
    subItem.sessionTitle:SetText(titleStr)
    subItem.sessionDateLabel:SetText(string.format("%02d/%02d/%04d", date.month, date.day, date.year))
    function subItem.clickOverlay:OnClick()
        drawLootSessionDetails(sessionIndex)
    end
    subItem.clickOverlay:SetHandler("OnClick", subItem.clickOverlay.OnClick)
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)
    if subItem.bg then return end
    subItem:SetExtent(580, 70)
    -- Background colouring
    local bg = subItem:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", subItem, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", subItem, 0, -4)
    bg:Show(true)
    subItem.bg = bg
    -- Top-left Session Title
    local sessionTitle = subItem:CreateChildWidget("label", "sessionTitle", 0, true)
    sessionTitle.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionTitle, FONT_COLOR.DEFAULT)
    sessionTitle:SetText("Unknown Loot Session")
    sessionTitle:AddAnchor("TOPLEFT", subItem, 10, 10)
    sessionTitle:SetAutoResize(true)
    sessionTitle.style:SetAlign(ALIGN.LEFT)
    -- Pack Item Icon
    local subItemIcon = CreateItemIconButton("subItemIcon", sessionTitle)
    subItemIcon:Show(true)
    F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    subItemIcon:AddAnchor("TOPLEFT", sessionTitle, 0, 10)
    subItem.subItemIcon = subItemIcon

    -- Top-right Session Date Label
    local sessionDateLabel = subItem:CreateChildWidget("label", "sessionDateLabel", 0, true)
    sessionDateLabel.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionDateLabel, FONT_COLOR.DEFAULT)
    sessionDateLabel:SetText("")
    sessionDateLabel:AddAnchor("TOPRIGHT", subItem, -12, 10)
    sessionDateLabel:SetAutoResize(true)
    sessionDateLabel.style:SetAlign(ALIGN.RIGHT)

    -- Left-side Text
    local textboxLeft = subItem:CreateChildWidget("textbox", "textboxLeft", 0, true)
    textboxLeft:AddAnchor("TOPLEFT", subItem, 55, 10)
    textboxLeft:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    textboxLeft.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(textboxLeft, FONT_COLOR.DEFAULT)
    subItem.textboxLeft = textboxLeft
    -- Right-side Text
    local textboxRight = subItem:CreateChildWidget("textbox", "textboxRight", 0, true)
    textboxRight:AddAnchor("TOPLEFT", subItem, 55, 10)
    textboxRight:AddAnchor("BOTTOMRIGHT", subItem, -12, 0)
    textboxRight.style:SetAlign(ALIGN.RIGHT)
    ApplyTextColor(textboxRight, FONT_COLOR.DEFAULT)
    subItem.textboxRight = textboxRight
    -- Interact Layer overtop of everything
    local clickOverlay = subItem:CreateChildWidget("button", "clickOverlay", 0, true)
    clickOverlay:AddAnchor("TOPLEFT", subItem, 0, 0)
    clickOverlay:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    subItem.clickOverlay = clickOverlay
end

--- Builds the "Loot Tracker" tab contents. Called at most once by main.lua's
--- CreateLootWindow (which itself guards against rebuilding on every tab
--- activation -- see main.lua). Only builds widgets; OnLoad fills in the
--- actual session data once it has loaded it from disk.
local function CreateUI(wndParent)
    local title = wndParent:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Loot Sessions")
    title:AddAnchor("TOP", wndParent, 0, 10)

    sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wndParent)
    sessionScrollList:Show(true)
    sessionScrollList:AddAnchor("TOPLEFT", wndParent, 4, 40)
    sessionScrollList:AddAnchor("BOTTOMRIGHT", wndParent, -4, -4)
    sessionScrollList:InsertColumn("", 600, 1, SessionSetFunc, nil, nil, SessionsColumnLayoutSetFunc)
    sessionScrollList:InsertRows(8, false)
    sessionScrollList.listCtrl:DisuseSorting()
    sessionScrollList.pageControl.maxPage = 1
    function sessionScrollList:OnPageChangedProc(pageIndex)
        sessionScrollList:DeleteAllDatas()
        sessionScrollList:ResetScroll(0)
        fillSessionTableData(sessionScrollList, pageIndex)
    end

    local toggleOverlayBtn = wndParent:CreateChildWidget("button", "toggleOverlayBtn", 0, true)
    toggleOverlayBtn:SetText("Toggle Overlay")
    toggleOverlayBtn:AddAnchor("BOTTOMRIGHT", wndParent, -10, 50)
    ApplyButtonSkin(toggleOverlayBtn, BUTTON_BASIC.DEFAULT)
    function toggleOverlayBtn:OnClick()
        if lootTrackerOverlay == nil then return end
        local nowVisible = not lootTrackerOverlay:IsVisible()
        lootTrackerOverlay:Show(nowVisible)
        EluTrackerSettings.lootOverlay = EluTrackerSettings.lootOverlay or {}
        EluTrackerSettings.lootOverlay.visible = nowVisible
        SaveEluTrackerSettings()
    end
    toggleOverlayBtn:SetHandler("OnClick", toggleOverlayBtn.OnClick)

    -- Now that the widgets exist, show whatever data has already been
    -- loaded (nothing yet on a first-ever load -- OnLoad calls this again
    -- once pastSessions has actually been read from disk).
    refreshSessionList(1)
end

--- Builds the small draggable HUD overlay (start/pause/end session, live
--- profit/kills/labor). Built once and reused; the toggle button in the
--- tab just shows/hides it rather than rebuilding it.
local function BuildLootTrackerOverlay()
    if lootTrackerOverlay ~= nil then return end

    local overlaySettings = EluTrackerSettings.lootOverlay or { x = 0, y = 0, visible = false }

    lootTrackerOverlay = api.Interface:CreateEmptyWindow("lootTrackerOverlay", "UIParent")
    -- Card stays at its original 220x80 -- only the two buttons themselves
    -- get smaller/tidier below (see the comment further down): one row
    -- instead of two stacked, and shrunk down, so they take up noticeably
    -- less of the card without changing the card's own size.
    lootTrackerOverlay:SetExtent(220, 80)
    if (overlaySettings.x or 0) == 0 and (overlaySettings.y or 0) == 0 then
        lootTrackerOverlay:AddAnchor("CENTER", "UIParent", 0, 0)
    else
        lootTrackerOverlay:AddAnchor("TOPLEFT", "UIParent", overlaySettings.x, overlaySettings.y)
    end
    lootTrackerOverlay:Show(overlaySettings.visible or false)
    lootTrackerOverlay:Clickable(false)

    local bg = lootTrackerOverlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(0),ConvertColor(0),ConvertColor(0),0.5)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", lootTrackerOverlay, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", lootTrackerOverlay, 0, 0)
    lootTrackerOverlay.bg = bg

    -- Timer clock icon and label
    local timerLabel = lootTrackerOverlay:CreateChildWidget("label", "timerLabel", 0, true)
    timerLabel.style:SetShadow(true)
    timerLabel.style:SetAlign(ALIGN.RIGHT)
    timerLabel:AddAnchor("TOPRIGHT", lootTrackerOverlay, "TOPRIGHT", -30, 15)
    timerLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
    timerLabel:SetText("00:00:00")
    lootTrackerOverlay.timerLabel = timerLabel

    local clockIcon = timerLabel:CreateChildWidget("label", "clockIcon", 0, true)
    clockIcon:AddAnchor("TOPLEFT", timerLabel, "TOPLEFT", -80, -14)
    local clockIconTexture = clockIcon:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
    clockIconTexture:SetTextureInfo("clock")
    clockIconTexture:AddAnchor("TOPLEFT", clockIcon, 0, 0)

    -- Profit, Labor and kill count labels
    local profitLabel = lootTrackerOverlay:CreateChildWidget("label", "profitLabel", 0, true)
    profitLabel.style:SetShadow(true)
    profitLabel.style:SetAlign(ALIGN.LEFT)
    profitLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 35)
    profitLabel.style:SetFontSize(FONT_SIZE.SMALL)
    profitLabel:SetText("Profit: 0g")
    lootTrackerOverlay.profitLabel = profitLabel

    local killsLabel = lootTrackerOverlay:CreateChildWidget("label", "killsLabel", 0, true)
    killsLabel.style:SetShadow(true)
    killsLabel.style:SetAlign(ALIGN.LEFT)
    killsLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 50)
    killsLabel.style:SetFontSize(FONT_SIZE.SMALL)
    killsLabel:SetText("Kills: 0")
    lootTrackerOverlay.killsLabel = killsLabel

    local laborLabel = lootTrackerOverlay:CreateChildWidget("label", "laborLabel", 0, true)
    laborLabel.style:SetShadow(true)
    laborLabel.style:SetAlign(ALIGN.LEFT)
    laborLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 65)
    laborLabel.style:SetFontSize(FONT_SIZE.SMALL)
    laborLabel:SetText("Labor: 0")
    lootTrackerOverlay.laborLabel = laborLabel

    local closeBtn = lootTrackerOverlay:CreateChildWidget("button", "closeBtn", 0, true)
    closeBtn:SetText("X")
    closeBtn:SetExtent(16, 16)
    closeBtn:AddAnchor("TOPRIGHT", lootTrackerOverlay, -5, 5)
    closeBtn.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(closeBtn, FONT_COLOR.RED)
    function closeBtn:OnClick()
        lootTrackerOverlay:Show(false)
        EluTrackerSettings.lootOverlay = EluTrackerSettings.lootOverlay or {}
        EluTrackerSettings.lootOverlay.visible = false
        SaveEluTrackerSettings()
    end
    closeBtn:SetHandler("OnClick", closeBtn.OnClick)

    -- Pause/Resume and End, stacked in the same narrow top-right control
    -- column the original buttons used -- back to stacked (not side by
    -- side) on request: side by side needed roughly double the width of a
    -- single button, which reached far enough left to cut into the
    -- Profit/Kills/Labor text next to it. A single narrower column reaches
    -- much less far left, so it clears that text -- and each button is a
    -- bit taller than the original 20px.
    local overlayBtnW = 54
    local overlayBtnH = 22
    local overlayBtnGapV = 3
    local overlayBtnX = -10
    local overlayBtnY = 30

    -- BUG FOUND (this is why Pause/End visually overlapped when they were
    -- briefly side by side): ApplyButtonSkin silently regrows a widget back
    -- toward its skin's own natural size -- the exact same gotcha already
    -- documented in elu_functions_tools.lua, which is why every
    -- *ButtonVisual function over there re-asserts :SetExtent() AFTER
    -- ApplyButtonSkin, not before. Keeping that ordering here too (skin
    -- first, size after) even though stacking gives more breathing room
    -- than the side-by-side layout did, so the same mistake can't quietly
    -- creep back in later.
    local startBtn = lootTrackerOverlay:CreateChildWidget("button", "startBtn", 0, true)
    startBtn:AddAnchor("TOPRIGHT", lootTrackerOverlay, overlayBtnX, overlayBtnY)
    ApplyButtonSkin(startBtn, BUTTON_BASIC.DEFAULT)
    startBtn:SetExtent(overlayBtnW, overlayBtnH)
    startBtn:SetText("Start")

    local saveBtn = lootTrackerOverlay:CreateChildWidget("button", "saveBtn", 0, true)
    saveBtn:AddAnchor("TOPRIGHT", lootTrackerOverlay, overlayBtnX, overlayBtnY + overlayBtnH + overlayBtnGapV)
    ApplyButtonSkin(saveBtn, BUTTON_BASIC.DEFAULT)
    saveBtn:SetExtent(overlayBtnW, overlayBtnH)
    saveBtn:SetText("End")
    -- Soft red tint on the label only (skin/background stay the same
    -- BUTTON_BASIC.DEFAULT as Start/Pause/Resume) -- just enough to read as
    -- the "ends the session" action without looking like a different,
    -- heavier button style bolted on next to it.
    ApplyTextColor(saveBtn, {1, 0.45, 0.45, 1})

    if currentSession ~= nil then
        saveBtn:Show(true)
        if sessionPaused then
            startBtn:SetText("Resume")
        else
            startBtn:SetText("Pause")
        end
    else
        saveBtn:Show(false)
        startBtn:SetText("Start")
    end

    function startBtn:OnClick()
        if currentSession == nil then
            startLootTrackerSession()
            startBtn:SetText("Pause")
            saveBtn:Show(true)
            sessionPaused = false
        elseif not sessionPaused then
            -- Pausing: bank the elapsed time from the segment that's ending
            -- into lootTrackerSessionTimer (see the comment on it near the
            -- top of this file) before flipping sessionPaused -- from this
            -- point on GetLiveSessionElapsedMs() stops adding any more time
            -- until Resume starts a new segment below.
            lootTrackerSessionTimer = lootTrackerSessionTimer + (api.Time:GetUiMsec() - sessionSegmentStartMs)
            sessionPaused = true
            startBtn:SetText("Resume")
        else
            -- Resuming: a new running segment starts right now.
            sessionSegmentStartMs = api.Time:GetUiMsec()
            sessionPaused = false
            startBtn:SetText("Pause")
        end
    end
    startBtn:SetHandler("OnClick", startBtn.OnClick)
    -- Same ApplyButtonSkin-then-SetExtent ordering as the creation above --
    -- ApplyButtonSkin on hover would otherwise regrow startBtn back to its
    -- natural size on every mouse-over, right back into saveBtn next to it.
    function startBtn:OnEnter()
        ApplyButtonSkin(startBtn, BUTTON_BASIC.DEFAULT)
        startBtn:SetExtent(overlayBtnW, overlayBtnH)
    end
    startBtn:SetHandler("OnEnter", startBtn.OnEnter)
    function startBtn:OnLeave()
        ApplyButtonSkin(startBtn, BUTTON_BASIC.DEFAULT)
        startBtn:SetExtent(overlayBtnW, overlayBtnH)
    end
    startBtn:SetHandler("OnLeave", startBtn.OnLeave)

    -- ApplyTextColor is a one-shot style override the engine doesn't
    -- reliably restore on mouse leave (same lesson already learned the hard
    -- way in elu_functions_tools.lua) -- re-assert it on every hover
    -- transition so End doesn't silently fade back to the default button
    -- color the first time someone mouses over it. ApplyTextColor doesn't
    -- touch the widget's size the way ApplyButtonSkin does, so no
    -- SetExtent needed here.
    function saveBtn:OnClick()
        endLootTrackerSession()
        startBtn:SetText("Start")
        saveBtn:Show(false)
        sessionPaused = false
    end
    saveBtn:SetHandler("OnClick", saveBtn.OnClick)
    function saveBtn:OnEnter() ApplyTextColor(saveBtn, {1, 0.45, 0.45, 1}) end
    saveBtn:SetHandler("OnEnter", saveBtn.OnEnter)
    function saveBtn:OnLeave() ApplyTextColor(saveBtn, {1, 0.45, 0.45, 1}) end
    saveBtn:SetHandler("OnLeave", saveBtn.OnLeave)

    --- Add dragable bar across top
    local moveWnd = lootTrackerOverlay:CreateChildWidget("label", "moveWnd", 0, true)
    moveWnd:AddAnchor("TOPLEFT", lootTrackerOverlay, 0, 0)
    moveWnd:AddAnchor("TOPRIGHT", lootTrackerOverlay, -25, 0)
    moveWnd:SetHeight(30)
    moveWnd.style:SetFontSize(FONT_SIZE.LARGE)
    moveWnd.style:SetAlign(ALIGN.LEFT)
    moveWnd:SetText("   Loot Tracker")
    ApplyTextColor(moveWnd, FONT_COLOR.WHITE)
    function moveWnd:OnDragStart()
        if api.Input:IsShiftKeyDown() then
            lootTrackerOverlay:StartMoving()
            api.Cursor:ClearCursor()
            api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
        end
    end
    moveWnd:SetHandler("OnDragStart", moveWnd.OnDragStart)
    function moveWnd:OnDragStop()
        lootTrackerOverlay:StopMovingOrSizing()
        api.Cursor:ClearCursor()
        local currentX, currentY = lootTrackerOverlay:GetOffset()
        EluTrackerSettings.lootOverlay = EluTrackerSettings.lootOverlay or {}
        EluTrackerSettings.lootOverlay.x = currentX
        EluTrackerSettings.lootOverlay.y = currentY
        SaveEluTrackerSettings()
    end
    moveWnd:SetHandler("OnDragStop", moveWnd.OnDragStop)
    moveWnd:EnableDrag(true)
end

local function OnLoad()
    pastSessionsFilename = "elu_tracker_loot_sessions.lua"
    AH_PRICES = require("Elu_Tracker/data/auction_house_prices")
    sessionPaused = false

    -- Fill in AH prices for noble's, jester's, prince's, queen's and ancestral crates
    fillInAHPricesForCrates()
    -- Fill in regrade brazier loot prices
    fillInRegradeBrazierPrices()
    -- Fill in pure ore prices
    fillInPureOrePrices()

    -- Load previous sessions, or make empty file.
    pastSessions = api.File:Read(pastSessionsFilename)
    if pastSessions ~= nil then
        if pastSessions.sessions ~= nil then
            maxPage = math.ceil(#pastSessions.sessions / pageSize)
        else
            maxPage = 1
        end
    else
        pastSessions = {}
        pastSessions["sessions"] = {}
        api.File:Write(pastSessionsFilename, pastSessions)
        maxPage = 1
    end
    if maxPage == 0 then maxPage = 1 end

    local activeSession = EluTrackerSettings.activeLootSession
    if type(activeSession) == "table" and activeSession.localTimestamp ~= nil then
        currentSession = activeSession
        lootTrackerSessionTimer = activeSession.savedSessionTimer or 0
    else
        currentSession = nil
        lootTrackerSessionTimer = 0
    end
    -- sessionPaused is always forced to false a few lines up regardless of
    -- what was restored, so whether this is a genuinely resumed session or
    -- a fresh one, a running segment effectively begins right now.
    sessionSegmentStartMs = api.Time:GetUiMsec()

    -- Initialize the addon-wide loot event window
    eluLootEventWindow = api.Interface:CreateEmptyWindow("eluLootEventWindow", "UIParent")
    eluLootEventWindow:Show(true)
    function eluLootEventWindow:OnEvent(event, ...)
        if event == "REMOVED_ITEM" then
            removedItem(unpack(arg))
        end
        if event == "ADDED_ITEM" then
            lootedItem(unpack(arg))
        end
        if event == "LABORPOWER_CHANGED" then
            laborPointsChanged(unpack(arg))
        end
        if event == "EXP_CHANGED" then
            trackKill(unpack(arg))
        end
        if event == "CHAT_JOINED_CHANNEL" then
            updateLastKnownChannel(unpack(arg))
        end
    end
    eluLootEventWindow:SetHandler("OnEvent", eluLootEventWindow.OnEvent)
    eluLootEventWindow:RegisterEvent("ADDED_ITEM")
    eluLootEventWindow:RegisterEvent("REMOVED_ITEM")
    eluLootEventWindow:RegisterEvent("LABORPOWER_CHANGED")
    eluLootEventWindow:RegisterEvent("EXP_CHANGED")
    eluLootEventWindow:RegisterEvent("CHAT_JOINED_CHANNEL")

    -- Now that data is loaded, refresh the tab's session list (CreateUI may
    -- have already run once with no data, if this is the very first build).
    refreshSessionList(1)

    -- Initialize Loot Tracker overlay (eager: this is this tab's core
    -- feature, not an optional extra, so it's built up front like the
    -- original -- but now properly freed on unload, see OnUnload below).
    BuildLootTrackerOverlay()

    -- Note: deliberately NOT calling api.On("UPDATE", OnUpdate) here.
    -- main.lua is the single owner of the UPDATE event and calls
    -- lootTrackerAddon.OnUpdate(dt) itself once per tick alongside every
    -- other module (see main.lua's own OnUpdate) -- exactly like
    -- packs.lua/fish_tracker.lua do. Registering our own UPDATE handler
    -- here would silently replace main.lua's, breaking every other
    -- tracker's OnUpdate (the same class of bug main.lua's OnChatMessage
    -- comment warns about for CHAT_MESSAGE).
    SaveEluTrackerSettings()
end

local function OnUnload()
    if eluLootEventWindow then
        eluLootEventWindow:Show(false)
        pcall(function() api.Interface:Free(eluLootEventWindow) end)
        eluLootEventWindow = nil
    end
    if lootTrackerOverlay then
        lootTrackerOverlay:Show(false)
        pcall(function() api.Interface:Free(lootTrackerOverlay) end)
        lootTrackerOverlay = nil
    end
    if lootSessionDetailsWindow then
        lootSessionDetailsWindow:Show(false)
        pcall(function() api.Interface:Free(lootSessionDetailsWindow) end)
        lootSessionDetailsWindow = nil
    end
    lootSessionItemsList = nil
    sessionScrollList = nil
end

elu_loot_tracker_addon.CreateUI = CreateUI
elu_loot_tracker_addon.OnLoad = OnLoad
elu_loot_tracker_addon.OnUnload = OnUnload
elu_loot_tracker_addon.OnUpdate = OnUpdate

return elu_loot_tracker_addon
