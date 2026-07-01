
local your_packs_addon = {
	name = "Packs",
	author = "Michaelqt",
	version = "",
	desc = ""
}

local itemTaskTypes = {}
local ITEM_TASK_ID_PACK_IN_VEHICLE = 16
local ITEM_TASK_ID_PICKED_PACK_UP = 23
local ITEM_TASK_ID_PACK_WAS_CRAFTED = 27
local ITEM_TASK_ID_CONSUMABLE_USED = 39
local ITEM_TASK_ID_MAIL_SEND_OR_RECEIVE = 46
local ITEM_TASK_ID_PACK_DROPPED = 61
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
local SESSION_TIMEOUT_MS = 60000 * 3  
local SESSION_TIMEOUT_MS = 1000 * 45  

local displayRefreshCounter = 0
local DISPLAY_REFRESH_MS = 60000

local packSlotCheckCounter = 0
local PACK_SLOT_CHECK_MS = 100

local PACK_TIMER_8HRS_IN_SECS = 28800

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
local function GetCurrentSetPrices()
    local cVal, dVal = 1.5, 22
    local data = api.File:Read("elu_commerce_prices.txt")
    if type(data) == "table" then
        if data.c then cVal = tonumber(data.c) or 1.5 end
        if data.d then dVal = tonumber(data.d) or 22 end
    end
    return cVal, dVal
end

local function getTotalGoldMadeFromPacks()
    local totalGold = 0
    if pastSessions == nil then return totalGold end
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        local pTotal = sessionObject.profitTotal

        if type(pTotal) == "number" then 
            totalGold = totalGold + pTotal
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
            local pTotal = sessionObject.profitTotal
            
            if type(pTotal) == "number" then
                pendingGold = pendingGold + pTotal
            end
        end 
    end 
    return pendingGold
end

local function getPendingResourcesTotal()
    local pendingC = 0
    local pendingD = 0
    local pendingG = 0
    if pastSessions == nil then return pendingC, pendingD, pendingG end
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        local timeDiffTilNow = PACK_TIMER_8HRS_IN_SECS - differenceBetweenTimestamps(api.Time:GetLocalTime(), sessionObject.localTimestamp)
        if timeDiffTilNow > 0 then
            if sessionObject.coinTypeId == 32103 then pendingC = pendingC + sessionObject.refundTotal
            elseif sessionObject.coinTypeId == 32106 then pendingD = pendingD + sessionObject.refundTotal
            elseif sessionObject.coinTypeId == 23633 then pendingG = pendingG + sessionObject.refundTotal end
        end 
    end 
    return pendingC, pendingD, pendingG
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
                packId = sessionObject.packId,
                refundTotal = sessionObject.refundTotal,
                profitTotal = sessionObject.profitTotal,
                costTotal = sessionObject.costTotal,
                packCount = sessionObject.packCount, 
                coinTypeId = sessionObject.coinTypeId,
                turnInZone = sessionObject.turnInZone,
                
                index = count,

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
    if coinTypeId == 0 then 
        currentSession["profitTotal"] = currentSession["refundTotal"] / 10000
    elseif coinTypeId == 32103 or coinTypeId == 32106 then 
        local cPrice, dPrice = GetCurrentSetPrices()
        local stabilizerPrice = (coinTypeId == 32103) and cPrice or dPrice
        currentSession["profitTotal"] = stabilizerPrice * currentSession["refundTotal"]
    elseif coinTypeId == 23633 then 
        local gildaDustPrice = AH_PRICES[8000026].average
        currentSession["profitTotal"] = gildaDustPrice * currentSession["refundTotal"]
    elseif coinTypeId == 40229 then 
        local lordsCoinPrice = AH_PRICES[26880].average
        currentSession["profitTotal"] = lordsCoinPrice * (currentSession["refundTotal"] / 100)
    else 
        currentSession["profitTotal"] = "Unknown"
    end 
    currentSession["costTotal"] = "Unknown"

    table.insert(pastSessions["sessions"], 1, currentSession)
    api.File:Write(pastSessionsFilename, pastSessions)

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

    if currentSession ~= nil then 
        saveCurrentSessionToFile()
    end 

    currentSession = sessionToStart
end 

local function addPackToSession(refund, coinTypeId, packId) 
    if coinTypeId == currentSession["coinTypeId"] and packId == currentSession["packId"] then 
        currentSession["packCount"] = currentSession["packCount"] + 1
        currentSession["refundTotal"] = currentSession["refundTotal"] + refund
        currentSession["localTimestamp"] = api.Time:GetLocalTime()
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

    if currentBackSlotItem ~= nil then 
        if currentSession == nil then 
            startPackTurnInSession(currentBackSlotItem, lastSeenCoinType)
            addPackToSession(lastSeenPrice, lastSeenCoinType, currentBackSlotItem)
        else
            local timeRightNow = api.Time:GetLocalTime()
            local timeDelta = tonumber(timeRightNow) - tonumber(currentSession["localTimestamp"])

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
    if removedItemId == currentBackSlotItem and itemTaskType == ITEM_TASK_ID_PACK_DROPPED then  
        currentBackSlotItem = nil
    end 

    if tonumber(removedItemId) == tonumber(currentBackSlotItem) and itemTaskType == ITEM_TASK_ID_PACK_TURNED_IN then 
        soldASpecialty("")
    end 
end
  
local function recordPackPickedUp(itemLinkText, itemCount, itemTaskType, tradeOtherName)
    local itemId = itemIdFromItemLinkText(itemLinkText)

    if packs_helper:IsASpecialtyPackById(tonumber(itemId)) == true then
        currentBackSlotItem = itemId
        if currentBackSlotItem ~= nil and packs_helper:GetSpecialtyPackNameById(tonumber(currentBackSlotItem)) ~= nil then 
            packOriginId = packs_helper:GetSpecialtyPackZoneIdById(tonumber(itemId))
            api.Store:GetSpecialtyRatioBetween(packOriginId, 8)
        end
    end 
end 

local function soldAtResourceTrader(itemLinkText, stackCount)
    local removedItemId = itemIdFromItemLinkText(itemLinkText)
    if tonumber(removedItemId) == tonumber(currentBackSlotItem) and tostring(stackCount) == "1" then 
        soldASpecialty("")
    end 
end

local function getSpecialtyInfo(specialtyRatioTable)
    for key, value in pairs(specialtyRatioTable) do 
    end 
end 

local function sellSpecialtyContentInfo(list)
    for key, value in pairs(list) do 
    end 
end 

local function traderDialogOpened(refund, itemType, itemGrade, coinType)
    currentBackSlotItem = itemType
    lastSeenPrice = refund
    lastSeenCoinType = coinType
end

local function refreshStatisticsLabels()
    local totalGold = getTotalGoldMadeFromPacks()
    local totalPacks = getTotalPacksTurnedIn()
    local favouritePackId = getFavouritePackType()
    local pendingGold = getPendingPackGoldTotal()
    local pendingC, pendingD, pendingG = getPendingResourcesTotal()

    commerceWindow.pendingGoldStr:SetText("Pending Pack Value: " .. string.format('%.2f', pendingGold) .. "g")
    if commerceWindow.pendingResourcesStr then
        commerceWindow.pendingResourcesStr:SetText(string.format("Charcoal: %d  |  Dragon: %d  |  Gilda: %d", math.floor(pendingC), math.floor(pendingD), math.floor(pendingG)))
    end
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
        if currentSession ~= nil then 
            api.Log:Info("[Elu Tracker] Ending current pack session...")
            saveCurrentSessionToFile()
            currentSession = nil
            
        end 
        sessionTimeoutCounter = 0
    end 
    sessionTimeoutCounter = sessionTimeoutCounter + dt

    if isPaystubWindowOpen() then
        if displayRefreshCounter + dt > DISPLAY_REFRESH_MS then 
            displayRefreshCounter = 0
            local sessionScrollList = commerceWindow.sessionScrollList
            sessionScrollList.pageControl.maxPage = maxPage
            fillSessionTableData(sessionScrollList, 1)
            sessionScrollList.pageControl:SetCurrentPage(1, true)

            refreshStatisticsLabels()
        end 
        displayRefreshCounter = displayRefreshCounter + dt
    else
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
    end
    packSlotCheckCounter = packSlotCheckCounter + dt 
end 

local function SessionSetFunc(subItem, data, setValue)
    if setValue then
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
        if data.packId ~= nil then 
            local packInfo = api.Item:GetItemInfoByType(tonumber(data.packId))
            F_SLOT.SetIconBackGround(subItem.subItemIcon, packInfo.path)
        end 
        
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
            subItem.bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
            subItem.sessionIsPaidLabel:SetText(timeDiffStr)
        else
            subItem.bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
            subItem.sessionIsPaidLabel:SetText("Paid on " .. string.format("%02d/%02d/%04d", date.day, date.month, date.year))
        end 
    end
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)
    if subItem.sessionTitle then return end 
    
    subItem:SetExtent(580, 70)
    local bg = subItem:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", subItem, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", subItem, 0, -4)
    bg:Show(true)
    subItem.bg = bg
    local sessionTitle = subItem:CreateChildWidget("label", "sessionTitle", 0, true)
    sessionTitle.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionTitle, FONT_COLOR.DEFAULT)
    sessionTitle:SetText("Unknown Turn-in")
    sessionTitle:AddAnchor("TOPLEFT", subItem, 10, 10)
    sessionTitle:SetAutoResize(true)
    sessionTitle.style:SetAlign(ALIGN.LEFT)
    local subItemIcon = CreateItemIconButton("subItemIcon", sessionTitle)
    subItemIcon:Show(true)
    F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    subItemIcon:AddAnchor("TOPLEFT", sessionTitle, 0, 10)
    subItem.subItemIcon = subItemIcon

    local sessionIsPaidLabel = subItem:CreateChildWidget("label", "sessionIsPaidLabel", 0, true)
    sessionIsPaidLabel.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionIsPaidLabel, FONT_COLOR.DEFAULT)
    sessionIsPaidLabel:SetText("")
    sessionIsPaidLabel:AddAnchor("TOPRIGHT", subItem, -12, 10)
    sessionIsPaidLabel:SetAutoResize(true)
    sessionIsPaidLabel.style:SetAlign(ALIGN.RIGHT)

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
    function clickOverlay:OnClick()
        api.Log:Info("Ding!")
    end 
    clickOverlay:SetHandler("OnClick", clickOverlay.OnClick)
end


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
        
        pack.destinations = {}
        if packZoneId ~= 0 then
            local sellableZones = api.Store:GetSellableZoneGroups(packZoneId)
            for key, value in pairs(sellableZones) do
                for key, value in pairs(value) do 
                end         
                pack.destinations[tostring(key)] = {} 
                pack.destinations[tostring(key)].id = tostring(value.id)
                pack.destinations[tostring(key)].name = tostring(value.name)
            end
        end 
        pack.zone = packZoneId
        
    end 
    
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
    
    local pendingC, pendingD, pendingG = getPendingResourcesTotal()
    local pendingResourcesStr = commerceWindow:CreateChildWidget("label", "pendingResourcesStr", 0, true)
    pendingResourcesStr.style:SetFontSize(FONT_SIZE.LARGE)
    pendingResourcesStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(pendingResourcesStr, FONT_COLOR.DEFAULT)
    pendingResourcesStr:SetText(string.format("Charcoal: %d  |  Dragon: %d  |  Gilda: %d", math.floor(pendingC), math.floor(pendingD), math.floor(pendingG)))
    pendingResourcesStr:AddAnchor("BOTTOMLEFT", pendingGoldStr, 0, 20)
    commerceWindow.pendingResourcesStr = pendingResourcesStr

    local totalGoldStr = commerceWindow:CreateChildWidget("label", "totalGoldStr", 0, true)
    totalGoldStr.style:SetFontSize(FONT_SIZE.LARGE)
    totalGoldStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(totalGoldStr, FONT_COLOR.DEFAULT)
    totalGoldStr:SetText("Total Gold Value Made: " .. string.format('%.2f', totalGold) .. "g")
    totalGoldStr:AddAnchor("BOTTOMLEFT", pendingResourcesStr, 0, 20)
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
    
    api.On("UPDATE", OnUpdate)

end

local function OnUnload()
    api.Interface:Free(eluTrackerEventWindow)
    api.On("UPDATE", function() return end)
    eluTrackerEventWindow = nil
end

local function RefreshUI()
    if commerceWindow and commerceWindow.sessionScrollList then
        fillSessionTableData(commerceWindow.sessionScrollList, commerceWindow.sessionScrollList.pageControl.currentPage)
        refreshStatisticsLabels()
    end
end

your_packs_addon.OnLoad = OnLoad
your_packs_addon.OnUnload = OnUnload
your_packs_addon.RefreshUI = RefreshUI

return your_packs_addon
