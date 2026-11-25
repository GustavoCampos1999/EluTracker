local settingsManager = require("Elu_Tracker/settings_manager")
local settings = settingsManager.Settings.lossPornSettings
local SaveSettings = settingsManager.SaveSettings

local api = require("api")

local loss_porn_addon = {
	name = "Regrade Log",
	author = "Michaelqt",
	version = "1.0",
	desc = "See failed regrades from other players in chat."
}

local ui = require("Elu_Tracker/loss_porn_ui")

local lossPornWindow

local LossPornSessionWiped = false

local clockTimer = 0
local clockResetTime = 1000

local ENCHANT_RESULT = {
    BREAK = 0,
    DOWNGRADE = 1,
    FAIL = 2,
    SUCCESS = 3,
    GREATE_SUCCESS = 4
}

local function split(s, delimiter)
    local result = {}
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end

local function getGradeName(gradeId)
    local grades = {
        [0] = "Crude",
        [1] = "Basic",
        [2] = "Grand",
        [3] = "Rare",
        [4] = "Arcane",
        [5] = "Heroic",
        [6] = "Unique",
        [7] = "Celestial",
        [8] = "Divine",
        [9] = "Epic",
        [10] = "Legendary",
        [11] = "Mythic",
        [12] = "Primordial"
    }
    return grades[gradeId] or "Unknown Grade"
end

local function getGradeColor(gradeId)
    local hex = "FFFFFFFF"
    if gradeId == 0 then hex = "FF808080"
    elseif gradeId == 1 then hex = "FFa9a9a9"
    elseif gradeId == 2 then hex = "FFffffff"
    elseif gradeId == 3 then hex = "FF55a62e"
    elseif gradeId == 4 then hex = "FF2593d6"
    elseif gradeId == 5 then hex = "FFc267cd"
    elseif gradeId == 6 then hex = "FFdf8236"
    elseif gradeId == 7 then hex = "FFf95252"
    elseif gradeId == 8 then hex = "FFcf7d5d"
    elseif gradeId == 9 then hex = "FF8fa5ca"
    elseif gradeId == 10 then hex = "FFbf7900"
    elseif gradeId == 11 then hex = "FFc90b0b"
    elseif gradeId == 12 then hex = "FFc90b0b"
    end
    return "|c" .. hex
end

local function itemIdFromItemLinkText(itemLinkText)
    if type(itemLinkText) ~= "string" then return nil end
    local matched = string.match(itemLinkText, "^|i(%d+)") or string.match(itemLinkText, "(%d+)")
    if matched then
        return matched
    end
    local itemIdStr = string.sub(itemLinkText, 3)
    itemIdStr = split(itemIdStr, ",")
    itemIdStr = itemIdStr[1]
    return itemIdStr
end 

local function getTimeString()
    local success, t = pcall(function() return os.date("%H:%M:%S") end)
    if success and type(t) == "string" then
        return t
    end
    if api.Time and api.Time.GetLocalTime and api.Time.TimeToDate then
        local rawTime = api.Time:GetLocalTime()
        if rawTime then
            local strTime = type(rawTime) == "number" and string.format("%.0f", rawTime) or tostring(rawTime)
            local success2, d = pcall(function() return api.Time:TimeToDate(strTime) end)
            if success2 and d and type(d) == "table" then
                return string.format("%02d:%02d:%02d", tonumber(d.hour) or 0, tonumber(d.minute) or 0, tonumber(d.second) or 0)
            end
        end
    end
    return "00:00:00"
end

local function OnUpdate(dt)
end 

settingsManager._lossPornRuntime = settingsManager._lossPornRuntime or {}
local sharedRuntime = settingsManager._lossPornRuntime
local lastRegradeEventKey = nil
local lastRegradeEventTime = 0

local function handleRegradeEvent(characterName, resultCode, itemLink, oldGrade, newGrade)
    if type(characterName) ~= "string" or characterName == "" then return end
    if type(itemLink) ~= "string" or itemLink == "" then return end

    resultCode = tonumber(resultCode)
    oldGrade = tonumber(oldGrade)
    newGrade = tonumber(newGrade)
    if resultCode == nil then return end

    local itemId = itemIdFromItemLinkText(itemLink)

    local nowMs = (api.Time and api.Time.GetUiMsec and api.Time:GetUiMsec()) or 0
    local eventKey = tostring(characterName) .. "|" .. tostring(resultCode) .. "|" .. tostring(itemId or itemLink) .. "|" .. tostring(oldGrade) .. "|" .. tostring(newGrade)
    local prevKey = sharedRuntime.lastKey or lastRegradeEventKey
    local prevTime = sharedRuntime.lastTime or lastRegradeEventTime

    if prevKey == eventKey and nowMs > 0 and (nowMs - prevTime) >= 0 and (nowMs - prevTime) < 2000 then
        return
    end
    lastRegradeEventKey = eventKey
    lastRegradeEventTime = nowMs
    sharedRuntime.lastKey = eventKey
    sharedRuntime.lastTime = nowMs

    local msg = ""
    local uiLogMsg1 = ""
    local uiLogMsg2 = ""
    local isSuccess = false
    
    local oldGradeStr = getGradeName(oldGrade) or "Unknown"
    local newGradeStr = getGradeName(newGrade) or "Unknown"
    
    local oldGradeCol = getGradeColor(oldGrade)
    local newGradeCol = getGradeColor(newGrade)
    
    local itemName = "Unknown Item"
    if itemId then
        local success, itemInfo = pcall(function() return api.Item:GetItemInfoByType(tonumber(itemId)) end)
        if success and itemInfo and itemInfo.name then
            itemName = itemInfo.name
        end
    end
    
    local timeStr = getTimeString()
    
    if resultCode == ENCHANT_RESULT.DOWNGRADE then 
        msg = "|cFFFFF8C7" .. characterName .. " failed their regrade, |cFFF8BD47Downgrading|r their " .. itemLink .. " from " .. oldGradeCol .. oldGradeStr .. "|r to " .. newGradeCol .. newGradeStr .. "|r."
        uiLogMsg1 = "|cFF805000[" .. timeStr .. "]|r |cFFF8BD47[DOWNGRADE]|r |cFF805000" .. characterName .. "|r"
        uiLogMsg2 = "-> |cFFF8BD47downgraded|r " .. newGradeCol .. itemName .. " " .. oldGradeCol .. "(" .. oldGradeStr .. " -> |r" .. newGradeCol .. newGradeStr .. ")|r"
    elseif resultCode == ENCHANT_RESULT.BREAK then 
        msg = "|cFFFFF8C7" .. characterName .. " failed their regrade, |cFFFF6060Destroying|r their " .. oldGradeCol .. oldGradeStr .. "|r " .. itemLink .. "."
        uiLogMsg1 = "|cFF805000[" .. timeStr .. "]|r |cFFff4a4a[DESTROYED]|r |cFF805000" .. characterName .. "|r"
        uiLogMsg2 = "-> |cFFFF6060destroyed|r " .. oldGradeCol .. itemName .. " " .. oldGradeCol .. "(" .. oldGradeStr .. ")|r"
    elseif resultCode == ENCHANT_RESULT.FAIL then 
        if oldGrade and oldGrade >= 7 then
            msg = "|cFFFFF8C7" .. characterName .. " failed their regrade, |cFFF8BD47Anchoring|r their " .. oldGradeCol .. oldGradeStr .. "|r " .. itemLink .. " like a complete and total coward."
        else
            msg = "|cFFFFF8C7" .. characterName .. " |cFFF8BD47Failed|r their regrade on " .. oldGradeCol .. oldGradeStr .. "|r " .. itemLink .. "."
        end
        uiLogMsg1 = "|cFF805000[" .. timeStr .. "]|r |cFFffaa00[FAIL]|r |cFF805000" .. characterName .. "|r"
        uiLogMsg2 = "-> |cFFF8BD47failed|r on " .. oldGradeCol .. itemName .. " " .. oldGradeCol .. "(" .. oldGradeStr .. ")|r"
    elseif resultCode == ENCHANT_RESULT.SUCCESS then
        isSuccess = true
        uiLogMsg1 = "|cFF805000[" .. timeStr .. "]|r |cFF00cc00[SUCCESS]|r |cFF805000" .. characterName .. "|r"
        uiLogMsg2 = "-> |cFF6ae858succeeded|r regrading " .. newGradeCol .. itemName .. " " .. oldGradeCol .. "(" .. oldGradeStr .. " -> |r" .. newGradeCol .. newGradeStr .. ")|r"
    elseif resultCode == ENCHANT_RESULT.GREATE_SUCCESS then
        isSuccess = true
        uiLogMsg1 = "|cFF805000[" .. timeStr .. "]|r |cFF32CD32[GREAT SUCCESS]|r |cFF805000" .. characterName .. "|r"
        uiLogMsg2 = "-> |cFF32CD32great success|r on " .. newGradeCol .. itemName .. " " .. oldGradeCol .. "(" .. oldGradeStr .. " -> |r" .. newGradeCol .. newGradeStr .. ")|r"
    end 
    
    if msg ~= "" then
        if settings.chatMode == 2 then
            api.Log:Info(msg)
        elseif settings.chatMode == 3 then
            api.Log:Err(msg)
        end
    end
    
    if uiLogMsg1 ~= "" then
        
        settings.sessionLogs = settings.sessionLogs or {}
        
        if #settings.sessionLogs > 0 and type(settings.sessionLogs[1]) == "string" then
            settings.sessionLogs = {}
        end
        
        table.insert(settings.sessionLogs, 1, {
            line1 = uiLogMsg1,
            line2 = uiLogMsg2,
            isSuccess = isSuccess
        })
        
        while #settings.sessionLogs > 200 do
            table.remove(settings.sessionLogs, #settings.sessionLogs)
        end
        
        ui.RefreshList()
    end
end

local function OnLoad()
    if settings.chatMode == nil and settings.showInChat ~= nil then
        settings.chatMode = settings.showInChat and 2 or 1
        settings.showInChat = nil
        SaveSettings()
    end

    if not LossPornSessionWiped then
        settings.sessionLogs = {}
        LossPornSessionWiped = true
    end

    local myGen = (tonumber(sharedRuntime.gen) or 0) + 1
    sharedRuntime.gen = myGen
    if not lossPornWindow and sharedRuntime.window then
        lossPornWindow = sharedRuntime.window
    end

    if not lossPornWindow then
        lossPornWindow = api.Interface:CreateEmptyWindow("lossPornWnd", "UIParent")
    end
    sharedRuntime.window = lossPornWindow

    pcall(function() lossPornWindow:ReleaseHandler("GRADE_ENCHANT_BROADCAST") end)
    pcall(function() lossPornWindow:ReleaseHandler("GRADE_ENCHANT_RESULT") end)
    pcall(function() lossPornWindow:ReleaseHandler("OnEvent") end)

    function lossPornWindow:OnEvent(event, a1, a2, a3, a4, a5)
        if sharedRuntime.gen ~= myGen then
            return
        end
        if event == "GRADE_ENCHANT_BROADCAST" then
            local args = { a1, a2, a3, a4, a5 }
            if arg ~= nil and a1 == nil and type(arg) == "table" then
                args = arg
            end
            pcall(function() handleRegradeEvent(unpack(args)) end)
        end
    end
    lossPornWindow:SetHandler("OnEvent", lossPornWindow.OnEvent)
    lossPornWindow:RegisterEvent("GRADE_ENCHANT_BROADCAST")
    lossPornWindow:Show(true)
	
    pcall(function()
        if ADDON and ADDON.GetContent and UIC and UIC.SYSTEM_CONFIG_FRAME then
            local configMenu = ADDON:GetContent(UIC.SYSTEM_CONFIG_FRAME)
            if configMenu and configMenu.michaelClient and configMenu.michaelClient.AddAddon then
                configMenu.michaelClient:AddAddon("Regrade Log", function()
                    ui.Toggle()
                end)
            end
        end
    end)

end

local function OnUnload()
    sharedRuntime.gen = (tonumber(sharedRuntime.gen) or 0) + 1
    if lossPornWindow then
        pcall(function() lossPornWindow:SetHandler("OnEvent", function() end) end)
        pcall(function() lossPornWindow:ReleaseHandler("GRADE_ENCHANT_BROADCAST") end)
        pcall(function() lossPornWindow:ReleaseHandler("GRADE_ENCHANT_RESULT") end)
        pcall(function() lossPornWindow:ReleaseHandler("OnEvent") end)
        lossPornWindow:Show(false)
    end

    ui.Destroy()

    pcall(function()
        if ADDON and ADDON.GetContent and UIC and UIC.SYSTEM_CONFIG_FRAME then
            local configMenu = ADDON:GetContent(UIC.SYSTEM_CONFIG_FRAME)
            if configMenu and configMenu.michaelClient and configMenu.michaelClient.addons then
                local entry = configMenu.michaelClient.addons["Regrade Log"]
                if entry then entry:Show(false) end
            end
        end
    end)

end

loss_porn_addon.OnLoad = OnLoad
loss_porn_addon.OnUnload = OnUnload
loss_porn_addon.OnUpdate = OnUpdate
loss_porn_addon.Toggle = function() if ui and ui.Toggle then ui.Toggle() end end

return loss_porn_addon
