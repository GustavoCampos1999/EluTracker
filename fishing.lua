local elu_fishing_addon = {
    name = "Fishing",
    author = "Eludelu",
    version = "1.0",
    desc = "Tracks fishing turn-ins and profit."
}

local ITEM_TASK_ID_PACK_IN_VEHICLE = 16
local ITEM_TASK_ID_PACK_DROPPED = 61
local ITEM_TASK_ID_PACK_TURNED_IN = 109

local eluFishingEventWindow
local fishingWindow 

local lastKnownZone
local currentZone

local currentBackSlotItem = nil
local lastSeenPrice = 0
local lastSeenCoinType = 0

local recentFishRemovedId = nil
local recentFishTimer = 8000
local recentGoldReceived = 0
local recentGoldTimer = 8000

local currentSession
local pastSessions
local pastSessionsFilename = "elu_tracker_fishing_sessions.lua"

local sessionTimeoutCounter = 0
local SESSION_TIMEOUT_MS = 17000 

local displayRefreshCounter = 0
local DISPLAY_REFRESH_MS = 60000

local pageSize = 20
local maxPage

local function ConvertColor(color) return color / 255 end 

local FISH_IDS = {
    [27604] = true, [27603] = true, [27602] = true, -- Blue Marlin
    [27601] = true, [27600] = true, [27599] = true, -- Sailfish
    [27501] = true, [27458] = true, [27457] = true, -- Bluefin
    [39735] = true, [39734] = true, [39733] = true, -- Sunfish
    [27607] = true, [27606] = true, [27605] = true, -- Sturgeon
    [27504] = true, [27503] = true, [27502] = true, -- Carp
    [42160] = true, [27612] = true, [27611] = true, -- Electric Eel
    [27610] = true, [27609] = true, [27608] = true, -- Arowana
    [31691] = true, [30428] = true, [30422] = true, [30429] = true,
    [32064] = true, [32065] = true, [32066] = true, 
    [32067] = true, [32068] = true, [32069] = true, 
    [32070] = true, [32071] = true, [32072] = true, 
    [32073] = true, [32074] = true, [32075] = true, 
    [32076] = true, [32077] = true, [32078] = true, 
    [32085] = true, [32086] = true, [32087] = true, 
    [32088] = true, [32089] = true, [32090] = true, 
    [32091] = true, [32092] = true, [32093] = true, 
    [32094] = true, [32095] = true, [32096] = true, 
    [32097] = true, [32098] = true, [32099] = true, 
    [32100] = true, [32101] = true, [32102] = true, 
    [36369] = true, [36370] = true, [36371] = true, 
    [40828] = true, [40829] = true, [40830] = true, 
    [40831] = true, [40832] = true, [40833] = true, 
    [40834] = true, [40835] = true, [40836] = true, 
    [40837] = true, [40838] = true, [40839] = true, 
    [40840] = true, [40841] = true, [40842] = true, 
}

local function isAFish(itemArg)
    if not itemArg then return false end
    local nameToCheck = ""
    if type(itemArg) == "number" or tonumber(itemArg) ~= nil then
        local numId = tonumber(itemArg)
        if FISH_IDS[numId] then return true end
        local itemInfo = api.Item:GetItemInfoByType(numId)
        if not itemInfo then return false end
        if itemInfo.name then nameToCheck = string.lower(itemInfo.name) end
    elseif type(itemArg) == "string" then
        nameToCheck = string.lower(itemArg)
    end
    
    if nameToCheck ~= "" then
        if string.find(nameToCheck, "fry pack") or 
           string.find(nameToCheck, "gargantuan") or 
           string.find(nameToCheck, "marlin") or
           string.find(nameToCheck, "marlim") or
           string.find(nameToCheck, "sturgeon") or
           string.find(nameToCheck, "estur") or
           string.find(nameToCheck, "sailfish") or
           string.find(nameToCheck, "veleiro") or
           string.find(nameToCheck, "tuna") or
           string.find(nameToCheck, "atum") or
           string.find(nameToCheck, "snapper") or
           string.find(nameToCheck, "pargo") or
           string.find(nameToCheck, "carp") or
           string.find(nameToCheck, "carpa") or
           string.find(nameToCheck, "pike") or
           string.find(nameToCheck, "puffer") or
           string.find(nameToCheck, "baiacu") or
           string.find(nameToCheck, "arowana") or
           string.find(nameToCheck, "mullet") or
           string.find(nameToCheck, "tainha") or
           string.find(nameToCheck, "barramundi") or
           string.find(nameToCheck, "coelacanth") or
           string.find(nameToCheck, "celacanto") or
           string.find(nameToCheck, "sunfish") or
           string.find(nameToCheck, "peixe") or
           string.find(nameToCheck, "piranha") or
           string.find(nameToCheck, "arapaima") or
           string.find(nameToCheck, "pirarucu") or
           string.find(nameToCheck, "bass") or
           string.find(nameToCheck, "robalo") or
           string.find(nameToCheck, "koi") or
           string.find(nameToCheck, "bluefin") then
            return true
        end
    end
    return false
end

local function split(s, sep)
    local fields = {}
    local pattern = string.format("([^%s]+)", sep or " ")
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

-- ==========================================
-- PREVENÇÃO CONTRA NOTAÇÃO CIENTÍFICA (BUG DE 1969)
-- ==========================================
local function getSafeTimestamp()
    local t = api.Time:GetLocalTime()
    return string.format("%.0f", tonumber(t) or 0)
end

local function updateLastKnownChannel(channelId, channelName)
    if channelId ~= 1 then return end 
    if currentZone ~= nil then lastKnownZone = currentZone end 
    currentZone = channelName
end 

local function getTotalGoldMadeFromFishing()
    local totalGold = 0
    if pastSessions == nil or pastSessions["sessions"] == nil then return totalGold end
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        if type(sessionObject.profitTotal) == "number" then 
            totalGold = totalGold + sessionObject.profitTotal
        end 
    end 
    return totalGold
end 

local function getTotalFishSold()
    local totalFish = 0
    if pastSessions == nil or pastSessions["sessions"] == nil then return totalFish end
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        if type(sessionObject.packCount) == "number" then
            totalFish = totalFish + sessionObject.packCount
        end
    end 
    return totalFish
end

local function getFavouriteFishType()
    local fishCounts = {}
    if pastSessions == nil or pastSessions["sessions"] == nil then return nil end
    for _, sessionObject in pairs(pastSessions["sessions"]) do
        local fishId = sessionObject.packId
        if fishId then
            if fishCounts[fishId] == nil then fishCounts[fishId] = 0 end
            fishCounts[fishId] = fishCounts[fishId] + (sessionObject.packCount or 1)
        end
    end
    local favouriteFishId = nil
    local maxCount = 0
    for fishId, count in pairs(fishCounts) do
        if count > maxCount then maxCount = count; favouriteFishId = fishId end
    end
    return favouriteFishId
end

local function fillSessionTableData(itemScrollList, pageIndex)
    local startingIndex = 1
    if pageIndex > 1 then startingIndex = ((pageIndex - 1) * pageSize) + 1 end
    local endingIndex = startingIndex + pageSize
    itemScrollList:DeleteAllDatas()
    if pastSessions == nil or pastSessions["sessions"] == nil then return end
    local count = 1
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        if count >= startingIndex and count < endingIndex then 
            local itemData = {
                localTimestamp = sessionObject.localTimestamp,
                packId         = sessionObject.packId,
                refundTotal    = sessionObject.refundTotal,
                profitTotal    = sessionObject.profitTotal,
                packCount      = sessionObject.packCount, 
                coinTypeId     = sessionObject.coinTypeId,
                turnInZone     = sessionObject.turnInZone,
                index          = count,
                isViewData     = true, 
                isAbstention   = false
            }
            itemScrollList:InsertData(count, 1, itemData)
        end
        count = count + 1
    end 
end

local function saveCurrentSessionToFile()
    if pastSessions == nil then pastSessions = { sessions = {} } end 
    if not pastSessions.sessions then pastSessions.sessions = {} end
    
    if tonumber(currentSession["coinTypeId"]) == 0 then
        currentSession["profitTotal"] = (tonumber(currentSession["refundTotal"]) or 0) / 10000
    else 
        currentSession["profitTotal"] = 0
    end 
    
    local found = false
    for i, s in ipairs(pastSessions.sessions) do
        if s == currentSession then
            found = true
            break
        end
    end
    
    if not found then
        table.insert(pastSessions.sessions, 1, currentSession)
    end
    
    api.File:Write(pastSessionsFilename, pastSessions)
    
    if fishingWindow and fishingWindow.sessionScrollList then
        local sessionScrollList = fishingWindow.sessionScrollList
        maxPage = math.ceil(#pastSessions.sessions / pageSize)
        if maxPage < 1 then maxPage = 1 end
        sessionScrollList.pageControl.maxPage = maxPage
        fillSessionTableData(sessionScrollList, sessionScrollList.pageControl:GetCurrentPageIndex() or 1)
    end
end 

local function startFishTurnInSession(packId, coinTypeId)
    if currentSession ~= nil then 
        saveCurrentSessionToFile()
    end 
    currentSession = {
        packId        = packId,
        coinTypeId    = coinTypeId,
        localTimestamp = getSafeTimestamp(),
        turnInZone    = currentZone or "Unknown Zone",
        packCount     = 0,
        refundTotal   = 0,
        profitTotal   = 0
    }
    
    if pastSessions == nil then pastSessions = { sessions = {} } end
    if not pastSessions.sessions then pastSessions.sessions = {} end
    table.insert(pastSessions.sessions, 1, currentSession)
end 

local function addFishToSession(refund, coinTypeId, packId) 
    if currentSession == nil then
        startFishTurnInSession(packId, coinTypeId)
    end
    
    if tonumber(coinTypeId) == tonumber(currentSession["coinTypeId"]) and tonumber(packId) == tonumber(currentSession["packId"]) then 
        currentSession["packCount"]   = (tonumber(currentSession["packCount"]) or 0) + 1
        currentSession["refundTotal"] = (tonumber(currentSession["refundTotal"]) or 0) + refund
        currentSession["localTimestamp"] = getSafeTimestamp()
        currentSession["profitTotal"] = currentSession["refundTotal"] / 10000
        sessionTimeoutCounter = 0
        
        saveCurrentSessionToFile()
    else
        startFishTurnInSession(packId, coinTypeId)
        addFishToSession(refund, coinTypeId, packId)
    end 
end 

local function attemptFishSaleMatch(forceSave)
    if recentFishRemovedId and (recentGoldReceived > 0 or forceSave) then
        local fishPrice = recentGoldReceived > 0 and recentGoldReceived or 0
        local coinType  = 0 
        
        if currentSession == nil or tonumber(currentSession["packId"]) ~= tonumber(recentFishRemovedId) then 
            if currentSession ~= nil then saveCurrentSessionToFile() end
            startFishTurnInSession(recentFishRemovedId, coinType)
        end 
        
        addFishToSession(fishPrice, coinType, recentFishRemovedId)
        
        displayRefreshCounter = DISPLAY_REFRESH_MS
        recentFishRemovedId = nil
        recentGoldReceived = 0
    end
end

-- ==========================================
-- CAPTURA PRECISA DA BALANÇA E EQUIPAMENTO
-- ==========================================
local function traderDialogOpened(...)
    local args = arg or {...}
    local refund = tonumber(args[1])
    local itemType = tonumber(args[2])
    local coinType = tonumber(args[4]) or 0
    
    if itemType and isAFish(itemType) then
        currentBackSlotItem = itemType
        lastSeenPrice = refund or 0
        lastSeenCoinType = coinType
    end
end

local function itemIdFromItemLinkText(itemLinkText)
    local itemIdStr = string.sub(itemLinkText, 3)
    return split(itemIdStr, ",")[1]
end 

local function recordFishPayment(...)
    local args = arg or {...}
    local itemLinkText = args[1]
    local itemTaskType = tonumber(args[4])
    
    if not itemLinkText then return end
    local removedItemId = tonumber(itemIdFromItemLinkText(itemLinkText))

    if removedItemId and isAFish(removedItemId) then
        if itemTaskType ~= ITEM_TASK_ID_PACK_DROPPED and itemTaskType ~= ITEM_TASK_ID_PACK_IN_VEHICLE then 
            recentFishRemovedId = removedItemId
            recentFishTimer = 0
            
            if lastSeenPrice and lastSeenPrice > 0 and tonumber(currentBackSlotItem) == removedItemId then
                recentGoldReceived = lastSeenPrice
                recentGoldTimer = 0
                attemptFishSaleMatch(false)
                lastSeenPrice = 0
                currentBackSlotItem = nil
            else
                attemptFishSaleMatch(false)
            end
        end
        
        if itemTaskType == ITEM_TASK_ID_PACK_DROPPED then
            currentBackSlotItem = nil
            lastSeenPrice = 0
        end
    end 
end

local function handleEquipmentChanged(...)
    local args = arg or {...}
    local unit = args[1]
    local slot = tonumber(args[2])
    local equipString = args[3]
    
    if unit == "player" then
        if equipString and string.find(tostring(equipString), "i;") then
             local itemIdStr = split(string.sub(tostring(equipString), 3), ",")[1]
             if itemIdStr and isAFish(tonumber(itemIdStr)) then
                 currentBackSlotItem = tonumber(itemIdStr)
             end
        else
             if currentBackSlotItem ~= nil and slot == 4 then 
                 recentFishRemovedId = currentBackSlotItem
                 recentFishTimer = 0
                 
                 if lastSeenPrice and lastSeenPrice > 0 then
                     recentGoldReceived = lastSeenPrice
                     recentGoldTimer = 0
                     attemptFishSaleMatch(false)
                     lastSeenPrice = 0
                     currentBackSlotItem = nil
                 end
             end
        end
    end
end

-- ==========================================
-- ESTATÍSTICAS E TABELA 
-- ==========================================
local previousPlayerGold = -1
local function CheckMoney()
    local currentGold = 0
    if X2Util and type(X2Util.GetMyMoneyString) == "function" then
        currentGold = tonumber(X2Util:GetMyMoneyString()) or 0
    else
        local ok, g = pcall(function() return api.Unit:GetUnitMoney("player") end)
        if ok and type(g) == "number" then currentGold = g end
    end

    if currentGold > 0 then
        if previousPlayerGold == -1 then
            previousPlayerGold = currentGold
            return
        end
        if currentGold > previousPlayerGold then
            local profit = currentGold - previousPlayerGold
            
            if recentFishRemovedId and recentFishTimer < 8000 then
                recentGoldReceived = profit
                recentGoldTimer = 0
                attemptFishSaleMatch(false)
            end
        end
        previousPlayerGold = currentGold
    end
end

local function refreshStatisticsLabels()
    local totalGold = getTotalGoldMadeFromFishing()
    local totalFish = getTotalFishSold()
    local favouriteFishId = getFavouriteFishType()
    
    local todayProfit = 0
    local yesterdayProfit = 0
    
    if pastSessions and pastSessions.sessions then
        local nowStr = getSafeTimestamp()
        local nowDate = api.Time:TimeToDate(nowStr)
        
        for _, sessionObject in pairs(pastSessions.sessions) do
            if type(sessionObject.profitTotal) == "number" then
                local sDate = api.Time:TimeToDate(tostring(sessionObject.localTimestamp))
                if sDate and nowDate then
                    if tonumber(sDate.year) == tonumber(nowDate.year) and tonumber(sDate.month) == tonumber(nowDate.month) and tonumber(sDate.day) == tonumber(nowDate.day) then
                        todayProfit = todayProfit + sessionObject.profitTotal
                    else
                        local shiftedMs = tonumber(sessionObject.localTimestamp) + 86400000
                        local shiftedDate = api.Time:TimeToDate(string.format("%.0f", shiftedMs))
                        if shiftedDate and tonumber(shiftedDate.year) == tonumber(nowDate.year) and tonumber(shiftedDate.month) == tonumber(nowDate.month) and tonumber(shiftedDate.day) == tonumber(nowDate.day) then
                            yesterdayProfit = yesterdayProfit + sessionObject.profitTotal
                        end
                    end
                end
            end
        end
    end

    if fishingWindow then
        if fishingWindow.todayGoldStr then fishingWindow.todayGoldStr:SetText("Today's Profit: " .. string.format('%.2f', todayProfit) .. "g") end
        if fishingWindow.yesterdayGoldStr then fishingWindow.yesterdayGoldStr:SetText("Yesterday's Profit: " .. string.format('%.2f', yesterdayProfit) .. "g") end
        if fishingWindow.totalGoldStr then fishingWindow.totalGoldStr:SetText("Total Gold from Fishing: " .. string.format('%.2f', totalGold) .. "g") end
        if fishingWindow.totalPacksStr then fishingWindow.totalPacksStr:SetText("Total Fish Sold: " .. totalFish) end

        local favName = "No favourite yet."
        if favouriteFishId ~= nil then
            local info = api.Item:GetItemInfoByType(tonumber(favouriteFishId))
            if info then favName = info.name end
        end
        if fishingWindow.favouritePackStr then fishingWindow.favouritePackStr:SetText("Most Caught Fish: " .. favName) end
    end
end 

local function OnUpdate(dt) 
    CheckMoney()
    recentFishTimer = recentFishTimer + dt
    recentGoldTimer = recentGoldTimer + dt

    if currentSession ~= nil then
        sessionTimeoutCounter = sessionTimeoutCounter + dt
        if sessionTimeoutCounter > SESSION_TIMEOUT_MS then
            local fishInfo = api.Item:GetItemInfoByType(tonumber(currentSession.packId) or 0)
            local fishName = fishInfo and fishInfo.name or "Fish"
            api.Log:Info(string.format("[Elu Tracker] Updated %dx %s payment.", currentSession.packCount, fishName))
            
            currentSession = nil
            sessionTimeoutCounter = 0
        end
    end

    if eluDisplayWindow and eluDisplayWindow:IsVisible() then
        if displayRefreshCounter + dt > DISPLAY_REFRESH_MS then 
            displayRefreshCounter = 0
            local sessionScrollList = fishingWindow.sessionScrollList
            if maxPage == nil then maxPage = 1 end
            sessionScrollList.pageControl.maxPage = maxPage
            fillSessionTableData(sessionScrollList, sessionScrollList.pageControl:GetCurrentPageIndex() or 1)
            refreshStatisticsLabels()
        end 
        displayRefreshCounter = displayRefreshCounter + dt
    else
        displayRefreshCounter = DISPLAY_REFRESH_MS
    end
end 

local function SessionSetFunc(subItem, data, setValue)
    if setValue then
        local fishInfo = api.Item:GetItemInfoByType(tonumber(data.packId) or 0)
        local fishName = fishInfo and fishInfo.name or ("Unknown Fish (id: " .. tostring(data.packId) .. ")")
        
        local date = api.Time:TimeToDate(tostring(data.localTimestamp))
        
        local leftTextStr  = fishName .. " x" .. tostring(data.packCount or 1)
        local refundG = (tonumber(data.refundTotal) or 0) / 10000
        leftTextStr = leftTextStr .. "\n " .. string.format('%.2f', refundG) .. " Gold"
        
         local profG = tonumber(data.profitTotal) or 0
        local rightTextStr = ""

        if date then
            rightTextStr = string.format("%02d/%02d/%04d\n%02d:%02d\n%.2fg", date.day, date.month, date.year, date.hour, date.minute, profG)
        else
            rightTextStr = string.format("Sold recently\n%.2fg", profG)
        end

        if fishInfo and fishInfo.path then 
            F_SLOT.SetIconBackGround(subItem.subItemIcon, fishInfo.path)
        end 
        
        local titleStr = (data.turnInZone or "Unknown Zone") .. " Fish Stand"
        subItem.textboxLeft:SetText(leftTextStr)
        subItem.textboxRight:SetText(rightTextStr)
        subItem.sessionTitle:SetText(titleStr)
        subItem.bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
    
        subItem.sessionIsPaidLabel:SetText("")
    end
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)
    if subItem.bg then return end 
    subItem:SetExtent(580, 70)
    local bg = subItem:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", subItem, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    bg:Show(true)
    subItem.bg = bg

    local sessionTitle = subItem:CreateChildWidget("label", "sessionTitle", 0, true)
    sessionTitle.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionTitle, FONT_COLOR.DEFAULT)
    sessionTitle:AddAnchor("TOPLEFT", subItem, 10, 10)
    sessionTitle:SetAutoResize(true)
    
    local subItemIcon = CreateItemIconButton("subItemIcon", sessionTitle)
    subItemIcon:Show(true)
    F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    subItemIcon:AddAnchor("TOPLEFT", sessionTitle, 0, 10)
    subItem.subItemIcon = subItemIcon

    local sessionIsPaidLabel = subItem:CreateChildWidget("label", "sessionIsPaidLabel", 0, true)
    sessionIsPaidLabel.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionIsPaidLabel, FONT_COLOR.DEFAULT)
    sessionIsPaidLabel:AddAnchor("TOPRIGHT", subItem, -12, 10)
    sessionIsPaidLabel:SetAutoResize(true)

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
end

local function OnLoad()
    eluFishingEventWindow = api.Interface:CreateEmptyWindow("eluFishingEventWindow", "UIParent")
    fishingWindow = eluDisplayWindow.tab.window[3].fishingWindow

    if X2Util and type(X2Util.GetMyMoneyString) == "function" then
        previousPlayerGold = tonumber(X2Util:GetMyMoneyString()) or -1
    end

    pastSessions = api.File:Read(pastSessionsFilename)
    if pastSessions == nil or pastSessions.sessions == nil then
        local readOk, backupData = pcall(require, "elu_tracker/data/fishing_sessions")
        if readOk and type(backupData) == "table" and backupData.sessions then
            pastSessions = backupData
            api.File:Write(pastSessionsFilename, pastSessions)
        else
            pastSessions = { sessions = {} }
        end
        if maxPage == nil then maxPage = 1 end
    else
        maxPage = math.ceil(#pastSessions.sessions / pageSize)
    end

    function eluFishingEventWindow:OnEvent(event, ...)
        local args = arg or {...}
        if event == "UNIT_EQUIPMENT_CHANGED" then handleEquipmentChanged(unpack(args)) end
        if event == "REMOVED_ITEM" then recordFishPayment(unpack(args)) end
        if event == "CHAT_JOINED_CHANNEL" then updateLastKnownChannel(unpack(args)) end 
        if event == "UPDATE_SPECIALTY_RATIO" then traderDialogOpened(unpack(args)) end
    end

    eluFishingEventWindow:SetHandler("OnEvent", eluFishingEventWindow.OnEvent)
    eluFishingEventWindow:RegisterEvent("UNIT_EQUIPMENT_CHANGED")
    eluFishingEventWindow:RegisterEvent("REMOVED_ITEM")
    eluFishingEventWindow:RegisterEvent("CHAT_JOINED_CHANNEL")
    eluFishingEventWindow:RegisterEvent("UPDATE_SPECIALTY_RATIO")

    local sessionScrollList = fishingWindow.sessionScrollList
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
    fishingWindow.sessionScrollList = sessionScrollList

    local todayGoldStr = fishingWindow:CreateChildWidget("label", "todayGoldStr", 0, true)
    todayGoldStr.style:SetFontSize(FONT_SIZE.LARGE)
    todayGoldStr.style:SetAlign(ALIGN.LEFT)
    todayGoldStr:SetAutoResize(true)
    ApplyTextColor(todayGoldStr, FONT_COLOR.DEFAULT)
    todayGoldStr:AddAnchor("BOTTOMLEFT", fishingWindow, 15, 50)
    fishingWindow.todayGoldStr = todayGoldStr

    
    local rolloverBtn = fishingWindow:CreateChildWidget("button", "rolloverBtn", 0, true)
    rolloverBtn:SetText("<- Move to Yesterday")
    rolloverBtn:AddAnchor("LEFT", todayGoldStr, "RIGHT", 15, 0)
    ApplyButtonSkin(rolloverBtn, BUTTON_BASIC.DEFAULT)
    rolloverBtn:SetExtent(135, 25)

    local confirmDialog = fishingWindow:CreateChildWidget("emptywidget", "confirmDialog", 0, true)
    confirmDialog:SetExtent(260, 100)
    confirmDialog:AddAnchor("CENTER", fishingWindow, 0, 0)
    confirmDialog:Show(false)

    local confirmBg = confirmDialog:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    confirmBg:SetTextureInfo("bg_quest")
    confirmBg:SetColor(0, 0, 0, 0.95)
    confirmBg:AddAnchor("TOPLEFT", confirmDialog, 0, 0)
    confirmBg:AddAnchor("BOTTOMRIGHT", confirmDialog, 0, 0)

    local confirmLabel = confirmDialog:CreateChildWidget("label", "confirmLabel", 0, true)
    confirmLabel:SetText("Move today's profit to yesterday?")
    confirmLabel.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(confirmLabel, FONT_COLOR.DEFAULT)
    confirmLabel:AddAnchor("TOP", confirmDialog, 0, 20)

    local yesBtn = confirmDialog:CreateChildWidget("button", "yesBtn", 0, true)
    yesBtn:SetText("Yes")
    yesBtn:SetExtent(80, 25)
    yesBtn:AddAnchor("BOTTOMLEFT", confirmDialog, 20, -15)
    ApplyButtonSkin(yesBtn, BUTTON_BASIC.DEFAULT)

    local cancelBtn = confirmDialog:CreateChildWidget("button", "cancelBtn", 0, true)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetExtent(80, 25)
    cancelBtn:AddAnchor("BOTTOMRIGHT", confirmDialog, -20, -15)
    ApplyButtonSkin(cancelBtn, BUTTON_BASIC.DEFAULT)

    function rolloverBtn:OnClick()
        confirmDialog:Show(true)
        confirmDialog:Raise()
    end
    rolloverBtn:SetHandler("OnClick", rolloverBtn.OnClick)

    function cancelBtn:OnClick()
        confirmDialog:Show(false)
    end
    cancelBtn:SetHandler("OnClick", cancelBtn.OnClick)

    function yesBtn:OnClick()
        confirmDialog:Show(false)
        if pastSessions and pastSessions.sessions then
            local nowStr = getSafeTimestamp()
            local nowDate = api.Time:TimeToDate(nowStr)
            local changed = false
            
           for _, sessionObject in pairs(pastSessions.sessions) do
                local sDate = api.Time:TimeToDate(tostring(sessionObject.localTimestamp))
                if sDate and nowDate and tonumber(sDate.year) == tonumber(nowDate.year) and tonumber(sDate.month) == tonumber(nowDate.month) and tonumber(sDate.day) == tonumber(nowDate.day) then
                    sessionObject.localTimestamp = string.format("%.0f", tonumber(sessionObject.localTimestamp) - 86400000)
                    changed = true
                end
            end
            
            if changed then
                api.File:Write(pastSessionsFilename, pastSessions)
                refreshStatisticsLabels()
                if fishingWindow.sessionScrollList then
                    fillSessionTableData(fishingWindow.sessionScrollList, fishingWindow.sessionScrollList.pageControl:GetCurrentPageIndex() or 1)
                end
            end
        end
    end
    yesBtn:SetHandler("OnClick", yesBtn.OnClick)

    local yesterdayGoldStr = fishingWindow:CreateChildWidget("label", "yesterdayGoldStr", 0, true)
    yesterdayGoldStr.style:SetFontSize(FONT_SIZE.LARGE)
    yesterdayGoldStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(yesterdayGoldStr, FONT_COLOR.DEFAULT)
    yesterdayGoldStr:AddAnchor("BOTTOMLEFT", todayGoldStr, 0, 30)
    fishingWindow.yesterdayGoldStr = yesterdayGoldStr

    local totalGoldStr = fishingWindow:CreateChildWidget("label", "totalGoldStr", 0, true)
    totalGoldStr.style:SetFontSize(FONT_SIZE.LARGE)
    totalGoldStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(totalGoldStr, FONT_COLOR.DEFAULT)
    totalGoldStr:AddAnchor("BOTTOMLEFT", yesterdayGoldStr, 0, 20)
    fishingWindow.totalGoldStr = totalGoldStr

    local totalPacksStr = fishingWindow:CreateChildWidget("label", "totalPacksStr", 0, true)
    totalPacksStr.style:SetFontSize(FONT_SIZE.LARGE)
    totalPacksStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(totalPacksStr, FONT_COLOR.DEFAULT)
    totalPacksStr:AddAnchor("BOTTOMLEFT", totalGoldStr, 0, 20)
    fishingWindow.totalPacksStr = totalPacksStr

    local favouritePackStr = fishingWindow:CreateChildWidget("label", "favouritePackStr", 0, true)
    favouritePackStr.style:SetFontSize(FONT_SIZE.LARGE)
    favouritePackStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(favouritePackStr, FONT_COLOR.DEFAULT)
    favouritePackStr:AddAnchor("BOTTOMLEFT", totalPacksStr, 0, 20)
    fishingWindow.favouritePackStr = favouritePackStr

    refreshStatisticsLabels()
    api.On("UPDATE", OnUpdate)
end

local function OnUnload()
    if eluFishingEventWindow then
        api.Interface:Free(eluFishingEventWindow)
        eluFishingEventWindow = nil
    end
    api.On("UPDATE", function() return end)
end

elu_fishing_addon.OnLoad = OnLoad
elu_fishing_addon.OnUnload = OnUnload

elu_fishing_addon.TestAddFish = function(fishId, goldAmount)
    local coinType = 0
    if currentSession == nil or tonumber(currentSession["packId"]) ~= tonumber(fishId) then 
        if currentSession ~= nil then saveCurrentSessionToFile() end
        startFishTurnInSession(fishId, coinType)
    end 
    addFishToSession(goldAmount, coinType, fishId)
    displayRefreshCounter = DISPLAY_REFRESH_MS
end

return elu_fishing_addon