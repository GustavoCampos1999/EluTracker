
local your_packs_addon = {
	name = "Packs",
	author = "Michaelqt",
	version = "",
	desc = ""
}

local itemTaskTypes = {}
--- Item Task Type IDs
--> AAC 16 = Placed pack into vehicle trade slot
local ITEM_TASK_ID_PACK_IN_VEHICLE = 16
--> AAC 23 = Picked pack up off floor or out of vehicle
local ITEM_TASK_ID_PICKED_PACK_UP = 23
--> AAC 27 = Crafted a pack OR items consumed from pack craft
local ITEM_TASK_ID_PACK_WAS_CRAFTED = 27
--> AAC 39 = Drank a potion
local ITEM_TASK_ID_CONSUMABLE_USED = 39
--> AAC 46 = Mailed item OR take item out of mail
local ITEM_TASK_ID_MAIL_SEND_OR_RECEIVE = 46
--> AAC 61 = Dropped pack on the floor
local ITEM_TASK_ID_PACK_DROPPED = 61
--> AAC 109 = turned pack in DOMESTICALLY
local ITEM_TASK_ID_PACK_TURNED_IN = 109

local AH_PRICES

local packs_helper

local eluTrackerEventWindow 
local commerceWindow

local currentBackSlotItem
local lastKnownZone
local currentZone

local lastSeenPrice
local lastSeenCoinType

local currentSession
local pastSessions
local pastSessionsFilename

local sessionTimeoutCounter = 0
local SESSION_TIMEOUT_MS = 60000 * 3  --> 1 minute is 60000
local SESSION_TIMEOUT_MS = 1000 * 45  --> TEST OVERRIDE

local displayRefreshCounter = 0
local DISPLAY_REFRESH_MS = 60000

local packSlotCheckCounter = 0
local PACK_SLOT_CHECK_MS = 100

local PACK_TIMER_8HRS_IN_SECS = 28800

local pageSize = 20 --> number of sessions on page
local maxPage

-- helpers 
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

local function updateLastKnownChannel(channelId, channelName)
    local targetChannelId = 1
    if channelId ~= 1 then 
      return 
    end 
    if currentZone ~= nil then 
      lastKnownZone = currentZone
    end 
    currentZone = channelName
    -- api.Log:Info("  you have switched zones: " .. tostring(currentZone) .. " from zone: " .. tostring(lastKnownZone))
end 
-- Statistics functions
local function getTotalGoldMadeFromPacks()
    local totalGold = 0
    if pastSessions == nil then return totalGold end
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        if sessionObject.profitTotal ~= "Unknown" then 
            totalGold = totalGold + sessionObject.profitTotal
        end 
    end 
    return totalGold
end 
local function getTotalPacksTurnedIn()
    local totalPacks = 0
    if pastSessions == nil then return totalPacks end
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        totalPacks = totalPacks + sessionObject.packCount
    end 
    return totalPacks
end
local function getFavouritePackType()
    local packCounts = {}
    if pastSessions == nil then return nil end
    for _, sessionObject in pairs(pastSessions["sessions"]) do
        local packId = sessionObject.packId
        if packCounts[packId] == nil then
            packCounts[packId] = 0
        end
        packCounts[packId] = packCounts[packId] + sessionObject.packCount
    end

    local favouritePackId = nil
    local maxCount = 0
    for packId, count in pairs(packCounts) do
        if count > maxCount then
            maxCount = count
            favouritePackId = packId
        end
    end

    return favouritePackId
end
local function getPendingPackGoldTotal()
    local pendingGold = 0
    if pastSessions == nil then return pendingGold end
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        local timeDiffTilNow = PACK_TIMER_8HRS_IN_SECS - differenceBetweenTimestamps(api.Time:GetLocalTime(), sessionObject.localTimestamp)
        if timeDiffTilNow > 0 then
            pendingGold = pendingGold + sessionObject.profitTotal
        end 
    end 
    return pendingGold
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
                -- localTimestamp = "1733471130",
                -- packId = "42023",
                -- refundTotal = 482872,
                -- packCount = 1,
                -- coinTypeId = 0,
                -- Sessions data fields
                localTimestamp = sessionObject.localTimestamp,
                packId = sessionObject.packId,
                refundTotal = sessionObject.refundTotal,
                profitTotal = sessionObject.profitTotal,
                costTotal = sessionObject.costTotal,
                packCount = sessionObject.packCount, 
                coinTypeId = sessionObject.coinTypeId,
                turnInZone = sessionObject.turnInZone,
                
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

local function isPaystubWindowOpen()
    if eluDisplayWindow:IsVisible() then 
        return true
    else 
        return false
    end 
end

local function saveCurrentSessionToFile()
    if pastSessions == nil then 
        pastSessions = {}
        pastSessions["sessions"] = {}
    end 

    local coinTypeId = currentSession["coinTypeId"]
    -- Let's fill in the AH prices
    if coinTypeId == 0 then --> Gold
        currentSession["profitTotal"] = currentSession["refundTotal"] / 10000
elseif coinTypeId == 32103 or coinTypeId == 32106 then --> Charcoal Stabilizers & Dragon Essence Stabilizers
        local stabilizerPrice = 0
        local settings = api.GetSettings("elu_tracker")
        
        -- Prioriza o preço salvo manualmente; se não existir, usa o padrão do arquivo
        if settings and settings.manualPrices and settings.manualPrices[coinTypeId] then
            stabilizerPrice = settings.manualPrices[coinTypeId]
        elseif AH_PRICES and AH_PRICES[coinTypeId] then
            stabilizerPrice = AH_PRICES[coinTypeId].average
        end
        currentSession["profitTotal"] = stabilizerPrice * currentSession["refundTotal"]
    elseif coinTypeId == 23633 then --> Gilda Star, valued as Gilda Dust
        local gildaDustPrice = AH_PRICES[8000026].average
        currentSession["profitTotal"] = gildaDustPrice * currentSession["refundTotal"]
    elseif coinTypeId == 40229 then --> Lord's Pence, valued as Lord's Coin
        local lordsCoinPrice = AH_PRICES[26880].average
        currentSession["profitTotal"] = lordsCoinPrice * (currentSession["refundTotal"] / 100)
    else --> Unknown/untradeable/unpriceable 
        currentSession["profitTotal"] = "Unknown"
    end 
    -- TODO: Fill in pack costs
    currentSession["costTotal"] = "Unknown"

    -- Insert it into the top position (to sort by most recent)
    table.insert(pastSessions["sessions"], 1, currentSession)
    api.File:Write(pastSessionsFilename, pastSessions)

    -- Refresh payment list
    local sessionScrollList = commerceWindow.sessionScrollList
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

local function startPackTurnInSession(packId, coinTypeId)
    local sessionToStart = {}
    sessionToStart["packId"] = packId
    sessionToStart["coinTypeId"] = coinTypeId
    sessionToStart["localTimestamp"] = api.Time:GetLocalTime()
    sessionToStart["turnInZone"] = currentZone
    sessionToStart["packCount"] = 0
    sessionToStart["refundTotal"] = 0
    sessionToStart["profitTotal"] = "Unknown"
    sessionToStart["costTotal"] = "Unknown"
    -- TODO: Add date
    -- api.Log:Info("[Elu Tracker] Starting new pack turn-in session for packId: " .. tostring(packId) .. " with coinTypeId: " .. tostring(coinTypeId))
    -- Before overwriting the old session, if it isn't null, then let's save it.
    if currentSession ~= nil then 
        saveCurrentSessionToFile()
        -- api.Log:Info("[Elu Tracker] Saved previous pack session before starting new one.")
    end 

    currentSession = sessionToStart
end 

local function addPackToSession(refund, coinTypeId, packId) 
    if coinTypeId == currentSession["coinTypeId"] and packId == currentSession["packId"] then 
        -- api.Log:Info("[Elu Tracker] Adding pack to current session for packId: " .. tostring(packId) .. " with coinTypeId: " .. tostring(coinTypeId))
        currentSession["packCount"] = currentSession["packCount"] + 1
        currentSession["refundTotal"] = currentSession["refundTotal"] + refund
        -- Also, reset the timestamp to latest turn in
        currentSession["localTimestamp"] = api.Time:GetLocalTime()
        -- We need to update the current session timeout as well.
        sessionTimeoutCounter = 0
    end 
end 

local function itemIdFromItemLinkText(itemLinkText)
    local itemIdStr = string.sub(itemLinkText, 3)
    itemIdStr = split(itemIdStr, ",")
    itemIdStr = itemIdStr[1]
    return itemIdStr
end 

local function soldASpecialty(text)
    -- We just sold a pack!
    -- api.Log:Info("[Elu Tracker] Detected specialty pack turn-in for packId: " .. tostring(currentBackSlotItem) .. " with refund: " .. tostring(lastSeenPrice) .. " and coinTypeId: " .. tostring(lastSeenCoinType))
    if currentBackSlotItem ~= nil then 
        -- if there is no session, start one
        if currentSession == nil then 
            startPackTurnInSession(currentBackSlotItem, lastSeenCoinType)
            addPackToSession(lastSeenPrice, lastSeenCoinType, currentBackSlotItem)
        else
            local timeRightNow = api.Time:GetLocalTime()
            local timeDelta = tonumber(timeRightNow) - tonumber(currentSession["localTimestamp"])

            -- if there is a session, see if it's been less than 5 minutes. if it has been, write to current session
            -- NOTE: start a new session if the turned in pack doesnt match the packId or its cointype ID
            if lastSeenCoinType == currentSession["coinTypeId"] and currentBackSlotItem == currentSession["packId"] then
                addPackToSession(lastSeenPrice, lastSeenCoinType, currentBackSlotItem)
            elseif lastSeenCoinType ~= currentSession["coinTypeId"] or currentBackSlotItem ~= currentSession["packId"] then
                startPackTurnInSession(currentBackSlotItem, lastSeenCoinType)
                addPackToSession(lastSeenPrice, lastSeenCoinType, currentBackSlotItem)
            end 
        end 
        
    end 

    currentBackSlotItem = nil
end 

local function recordPackPayment(itemLinkText, itemCount, removeState, itemTaskType, tradeOtherName)
    local removedItemId = itemIdFromItemLinkText(itemLinkText)
    -- api.Log:Info("[Elu Tracker] Detected removed item with ID: " .. tostring(removedItemId) .. " and task type: " .. tostring(itemTaskType))
    if removedItemId == currentBackSlotItem and itemTaskType == ITEM_TASK_ID_PACK_DROPPED then  
        currentBackSlotItem = nil
    end 

    if tonumber(removedItemId) == tonumber(currentBackSlotItem) and itemTaskType == ITEM_TASK_ID_PACK_TURNED_IN then 
        soldASpecialty("")
    end 
end
  
local function recordPackPickedUp(itemLinkText, itemCount, itemTaskType, tradeOtherName)
    local itemId = itemIdFromItemLinkText(itemLinkText)

    --- Legacy code, please do not touch.
    if packs_helper:IsASpecialtyPackById(tonumber(itemId)) == true then
        currentBackSlotItem = itemId
        if currentBackSlotItem ~= nil and packs_helper:GetSpecialtyPackNameById(tonumber(currentBackSlotItem)) ~= nil then 
            packOriginId = packs_helper:GetSpecialtyPackZoneIdById(tonumber(itemId))
            api.Store:GetSpecialtyRatioBetween(packOriginId, 8)
        end
    end 
    --- Ends untouchable legacy code, PLEASE DO NOT TOUCH.
end 

local function soldAtResourceTrader(itemLinkText, stackCount)
    -- api.Log:Info("sold: " .. itemLinkText .. " x" .. tostring(stackCount))
    local removedItemId = itemIdFromItemLinkText(itemLinkText)
    if tonumber(removedItemId) == tonumber(currentBackSlotItem) and tostring(stackCount) == "1" then 
        soldASpecialty("")
    end 
end

local function getSpecialtyInfo(specialtyRatioTable)
    for key, value in pairs(specialtyRatioTable) do 
        -- api.Log:Info(value.itemInfo.name .. " at " .. value.ratio .. "%")
    end 
end 

local function sellSpecialtyContentInfo(list)
    for key, value in pairs(list) do 
        -- api.Log:Info(key .. " " .. value)
    end 
end 

local function traderDialogOpened(refund, itemType, itemGrade, coinType)
    -- api.Log:Info(tostring(itemType) .. " turns in for " .. tostring(refund) .. " of coinType: " .. tostring(coinType))
    currentBackSlotItem = itemType
    lastSeenPrice = refund
    lastSeenCoinType = coinType
end

local function refreshStatisticsLabels()
    local totalGold = getTotalGoldMadeFromPacks()
    local totalPacks = getTotalPacksTurnedIn()
    local favouritePackId = getFavouritePackType()
    local pendingGold = getPendingPackGoldTotal()

    commerceWindow.pendingGoldStr:SetText("Pending Pack Value: " .. string.format('%.2f', pendingGold) .. "g")
    commerceWindow.totalGoldStr:SetText("Total Gold Value Made: " .. string.format('%.2f', totalGold) .. "g")
    commerceWindow.totalPacksStr:SetText("Total Packs Turned In: " .. totalPacks)
    if favouritePackId == nil then favouritePackId = 0 end
    local favouritePackName = api.Item:GetItemInfoByType(tonumber(favouritePackId))
    if favouritePackName ~= nil then 
        favouritePackName = favouritePackName.name
    else 
        favouritePackName = "No favourite yet."
    end
    commerceWindow.favouritePackStr:SetText("Favourite Pack: " .. favouritePackName)
end 

local function OnUpdate(dt) 
    if sessionTimeoutCounter + dt > SESSION_TIMEOUT_MS then
        -- Save, and clear session
        -- api.Log:Info("[Elu Tracker] Pack session timed out due to inactivity.")
        if currentSession ~= nil then 
            api.Log:Info("[Elu Tracker] Ending current pack session...")
            saveCurrentSessionToFile()
            currentSession = nil
            
        end 
        sessionTimeoutCounter = 0
    end 
    sessionTimeoutCounter = sessionTimeoutCounter + dt

    -- Only refresh the display if the paystub window is open
    if isPaystubWindowOpen() then
        if displayRefreshCounter + dt > DISPLAY_REFRESH_MS then 
            displayRefreshCounter = 0
            local sessionScrollList = commerceWindow.sessionScrollList
            sessionScrollList.pageControl.maxPage = maxPage
            fillSessionTableData(sessionScrollList, 1)
            sessionScrollList.pageControl:SetCurrentPage(1, true)

            -- Refresh stats
            refreshStatisticsLabels()
        end 
        displayRefreshCounter = displayRefreshCounter + dt
    else
        -- Optional: reset so it refreshes promptly when reopened
        displayRefreshCounter = DISPLAY_REFRESH_MS
    end

    if packSlotCheckCounter + dt > PACK_SLOT_CHECK_MS then 
        packSlotCheckCounter = 0
        local backpackInfo = api.Equipment:GetEquippedItemTooltipInfo(EQUIP_SLOT.BACKPACK)
        if backpackInfo == nil then 
            currentBackSlotItem = nil
        elseif packs_helper:IsASpecialtyPackById(tonumber(backpackInfo.itemType)) then 
            currentBackSlotItem = backpackInfo.itemType
        else
            currentBackSlotItem = nil
        end 
        -- api.Log:Info(currentBackSlotItem) 
    end
    packSlotCheckCounter = packSlotCheckCounter + dt 
end 

--- Session Scroll List Functions
local function SessionSetFunc(subItem, data, setValue)
    if setValue then
        -- Data Assignments
        local sessionIndex = data.index
        local packObject = packs_helper:GetSpecialtyPackNameById(tonumber(data.packId))
        local packName = "Unknown Pack (id: " .. tostring(data.packId) .. ")" 
        if packObject ~= nil then 
            if packObject.name ~= nil then packName = packObject.name end
        end
        local turnInZone = data.turnInZone
        local packCount = tostring(data.packCount)
        local coinTypeId = tonumber(data.coinTypeId)
        local profitTotal = data.profitTotal
        local costTotal = data.costTotal
        local coinTypeName = "Unknown refund type"
        if coinTypeId ~= nil then 
            coinTypeName = api.Item:GetItemInfoByType(coinTypeId).name
        end
        local date = api.Time:TimeToDate(data.localTimestamp)
        local timeDiffTilNow = PACK_TIMER_8HRS_IN_SECS - differenceBetweenTimestamps(api.Time:GetLocalTime(), data.localTimestamp)
        local timeDiffStr = "Payment In: " .. displayTimeString(tonumber(timeDiffTilNow))
        -- Display Strings
        local leftTextStr = packName .. " x" .. packCount 
        if coinTypeId == 0 then 
            leftTextStr = leftTextStr .. "\n " .. string.format('%.2f', tostring(data.refundTotal / 10000)) .. " Gold"
        elseif coinTypeId > 0 then
            leftTextStr = leftTextStr .. "\n " .. coinTypeName .. " x" .. tostring(data.refundTotal)
        end

        local rightTextStr = "Profit: " .. tostring(profitTotal)
        if type(profitTotal) == "number" then 
            rightTextStr = "Profit: " .. string.format('%.2f', tostring(profitTotal)) .. "g"
        end 
        if type(costTotal) == "number" then 
            rightTextStr = rightTextStr .. " \n " .. "Cost: " .. string.format('%.2f', tostring(costTotal)) .. "g"
        else 
            rightTextStr = rightTextStr .. " \n " .. "Cost: " .. tostring(costTotal)
        end 
        -- api.Log:Info(subItem.subItemIcon)
        if data.packId ~= nil then 
            local packInfo = api.Item:GetItemInfoByType(tonumber(data.packId))
            F_SLOT.SetIconBackGround(subItem.subItemIcon, packInfo.path)
        end 
        -- api.Log:Info(packInfo.path)
        
        local titleStr = "Unknown Zone Specialty Turn-in"
        if turnInZone ~= nil then 
            titleStr = turnInZone .. " Specialty Turn-in"
            if coinTypeId == 0 then 
                titleStr = titleStr .. " (Domestic)"
            elseif coinTypeId > 0 then 
                titleStr = titleStr .. " (International)"
            end 
        end 
        
        subItem.id = id
        subItem.textboxLeft:SetText(leftTextStr)
        subItem.textboxRight:SetText(rightTextStr)
        subItem.sessionTitle:SetText(titleStr)
        if timeDiffTilNow > 0 then 
            -- Not paid yet, set background to red and paid label to remaining time
            subItem.bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
            subItem.sessionIsPaidLabel:SetText(timeDiffStr)
        else
            -- Has been paid, set background to green.
            subItem.bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
            subItem.sessionIsPaidLabel:SetText("Paid on " .. string.format("%02d/%02d/%04d", date.month, date.day, date.year))
        end 
        -- F_SLOT.SetIconBackGround(subItem.subItemIcon, data.dds)
    end
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)
    if subItem.bg then return end -- FIX: Memory Leak Prevention
    
    subItem:SetExtent(580, 70)
    -- Background colouring
    local bg = subItem:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", subItem, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    bg:Show(true)
    subItem.bg = bg
    -- Top-left Session Title
    local sessionTitle = subItem:CreateChildWidget("label", "sessionTitle", 0, true)
    sessionTitle.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionTitle, FONT_COLOR.DEFAULT)
    sessionTitle:SetText("Unknown Turn-in")
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

    -- Top-right Session "Is paid?" Label
    local sessionIsPaidLabel = subItem:CreateChildWidget("label", "sessionIsPaidLabel", 0, true)
    sessionIsPaidLabel.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionIsPaidLabel, FONT_COLOR.DEFAULT)
    sessionIsPaidLabel:SetText("")
    sessionIsPaidLabel:AddAnchor("TOPRIGHT", subItem, -12, 10)
    sessionIsPaidLabel:SetAutoResize(true)
    sessionIsPaidLabel.style:SetAlign(ALIGN.RIGHT)

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
    function clickOverlay:OnClick()
        -- modelViewerEquipItem(subItem.id, nil, dressUpWindow.modelViewer)
        api.Log:Info("Ding!")
    end 
    clickOverlay:SetHandler("OnClick", clickOverlay.OnClick)
end
---

local function OnLoad()
    packs_helper = require("elu_tracker/packs_helper")
    AH_PRICES = require("elu_tracker/data/auction_house_prices")

    eluTrackerEventWindow = api.Interface:CreateEmptyWindow("eluTrackerEventWindow", "UIParent")
    
    currentBackSlotItem = nil
    lastKnownZone = nil
    currentZone = nil
    currentSession = nil
    lastSeenPrice = nil
    lastSeenCoinType = nil
    pastSessionsFilename = "elu_tracker_pack_sessions.lua"

    -- Load past sessions
    pastSessions = api.File:Read(pastSessionsFilename)
    if pastSessions == nil or pastSessions.sessions == nil then
        local ok, backupData = pcall(require, "elu_tracker/data/pack_sessions")
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
    

    for packId, pack in pairs(packs_helper.packsInfo) do
        local packZoneId = 0
        for zoneId, zoneName in pairs(packs_helper.zonesInfo) do
            if string.find(pack.name, zoneName) then 
                packZoneId = zoneId
            end 
        end 
        -- api.Log:Info("  This pack belongs to zone: " .. packZoneId)
        
        pack.destinations = {}
        if packZoneId ~= 0 then
            local sellableZones = api.Store:GetSellableZoneGroups(packZoneId)
            for key, value in pairs(sellableZones) do
                for key, value in pairs(value) do 
                    -- api.Log:Info(key .. " " .. tostring(value))
                end         
                pack.destinations[tostring(key)] = {} 
                pack.destinations[tostring(key)].id = tostring(value.id)
                pack.destinations[tostring(key)].name = tostring(value.name)
            end
        end 
        -- api.Log:Info(table.concat(pack.destinations, ","))
        pack.zone = packZoneId
        
    end 
    
    -- Load and write statistics to paystub window
    local totalGold = getTotalGoldMadeFromPacks()
    local totalPacks = getTotalPacksTurnedIn()
    local favouritePackId = getFavouritePackType()
    local pendingGold = getPendingPackGoldTotal()

    local productionZones = api.Store:GetProductionZoneGroups()
    function eluTrackerEventWindow:OnEvent(event, ...)
        if event == "REMOVED_ITEM" then      
            recordPackPayment(unpack(arg))
        end
        if event == "ADDED_ITEM" then
            recordPackPickedUp(unpack(arg))
        end 
        if event == "SELL_SPECIALTY" then 
            -- soldASpecialty(unpack(arg))
        end
        if event == "STORE_SELL" then
            soldAtResourceTrader(unpack(arg))
        end
        if event == "SPECIALTY_RATIO_BETWEEN_INFO" then 
            getSpecialtyInfo(unpack(arg))
        end 
        if event == "CHAT_JOINED_CHANNEL" then 
            updateLastKnownChannel(unpack(arg))
        end 
        if event == "SELL_SPECIALTY_CONTENT_INFO" then 
            sellSpecialtyContentInfo(unpack(arg))
        end 
        if event == "UPDATE_SPECIALTY_RATIO" then 
            traderDialogOpened(unpack(arg))
        end 
    end

    eluTrackerEventWindow:SetHandler("OnEvent", eluTrackerEventWindow.OnEvent)
    eluTrackerEventWindow:RegisterEvent("ADDED_ITEM")
    eluTrackerEventWindow:RegisterEvent("REMOVED_ITEM")
    eluTrackerEventWindow:RegisterEvent("STORE_SELL")
    eluTrackerEventWindow:RegisterEvent("SELL_SPECIALTY")
    eluTrackerEventWindow:RegisterEvent("SPECIALTY_RATIO_BETWEEN_INFO")
    eluTrackerEventWindow:RegisterEvent("CHAT_JOINED_CHANNEL")
    eluTrackerEventWindow:RegisterEvent("ITEM_ACQUISITION_BY_LOOT")
    eluTrackerEventWindow:RegisterEvent("UPDATE_SPECIALTY_RATIO")
    eluTrackerEventWindow:RegisterEvent("SELL_SPECIALTY_CONTENT_INFO")

    -- Initializing Commerce Tab
    eluDisplayWindow:Show(false)
    commerceWindow = eluDisplayWindow.tab.window[1].commerceWindow
    local sessionScrollList = commerceWindow.sessionScrollList
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
    commerceWindow.sessionScrollList = sessionScrollList

    local pendingGoldStr = commerceWindow:CreateChildWidget("label", "pendingGoldStr", 0, true)
    pendingGoldStr.style:SetFontSize(FONT_SIZE.LARGE)
    pendingGoldStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(pendingGoldStr, FONT_COLOR.DEFAULT)
    pendingGoldStr:SetText("Pending Pack Value: " .. string.format('%.2f', pendingGold) .. "g")
    pendingGoldStr:AddAnchor("BOTTOMLEFT", commerceWindow, 15, 50)
    commerceWindow.pendingGoldStr = pendingGoldStr

    local totalGoldStr = commerceWindow:CreateChildWidget("label", "totalGoldStr", 0, true)
    totalGoldStr.style:SetFontSize(FONT_SIZE.LARGE)
    totalGoldStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(totalGoldStr, FONT_COLOR.DEFAULT)
    totalGoldStr:SetText("Total Gold Value Made: " .. string.format('%.2f', totalGold) .. "g")
    totalGoldStr:AddAnchor("BOTTOMLEFT", pendingGoldStr, 0, 30)
    commerceWindow.totalGoldStr = totalGoldStr

    local totalPacksStr = commerceWindow:CreateChildWidget("label", "totalPacksStr", 0, true)
    totalPacksStr.style:SetFontSize(FONT_SIZE.LARGE)
    totalPacksStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(totalPacksStr, FONT_COLOR.DEFAULT)
    totalPacksStr:SetText("Total Packs Turned In: " .. totalPacks)
    totalPacksStr:AddAnchor("BOTTOMLEFT", totalGoldStr, 0, 20)
    commerceWindow.totalPacksStr = totalPacksStr

    if favouritePackId == nil then favouritePackId = 0 end
    local favouritePackName = api.Item:GetItemInfoByType(tonumber(favouritePackId))
    if favouritePackName ~= nil then 
        favouritePackName = favouritePackName.name
    else 
        favouritePackName = "No favourite yet."
    end
    local favouritePackStr = commerceWindow:CreateChildWidget("label", "favouritePackStr", 0, true)
    favouritePackStr.style:SetFontSize(FONT_SIZE.LARGE)
    favouritePackStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(favouritePackStr, FONT_COLOR.DEFAULT)
    favouritePackStr:SetText("Favourite Pack: " .. favouritePackName)
    favouritePackStr:AddAnchor("BOTTOMLEFT", totalPacksStr, 0, 20)
    
    -- api.Map:ToggleMapWithPortal(323, 16461, 11630, 100)
    -- api.Log:Info(tostring(currentDate.year) .. "-" .. tostring(currentDate.month) .. "-" .. tostring(currentDate.day))

    api.On("UPDATE", OnUpdate)
    -- api.SaveSettings()
end

local function OnUnload()
    api.Interface:Free(eluTrackerEventWindow)
    api.On("UPDATE", function() return end)
    eluTrackerEventWindow = nil
end

your_packs_addon.OnLoad = OnLoad
your_packs_addon.OnUnload = OnUnload

return your_packs_addon
