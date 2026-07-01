local your_loot_addon = {
	name = "Packs",
	author = "Michaelqt",
	version = "",
	desc = ""
}

local itemTaskTypes = {}
local ITEM_TASK_ID_FARMED = 9
local ITEM_TASK_ID_LOOTED_FROM_MONSTER = 10
local ITEM_TASK_ID_PACK_IN_VEHICLE = 16
local ITEM_TASK_ID_PICKED_PACK_UP = 23
local ITEM_TASK_ID_PACK_WAS_CRAFTED = 27
local ITEM_TASK_ID_CONSUMABLE_USED = 39
local ITEM_TASK_ID_DAWNSDROP_PICKAXE = 41
local ITEM_TASK_ID_MAIL_SEND_OR_RECEIVE = 46
local ITEM_TASK_ID_PACK_DROPPED = 61
local ITEM_TASK_ID_PACK_TURNED_IN = 109

local AH_PRICES

local eluTrackerEventWindow 
local lootWindow

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
local lootTrackerSessionTimer = 0
local sessionPaused

local displayRefreshCounter = 0
local DISPLAY_REFRESH_MS = 60000

local initializeLootWindowPos = false

local pageSize = 20 
local maxPage

function split(s, sep)
    local fields = {}
    
    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    
    return fields
end
local function ConvertColor(color)
    return color / 255
end 
local function differenceBetweenTimestamps(time1, time2)
    local time1Prefix = string.sub(time1, 1, 2)
    local time1Suffix = string.sub(time1, (#time1 - 2) * -1)

    local time2Prefix = string.sub(time2, 1, 2) 
    local time2Suffix = string.sub(time2, (#time2 - 2) * -1)
    local timeDiff = tonumber(time1Suffix) - tonumber(time2Suffix)
    return timeDiff
end 
local function displayTimeString(timeInSeconds)
    timeInMs = tonumber(timeInSeconds)
    local seconds = math.floor(timeInSeconds) % 60
    local minutes = math.floor(timeInSeconds / (1*60)) % 60  
    local hours = math.floor(timeInSeconds / (1*60*60)) % 24
    
    return string.format("%02dh %02dm", hours, minutes)
end

local function displayOverlayTimeString(timeInSeconds)
    timeInMs = tonumber(timeInSeconds)
    local seconds = math.floor(timeInSeconds) % 60
    local minutes = math.floor(timeInSeconds / (1*60)) % 60  
    local hours = math.floor(timeInSeconds / (1*60*60)) % 24
    
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function updateLastKnownChannel(channelId, channelName)
    local targetChannelId = 1
    if channelId ~= 1 then 
      return 
    end 
    if currentZone ~= nil then 
      lastKnownZone = currentZone
    end 
    currentZone = channelName
end 

local function getCleanedItemId(itemId)
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
    endingIndex = startingIndex + pageSize
    itemScrollList:DeleteAllDatas()

    if pastSessions == nil then return end
    
    local count = 1
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        if count >= startingIndex and count < endingIndex then 
            local itemData = {
                localTimestamp = sessionObject.localTimestamp,
                endTimestamp = sessionObject.endTimestamp,
                items = sessionObject.items,
                profitTotal = sessionObject.profitTotal,
                laborSpent = sessionObject.laborSpent,
                costTotal = sessionObject.costTotal,
                kills = sessionObject.kills, 
                zone = sessionObject.zone,
                index = count,

                isViewData = true, 
                isAbstention = false
            }
            itemScrollList:InsertData(count, 1, itemData)
        end
        count = count + 1
    end 
end

local function saveCurrentSessionToFile()
    if pastSessions == nil then 
        pastSessions = {}
        pastSessions["sessions"] = {}
    end 

    local items = currentSession["items"]
    currentSession["profitTotal"] = 0
    for itemId, itemCount in pairs(items) do 
        local cleanedItemId = getCleanedItemId(itemId)
        local itemPrice = AH_PRICES[tonumber(cleanedItemId)]
        
        if itemPrice ~= nil then
            if itemPrice.average ~= nil then 
                itemPrice = itemPrice.average
            else 
                itemPrice = 0
            end
        else 
            itemPrice = 0
        end
        currentSession["profitTotal"] = currentSession["profitTotal"] + (itemPrice * itemCount)
    end
    currentSession["endTimestamp"] = api.Time:GetLocalTime()
    currentSession["costTotal"] = "Unknown"

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
    table.insert(pastSessions["sessions"], 1, currentSession)
    api.File:Write(pastSessionsFilename, pastSessions)

    local sessionScrollList = lootWindow.sessionScrollList
    if pastSessions ~= nil then
        if pastSessions.sessions ~= nil then
            maxPage = math.ceil(#pastSessions.sessions / pageSize)    
        else
            maxPage = 1
        end   
    else
        maxPage = 1
    end 
    sessionScrollList.pageControl.maxPage = maxPage
    fillSessionTableData(sessionScrollList, 1)
    sessionScrollList.pageControl:SetCurrentPage(1, true)
end 

local function endLootTrackerSession()
    if currentSession == nil then return end 
    api.Log:Info("[Elu Tracker] Ending loot tracker session")
    saveCurrentSessionToFile()
    currentSession = nil
    lootTrackerSessionTimer = 0
end

local function startLootTrackerSession()
    api.Log:Info("[Elu Tracker] Starting loot tracker session")
    local sessionToStart = {}
    sessionToStart["localTimestamp"] = api.Time:GetLocalTime()
    sessionToStart["zone"] = currentZone
    sessionToStart["kills"] = 0
    sessionToStart["laborSpent"] = 0
    sessionToStart["profitTotal"] = 0
    sessionToStart["costTotal"] = 0
    sessionToStart["items"] = {}
    endLootTrackerSession()

    currentSession = sessionToStart
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

    local itemPrice = AH_PRICES[tonumber(cleanItemId)]
    if itemPrice ~= nil then
        itemPrice = itemPrice.average
    else 
        itemPrice = 0
    end
    currentSession["profitTotal"] = currentSession["profitTotal"] + (itemPrice * itemCount)
end

local function laborPointsChanged(diff, laborPoints)
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
    local removedItemId = itemIdFromItemLinkText(itemLinkText)
    local itemInfo = api.Item:GetItemInfoByType(tonumber(removedItemId))
end
  
local function lootedItem(itemLinkText, itemCount, itemTaskType, tradeOtherName)
    local itemId = itemIdFromItemLinkText(itemLinkText)
    if itemTaskType == ITEM_TASK_ID_LOOTED_FROM_MONSTER or itemTaskType == ITEM_TASK_ID_FARMED or ITEM_TASK_ID_DAWNSDROP_PICKAXE then 
        addItemToSession(itemId, itemCount)
    end

    local itemInfo = api.Item:GetItemInfoByType(tonumber(itemId))
end 

local function fillInAHPricesForCrates()
    local CRATE_IDS = {
        42074,
        42075, 
        42076, 
        42077, 
        43177, 
    }
    for _, crateId in ipairs(CRATE_IDS) do 
        local itemInfo = api.Item:GetItemInfoByType(crateId)
        local sunDustId = 16347
        local moonDustId = 16348
        local starDustId = 16349
        local brazierId = 15983
        local treeId = 35301
        local mgpId = 23653 

        local sunDustPrice = (AH_PRICES[sunDustId] and AH_PRICES[sunDustId].average) or 0
        local moonDustPrice = (AH_PRICES[moonDustId] and AH_PRICES[moonDustId].average) or 0
        local starDustPrice = (AH_PRICES[starDustId] and AH_PRICES[starDustId].average) or 0
        local mgpPrice = (AH_PRICES[mgpId] and AH_PRICES[mgpId].average) or 0

        local brazierPrice = 0.5
        local treePrice = 0.5
        
        if crateId == 42074 then 
            local cratePrice = (sunDustPrice * 1.8) + (moonDustPrice * 1.8) + (starDustPrice * 0.9) + (mgpPrice * 0.18)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        elseif crateId == 42075 then 
            local cratePrice = (sunDustPrice * 2.2) + (moonDustPrice * 2.2) + (starDustPrice * 1.1) + (mgpPrice * 0.20)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        elseif crateId == 42076 then
            local cratePrice = (brazierPrice * 1) + (treePrice * 1) + (mgpPrice * 0.2)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        elseif crateId == 42077 then
            local cratePrice = (brazierPrice * 2.25) + (treePrice * 2.25) + (mgpPrice * 0.25)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        elseif crateId == 43177 then
            local cratePrice = (brazierPrice * 5) + (treePrice * 5) + (mgpPrice * 0.8)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        end 
    end
end 

local function fillInRegradeBrazierPrices()
    local REGRADE_BRAZIER_LOOT_IDS = {}
    REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"] = 31085
    REGRADE_BRAZIER_LOOT_IDS["Starpoint"] = 31929
    REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"] = 28304
    REGRADE_BRAZIER_LOOT_IDS["Moonpoint"] = 28302
    REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"] = 28303
    REGRADE_BRAZIER_LOOT_IDS["Sunpoint"] = 28301
    REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"] = 39816
    REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint"] = 31930
    REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"] = 39815
    REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint"] = 28308
    REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"] = 39814
    REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint"] = 28300

    local sunFragmentPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]].average) or 0
    local sunpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint"]].average) or 0
    local moonFragmentPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]].average) or 0
    local moonpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint"]].average) or 0
    local starFragmentPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]].average) or 0
    local starpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint"]].average) or 0
    if sunpointPrice ~= nil then 
        sunFragmentPrice = sunpointPrice / 10
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]].average = sunFragmentPrice
    end
    if moonpointPrice ~= nil then 
        moonFragmentPrice = moonpointPrice / 10
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]].average = moonFragmentPrice
    end
    if starpointPrice ~= nil then 
        starFragmentPrice = starpointPrice / 10
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]].average = starFragmentPrice
    end
    local luckySunShardPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]].average) or 0
    local luckySunpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint"]].average) or 0
    local luckyMoonShardPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]].average) or 0
    local luckyMoonpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint"]].average) or 0
    local luckyStarShardPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]].average) or 0
    local luckyStarpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint"]].average) or 0
    if luckySunpointPrice ~= nil then 
        luckySunShardPrice = luckySunpointPrice / 3
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]].average = luckySunShardPrice
    end
    if luckyMoonpointPrice ~= nil then 
        luckyMoonShardPrice = luckyMoonpointPrice / 3
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]].average = luckyMoonShardPrice
    end
    if luckyStarpointPrice ~= nil then 
        luckyStarShardPrice = luckyStarpointPrice / 3
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]].average = luckyStarShardPrice
    end
end 

local function fillInArcheumTreePrices()

end

local function fillInPureOrePrices()
    local PURE_ORE_CONVERSION_MULTIPLIER = 9
    local PURE_ORE_IDS = {}
    PURE_ORE_IDS["Pure Iron Ore"] = 8081
    PURE_ORE_IDS["Pure Copper Ore"] = 8067
    PURE_ORE_IDS["Pure Silver Ore"] = 8085
    PURE_ORE_IDS["Pure Gold Ore"] = 8086
    PURE_ORE_IDS["Pure Archeum Ore"] = 17715

    local ironPrice = (AH_PRICES[8022] and AH_PRICES[8022].average) or 0 
    local copperPrice = (AH_PRICES[3411] and AH_PRICES[3411].average) or 0 
    local silverPrice = (AH_PRICES[8023] and AH_PRICES[8023].average) or 0 
    local goldPrice = (AH_PRICES[8027] and AH_PRICES[8027].average) or 0 
    local archeumPrice = (AH_PRICES[1386] and AH_PRICES[1386].average) or 0 
    ironPrice = ironPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Iron Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Iron Ore"]].average = ironPrice
    copperPrice = copperPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Copper Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Copper Ore"]].average = copperPrice
    silverPrice = silverPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Silver Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Silver Ore"]].average = silverPrice
    goldPrice = goldPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Gold Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Gold Ore"]].average = goldPrice
    archeumPrice = archeumPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Archeum Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Archeum Ore"]].average = archeumPrice
end 

local lootSessionDetailsWindow = nil

local function drawLootSessionDetails(sessionIndex)
    local session = pastSessions["sessions"][sessionIndex]
    if session == nil then return end 
    local zone = session.zone
    if zone == nil then zone = "Unknown" end
    local items = session.items
    local profitTotal = session.profitTotal
    local laborSpent = session.laborSpent
    local costTotal = session.costTotal
    local kills = session.kills
    local localTimestamp = session.localTimestamp
    local endTimestamp = session.endTimestamp
    local duration = differenceBetweenTimestamps(endTimestamp, localTimestamp)
    local durationStr = displayTimeString(duration)
    local date = api.Time:TimeToDate(localTimestamp)
    local profitPerHour = profitTotal / (duration / 3600)
    local killsPerHour = kills / (duration / 3600)
    local laborPerHour = laborSpent / (duration / 3600)
    local silverPerLabor = profitTotal * 100 / laborSpent
    local titleStr = zone .. " (" .. string.format("%02d/%02d/%04d", date.month, date.day, date.year) .. ")"

    if lootSessionDetailsWindow then
        lootSessionDetailsWindow:Show(false)
        api.Interface:Free(lootSessionDetailsWindow)
        lootSessionDetailsWindow = nil
    end

    lootSessionDetailsWindow = api.Interface:CreateWindow("lootSessionDetailsWindow", titleStr)
    lootSessionDetailsWindow:SetExtent(430, 450)
    lootSessionDetailsWindow:AddAnchor("CENTER", "UIParent", 0, 0)
    lootSessionDetailsWindow:Show(true)
    local lootSessionProfitLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionProfitLabel", 0, true)
    lootSessionProfitLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionProfitLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionProfitLabel, FONT_COLOR.DEFAULT)
    lootSessionProfitLabel:AddAnchor("TOPLEFT", lootSessionDetailsWindow, 10, 50)
    lootSessionProfitLabel:SetText("Profit: " .. string.format('%.0f', profitTotal) .. "g" .. " (" .. string.format('%.0f', profitPerHour) .. "g/hr)")
    local lootSessionDurationLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionDurationLabel", 0, true)
    lootSessionDurationLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionDurationLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionDurationLabel, FONT_COLOR.DEFAULT)
    lootSessionDurationLabel:AddAnchor("TOPLEFT", lootSessionDetailsWindow, 250, 50)
    lootSessionDurationLabel:SetText("Duration: " .. durationStr)

    local lootSessionKillsLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionKillsLabel", 0, true)
    lootSessionKillsLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionKillsLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionKillsLabel, FONT_COLOR.DEFAULT)
    lootSessionKillsLabel:AddAnchor("TOPLEFT", lootSessionProfitLabel, 0, 24)
    lootSessionKillsLabel:SetText("Kills: " .. tostring(kills) .. " (" .. string.format('%.0f', killsPerHour) .. "/hr)")

    local lootSessionLaborLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionLaborLabel", 0, true)
    lootSessionLaborLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionLaborLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionLaborLabel, FONT_COLOR.DEFAULT)
    lootSessionLaborLabel:AddAnchor("TOPLEFT", lootSessionKillsLabel, 0, 0)
    lootSessionLaborLabel:SetText("Labor: " .. tostring(laborSpent) .. " (" .. string.format('%.0f', laborPerHour) .. "/hr)")

    local lootSessionPerKillLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionPerKillLabel", 0, true)
    lootSessionPerKillLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionPerKillLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionPerKillLabel, FONT_COLOR.DEFAULT)
    lootSessionPerKillLabel:AddAnchor("TOPLEFT", lootSessionDurationLabel, 0, 24)
    lootSessionPerKillLabel:SetText("Profit per Kill: " .. string.format('%.2f', profitTotal / kills) .. "g")
    local lootSessionPerLaborLabel = lootSessionDetailsWindow:CreateChildWidget("label", "lootSessionPerLaborLabel", 0, true)
    lootSessionPerLaborLabel.style:SetFontSize(FONT_SIZE.LARGE)
    lootSessionPerLaborLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(lootSessionPerLaborLabel, FONT_COLOR.DEFAULT)
    lootSessionPerLaborLabel:AddAnchor("TOPLEFT", lootSessionPerKillLabel, 0, 0)
    lootSessionPerLaborLabel:SetText("Silver Per Labor: " .. string.format('%.2f', profitTotal * 100 / laborSpent) .. "s")
    if laborSpent > kills then 
        lootSessionKillsLabel:Show(false)
        lootSessionPerKillLabel:Show(false)
        lootSessionPerLaborLabel:Show(true)
        lootSessionLaborLabel:Show(true)
    else
        lootSessionLaborLabel:Show(false)
        lootSessionPerLaborLabel:Show(false)
        lootSessionKillsLabel:Show(true)
        lootSessionPerKillLabel:Show(true)
    end

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
    function lootSessionDeleteBtn:OnClick()
        table.remove(pastSessions["sessions"], sessionIndex)
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
        api.File:Write(pastSessionsFilename, pastSessions)
        
        if lootSessionDetailsWindow then
            lootSessionDetailsWindow:Show(false)
            api.Interface:Free(lootSessionDetailsWindow)
            lootSessionDetailsWindow = nil
        end
        local sessionScrollList = lootWindow.sessionScrollList
        sessionScrollList:DeleteAllDatas()
        sessionScrollList.pageControl.maxPage = math.ceil(#pastSessions.sessions / pageSize)
        fillSessionTableData(sessionScrollList, 1)
        sessionScrollList.pageControl:SetCurrentPage(1, true)
    end
    lootSessionDeleteBtn:SetHandler("OnClick", lootSessionDeleteBtn.OnClick)


    local lootSessionItemsList = W_CTRL.CreateScrollListBox("lootSessionItemsList", lootSessionDetailsWindow, "TYPE2")
    lootSessionItemsList:AddAnchor("TOPLEFT", lootSessionDetailsWindow, 10, 100)
    lootSessionItemsList:AddAnchor("BOTTOMRIGHT", lootSessionDetailsWindow, -10, -60)
    lootSessionItemsList:SetExtent(400, 300)
    local sortedItemsByAHPrice = {}
    for itemId, itemCount in pairs(items) do
        local cleanedItemId = getCleanedItemId(itemId)
        local itemPrice = AH_PRICES[tonumber(cleanedItemId)]
        local totalValue = 0
        if itemPrice ~= nil then
            totalValue = itemCount * (itemPrice.average or 0)
        end
        table.insert(sortedItemsByAHPrice, {itemId = itemId, itemCount = itemCount, totalValue = totalValue})
    end
    table.sort(sortedItemsByAHPrice, function(a, b)
        return a.totalValue > b.totalValue
    end)
    local count = 1
    for _, item in ipairs(sortedItemsByAHPrice) do 
        local itemInfo = api.Item:GetItemInfoByType(tonumber(getCleanedItemId(item.itemId)))
        local displayStr = itemInfo.name .. " x" .. item.itemCount .. " (" .. string.format('%.0f', item.totalValue) .. "g)"
        lootSessionItemsList:AppendItem(displayStr, count)
        count = count + 1
    end 


end 

local function isLootWindowOpen()
    if eluDisplayWindow:IsVisible() then 
        return true
    else 
        return false
    end 
end

local function OnUpdate(dt)
    local settings = api.GetSettings("elu_tracker")
    if initializeLootWindowPos ~= true then 
        lootWindow.lootTrackerOverlay:RemoveAllAnchors()
        lootWindow.lootTrackerOverlay:AddAnchor("TOPLEFT", "UIParent", settings.lootOverlayX, settings.lootOverlayY)
        initializeLootWindowPos = true
    end 
    
    if isLootWindowOpen() then
        if displayRefreshCounter + dt > DISPLAY_REFRESH_MS then
            displayRefreshCounter = 0

            local sessionScrollList = lootWindow.sessionScrollList
            sessionScrollList.pageControl.maxPage = maxPage
            fillSessionTableData(sessionScrollList, 1)
            sessionScrollList.pageControl:SetCurrentPage(1, true)
        end
        displayRefreshCounter = displayRefreshCounter + dt
    else
        displayRefreshCounter = DISPLAY_REFRESH_MS
    end

    if laborUsedTimer + dt > LABOR_USED_TIMER_RATE then 
        laborUsedTimer = 0
        laborUsed = false
    end
    laborUsedTimer = laborUsedTimer + dt

    if sessionClockRefreshTimer + dt > SESSION_CLOCK_REFRESH_RATE then 
        sessionClockRefreshTimer = 0
        lootWindow.lootTrackerOverlay.timerLabel:SetText(displayOverlayTimeString(lootTrackerSessionTimer / 1000))
        if currentSession ~= nil then
            local profitPerHour = currentSession["profitTotal"] / (lootTrackerSessionTimer / 1000) * 3600
            local killsPerHour = currentSession["kills"] / (lootTrackerSessionTimer / 1000) * 3600
            local silverPerLabor = currentSession["profitTotal"] * 100 / currentSession["laborSpent"]

            lootWindow.lootTrackerOverlay.profitLabel:SetText("Profit: " .. string.format('%.0f', tostring(currentSession["profitTotal"])) .. "g" .. " (" .. string.format('%.0f', tostring(profitPerHour)) .. "g/hr)")
            lootWindow.lootTrackerOverlay.killsLabel:SetText("Kills: " .. tostring(currentSession["kills"]) .. " (" .. string.format('%.0f', tostring(killsPerHour)) .. "/hr)")
            lootWindow.lootTrackerOverlay.laborLabel:SetText("Labor: " .. tostring(currentSession["laborSpent"] .. " (" .. string.format('%.0f', tostring(silverPerLabor)) .. "s/labor)"))
        else 
            lootWindow.lootTrackerOverlay.profitLabel:SetText("Profit: 0g")
            lootWindow.lootTrackerOverlay.killsLabel:SetText("Kills: 0")
            lootWindow.lootTrackerOverlay.laborLabel:SetText("Labor: 0")
        end 
    end
    sessionClockRefreshTimer = sessionClockRefreshTimer + dt

    if currentSession ~= nil and sessionPaused ~= true then 
        lootTrackerSessionTimer = lootTrackerSessionTimer + dt
    end 
    
end 


local function SessionSetFunc(subItem, data, setValue)
    if setValue then
        local sessionIndex = data.index
        local packObject = nil
        local packName = "Unknown Pack (id: " .. tostring(data.packId) .. ")" 
        if packObject ~= nil then 
            if packObject.name ~= nil then packName = packObject.name end
        end
        local items = data.items
        local lootZone = data.zone
        local kills = data.kills
        local laborSpent = data.laborSpent or 0
        local profitTotal = data.profitTotal
        local costTotal = data.costTotal
        local date = api.Time:TimeToDate(data.localTimestamp)
        local duration = differenceBetweenTimestamps(data.endTimestamp, data.localTimestamp)
        local durationStr = displayTimeString(duration)

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
                local durationInHours = duration / 3600
                local cratesPerHour = highestCrateItemCount / durationInHours
                leftTextStr = crateItemInfo.name .. " x" .. tostring(highestCrateItemCount) .. " (" .. string.format('%.0f', cratesPerHour) .. "/hr)"
            else
                leftTextStr = "No crates found"
            end
        end
        if items then
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
                local durationInHours = duration / 3600
                local coinpursesPerHour = highestCoinpurseItemCount / durationInHours
                leftTextStr = leftTextStr .. "\n" .. coinpurseItemInfo.name .. " x" .. tostring(highestCoinpurseItemCount) .. " (" .. string.format('%.0f', coinpursesPerHour) .. "/hr)"
            else
                leftTextStr = leftTextStr .. "\nNo coinpurses found"
            end
        end

        local rightTextStr = "Profit: " .. tostring(profitTotal)
        if type(profitTotal) == "number" then 
            rightTextStr = "Profit: " .. string.format('%.0f', tostring(profitTotal)) .. "g" .. " (" .. string.format('%.0f', profitTotal / (duration / 3600)) .. "g/hr)"
        end 
        if kills > 0 then 
            rightTextStr = rightTextStr .. " \n " .. "Kills: " .. tostring(kills) .. " (" .. string.format('%.0f', kills / (duration / 3600)) .. "/hr)"
        else 
            rightTextStr = rightTextStr .. " \n " .. "Labor Spent: " .. tostring(laborSpent) .. " (" .. string.format('%.0f', laborSpent / (duration / 3600)) .. "/hr)"
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
                highestItemId = getCleanedItemId(highestItemId)
                local itemInfo = api.Item:GetItemInfoByType(tonumber(highestItemId))
                if itemInfo ~= nil then 
                    F_SLOT.SetIconBackGround(subItem.subItemIcon, itemInfo.path) 
                end 
            end
        end

        local titleStr = "Unknown Zone Loot Session"
        
        
        if kills > laborSpent then 
            if lootZone ~= nil then 
                titleStr = lootZone .. " Loot Session"
            end 
            subItem.bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
        else
            if lootZone ~= nil then 
                titleStr = lootZone .. " Harvesting Session"
            end 

            subItem.bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
        end 
        titleStr = titleStr .. " (".. durationStr .. ") "
        subItem.id = id
        subItem.textboxLeft:SetText(leftTextStr)
        subItem.textboxRight:SetText(rightTextStr)
        subItem.sessionTitle:SetText(titleStr)
        subItem.sessionDateLabel:SetText(string.format("%02d/%02d/%04d", date.month, date.day, date.year))
        function subItem.clickOverlay:OnClick()
            drawLootSessionDetails(sessionIndex)
        end
        subItem.clickOverlay:SetHandler("OnClick", subItem.clickOverlay.OnClick)
    end
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)
    if subItem.bg then return end 

    subItem:SetExtent(580, 70)
    local bg = subItem:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", subItem, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    bg:Show(true)
    subItem.bg = bg
    local sessionTitle = subItem:CreateChildWidget("label", "sessionTitle", 0, true)
    sessionTitle.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionTitle, FONT_COLOR.DEFAULT)
    sessionTitle:SetText("Unknown Loot Session")
    sessionTitle:AddAnchor("TOPLEFT", subItem, 10, 10)
    sessionTitle:SetAutoResize(true)
    sessionTitle.style:SetAlign(ALIGN.LEFT)
    local subItemIcon = CreateItemIconButton("subItemIcon", sessionTitle)
    subItemIcon:Show(true)
    F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    subItemIcon:AddAnchor("TOPLEFT", sessionTitle, 0, 10)
    subItem.subItemIcon = subItemIcon

    local sessionDateLabel = subItem:CreateChildWidget("label", "sessionDateLabel", 0, true)
    sessionDateLabel.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionDateLabel, FONT_COLOR.DEFAULT)
    sessionDateLabel:SetText("")
    sessionDateLabel:AddAnchor("TOPRIGHT", subItem, -12, 10)
    sessionDateLabel:SetAutoResize(true)
    sessionDateLabel.style:SetAlign(ALIGN.RIGHT)

    local textboxLeft = subItem:CreateChildWidget("textbox", "textboxLeft", 0, true)
    textboxLeft:AddAnchor("TOPLEFT", subItem, 55, 10)
    textboxLeft:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    textboxLeft.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(textboxLeft, FONT_COLOR.DEFAULT)
    subItem.textboxLeft = textboxLeft
    local textboxRight = subItem:CreateChildWidget("textbox", "textboxRight", 0, true)
    textboxRight:AddAnchor("TOPLEFT", subItem, 55, 10)
    textboxRight:AddAnchor("BOTTOMRIGHT", subItem, -12, 0)
    textboxRight.style:SetAlign(ALIGN.RIGHT)
    ApplyTextColor(textboxRight, FONT_COLOR.DEFAULT)
    subItem.textboxRight = textboxRight
    local clickOverlay = subItem:CreateChildWidget("button", "clickOverlay", 0, true)
    clickOverlay:AddAnchor("TOPLEFT", subItem, 0, 0)
    clickOverlay:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    subItem.clickOverlay = clickOverlay
end



local function OnLoad()
    local settings = api.GetSettings("elu_tracker")
    pastSessionsFilename = "elu_tracker_loot_sessions.lua"
    AH_PRICES = require("elu_tracker/data/auction_house_prices")
    eluTrackerEventWindow = api.Interface:CreateEmptyWindow("eluTrackerEventWindow", "UIParent")
    sessionPaused = false

    fillInAHPricesForCrates()
    fillInRegradeBrazierPrices()
    fillInArcheumTreePrices()
    fillInPureOrePrices()
    
    pastSessions = api.File:Read(pastSessionsFilename)
    if pastSessions == nil or pastSessions.sessions == nil then
        local ok, backupData = pcall(require, "elu_tracker/data/loot_sessions")
        if ok and type(backupData) == "table" and backupData.sessions then
            pastSessions = backupData
            api.File:Write(pastSessionsFilename, pastSessions)
            api.Log:Info("[Elu Tracker] Migrated pack history from addon data folder.")
        else
            pastSessions = { sessions = {} }
        end
        if maxPage == nil then maxPage = 1 end
    else
        maxPage = math.ceil(#pastSessions.sessions / pageSize)
    end

    function eluTrackerEventWindow:OnEvent(event, ...)
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
        if event == "STORE_SELL" then
        end
        if event == "CHAT_JOINED_CHANNEL" then 
            updateLastKnownChannel(unpack(arg))
        end 
    end
    eluTrackerEventWindow:SetHandler("OnEvent", eluTrackerEventWindow.OnEvent)
    eluTrackerEventWindow:RegisterEvent("ADDED_ITEM")
    eluTrackerEventWindow:RegisterEvent("REMOVED_ITEM")
    eluTrackerEventWindow:RegisterEvent("LABORPOWER_CHANGED")
    eluTrackerEventWindow:RegisterEvent("EXP_CHANGED")
    eluTrackerEventWindow:RegisterEvent("STORE_SELL")
    eluTrackerEventWindow:RegisterEvent("CHAT_JOINED_CHANNEL")

    lootWindow = eluDisplayWindow.tab.window[2].lootWindow
    local sessionScrollList = lootWindow.sessionScrollList
    sessionScrollList:InsertColumn("", 600, 1, SessionSetFunc, nil, nil, SessionsColumnLayoutSetFunc)
    sessionScrollList:InsertRows(8, false)
    sessionScrollList.listCtrl:DisuseSorting()
    sessionScrollList.pageControl.maxPage = maxPage
    fillSessionTableData(sessionScrollList, 1)
    sessionScrollList.pageControl:SetCurrentPage(1, true)
    function sessionScrollList:OnPageChangedProc(pageIndex)
        sessionScrollList:DeleteAllDatas()
        sessionScrollList:ResetScroll(0)
        fillSessionTableData(sessionScrollList, pageIndex)
    end 

    local lootTrackerOverlay = api.Interface:CreateEmptyWindow("lootTrackerOverlay", "UIParent")
    local lootOverlayX = settings.lootOverlayX or 0
    local lootOverlayY = settings.lootOverlayY or 0
    local lootOverlayVisible = true
    if settings.lootOverlayVisible ~= nil then 
        lootOverlayVisible = settings.lootOverlayVisible
    end
    lootTrackerOverlay:SetExtent(220, 80)
    if lootOverlayX == 0 and lootOverlayY == 0 then 
        lootTrackerOverlay:AddAnchor("CENTER", "UIParent", 0, 0)
    else
        lootTrackerOverlay:AddAnchor("TOPLEFT", "UIParent", lootOverlayX, lootOverlayY)
    end 
    lootTrackerOverlay:Show(lootOverlayVisible)
    lootTrackerOverlay:Clickable(false)
    local bg = lootTrackerOverlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(0),ConvertColor(0),ConvertColor(0),0.5)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", lootTrackerOverlay, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", lootTrackerOverlay, 0, 0)
    lootTrackerOverlay.bg = bg
    local timerLabel = lootTrackerOverlay:CreateChildWidget("label", "timerLabel", 0, true)
    timerLabel.style:SetShadow(true)
    timerLabel.style:SetAlign(ALIGN.RIGHT)
    timerLabel:AddAnchor("TOPRIGHT", lootTrackerOverlay, "TOPRIGHT", -15, 15)
    timerLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
    timerLabel:SetText("00:00:00")
    local clockIcon = timerLabel:CreateChildWidget("label", "clockIcon", 0, true)  
    clockIcon:AddAnchor("TOPLEFT", timerLabel, "TOPLEFT", -80, -14)
    local clockIconTexture = clockIcon:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
    clockIconTexture:SetTextureInfo("clock")
    clockIconTexture:AddAnchor("TOPLEFT", clockIcon, 0, 0)
    local profitLabel = lootTrackerOverlay:CreateChildWidget("label", "profitLabel", 0, true)
    profitLabel.style:SetShadow(true)
    profitLabel.style:SetAlign(ALIGN.LEFT)
    profitLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 35)
    profitLabel.style:SetFontSize(FONT_SIZE.SMALL)
    profitLabel:SetText("Profit: 0g")
    local killsLabel = lootTrackerOverlay:CreateChildWidget("label", "killsLabel", 0, true)
    killsLabel.style:SetShadow(true)
    killsLabel.style:SetAlign(ALIGN.LEFT)
    killsLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 50)
    killsLabel.style:SetFontSize(FONT_SIZE.SMALL)
    killsLabel:SetText("Kills: 0")
    local laborLabel = lootTrackerOverlay:CreateChildWidget("label", "laborLabel", 0, true)
    laborLabel.style:SetShadow(true)
    laborLabel.style:SetAlign(ALIGN.LEFT)
    laborLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 65)
    laborLabel.style:SetFontSize(FONT_SIZE.SMALL)
    laborLabel:SetText("Labor: 0")
    local startBtn = lootTrackerOverlay:CreateChildWidget("button", "startBtn", 0, true)
	startBtn:SetText("Start")
	startBtn:AddAnchor("TOPRIGHT", lootTrackerOverlay, -10, 30)
    startBtn.bg = startBtn:CreateNinePartDrawable("ui/common/tab_list.dds", "background")
    startBtn.bg:SetColor(ConvertColor(100),ConvertColor(100),ConvertColor(100),0.7)
    startBtn.bg:SetTextureInfo("bg_quest")
    startBtn.bg:AddAnchor("TOPLEFT", startBtn, 0, 0)
    startBtn.bg:AddAnchor("BOTTOMRIGHT", startBtn, 0, 0)
    startBtn:SetExtent(50,20)
    local saveBtn = lootTrackerOverlay:CreateChildWidget("button", "saveBtn", 0, true)
	saveBtn:SetText("End")
	saveBtn:AddAnchor("TOPRIGHT", lootTrackerOverlay, -10, 52)
	saveBtn.bg = saveBtn:CreateNinePartDrawable("ui/common/tab_list.dds", "background")
    saveBtn.bg:SetColor(ConvertColor(100),ConvertColor(100),ConvertColor(100),0.7)
    saveBtn.bg:SetTextureInfo("bg_quest")
    saveBtn.bg:AddAnchor("TOPLEFT", saveBtn, 0, 0)
    saveBtn.bg:AddAnchor("BOTTOMRIGHT", saveBtn, 0, 0)
    saveBtn:SetExtent(50,20)
    function startBtn:OnClick()
        startLootTrackerSession()
    end
    startBtn:SetHandler("OnClick", startBtn.OnClick)
    function saveBtn:OnClick()
        endLootTrackerSession()
    end
    saveBtn:SetHandler("OnClick", saveBtn.OnClick)
    local moveWnd = lootTrackerOverlay:CreateChildWidget("label", "moveWnd", 0, true)
    moveWnd:AddAnchor("TOPLEFT", lootTrackerOverlay, 0, 0)
    moveWnd:AddAnchor("TOPRIGHT", lootTrackerOverlay, 0, 0)
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
        settings.lootOverlayX = currentX
        settings.lootOverlayY = currentY
        api.SaveSettings()
    end
    moveWnd:SetHandler("OnDragStop", moveWnd.OnDragStop)
    moveWnd:EnableDrag(true)
    lootWindow.lootTrackerOverlay = lootTrackerOverlay
    local toggleOverlayBtn = lootWindow:CreateChildWidget("button", "toggleOverlayBtn", 0, true)
	toggleOverlayBtn:SetText("Toggle Overlay")
	toggleOverlayBtn:AddAnchor("BOTTOMRIGHT", lootWindow, -10, 50)
    ApplyButtonSkin(toggleOverlayBtn, BUTTON_BASIC.DEFAULT)
    function toggleOverlayBtn:OnClick()
        if lootTrackerOverlay:IsVisible() then
            lootTrackerOverlay:Show(false)
            settings.lootOverlayVisible = false
        else
            lootTrackerOverlay:Show(true)
            settings.lootOverlayVisible = true
        end
        api.SaveSettings()
    end
    toggleOverlayBtn:SetHandler("OnClick", toggleOverlayBtn.OnClick)

    api.On("UPDATE", OnUpdate)
    api.SaveSettings()
end

local function OnUnload()
    local settings = api.GetSettings("elu_tracker")
    if eluTrackerEventWindow then
        api.Interface:Free(eluTrackerEventWindow)
        eluTrackerEventWindow = nil
    end
    api.On("UPDATE", function() return end)
    
    if lootWindow and lootWindow.lootTrackerOverlay then
        lootWindow.lootTrackerOverlay:Show(false)
    end
    lootWindow = nil
    api.SaveSettings()
end

your_loot_addon.OnLoad = OnLoad
your_loot_addon.OnUnload = OnUnload

return your_loot_addon
