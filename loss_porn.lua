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
    if gradeId == 1 then hex = "FFa9a9a9"
    elseif gradeId == 2 then hex = "FFffffff"
    elseif gradeId == 3 then hex = "FF55a62e"
    elseif gradeId == 4 then hex = "FF2593d6"
    elseif gradeId == 5 then hex = "FFc267cd"
    elseif gradeId == 6 then hex = "FFdf8236"
    elseif gradeId == 7 then hex = "FFf95252" -- Celestial
    elseif gradeId == 8 then hex = "FFcf7d5d" -- Divine
    elseif gradeId == 9 then hex = "FF8fa5ca" -- Epic
    elseif gradeId == 10 then hex = "FFbf7900" -- Legendary
    elseif gradeId == 11 then hex = "FFc90b0b" -- Mythic
    elseif gradeId == 12 then hex = "FFc90b0b" -- Primordial
    end
    return "|c" .. hex
end

local function itemIdFromItemLinkText(itemLinkText)
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
        local success2, d = pcall(function() return api.Time:TimeToDate(api.Time:GetLocalTime()) end)
        if success2 and d and type(d) == "table" then
            return string.format("%02d:%02d:%02d", d.hour or 0, d.minute or 0, d.second or 0)
        end
    end
    return "00:00:00"
end

local function OnUpdate(dt)
    if clockTimer + dt > clockResetTime then
		clockTimer = 0
    end 
    clockTimer = clockTimer + dt
end 

local function handleRegradeEvent(characterName, resultCode, itemLink, oldGrade, newGrade)
    resultCode = tonumber(resultCode)
    oldGrade = tonumber(oldGrade)
    newGrade = tonumber(newGrade)

    local msg = ""
    local uiLogMsg1 = ""
    local uiLogMsg2 = ""
    local isSuccess = false
    
    local oldGradeStr = getGradeName(oldGrade) or "Unknown"
    local newGradeStr = getGradeName(newGrade) or "Unknown"
    
    local oldGradeCol = getGradeColor(oldGrade)
    local newGradeCol = getGradeColor(newGrade)
    local itemCol = oldGradeCol
    
    local itemId = itemIdFromItemLinkText(itemLink)
    local itemName = "Unknown Item"
    if itemId then
        local success, itemInfo = pcall(function() return api.Item:GetItemInfoByType(tonumber(itemId)) end)
        if success and itemInfo and itemInfo.name then
            itemName = itemInfo.name
        end
    end
    
    local timeStr = getTimeString()
    
    if resultCode == ENCHANT_RESULT.DOWNGRADE then 
        msg = "|cFFFFF8C7" .. characterName .. " failed their regrade, |cFFF8BD47Downgrading|r their " .. itemLink .. " from |cFFf95252Celestial|r to |cFFc267cdArcane|r"
        uiLogMsg1 = "|cFF805000[" .. timeStr .. "]|r |cFF00cc00[DOWNGRADE]|r |cFF805000" .. characterName .. "|r"
        uiLogMsg2 = "-> |cFFF8BD47downgraded|r " .. newGradeCol .. itemName .. " " .. oldGradeCol .. "(" .. oldGradeStr .. " -> |r" .. newGradeCol .. newGradeStr .. ")|r"
    elseif resultCode == ENCHANT_RESULT.BREAK then 
        msg = "|cFFFFF8C7" .. characterName .. " failed their regrade, |cFFFF6060Destroying|r their " .. itemLink
        uiLogMsg1 = "|cFF805000[" .. timeStr .. "]|r |cFFff4a4a[DESTROYED]|r |cFF805000" .. characterName .. "|r"
        uiLogMsg2 = "-> |cFFFF6060destroyed|r " .. oldGradeCol .. itemName .. " " .. oldGradeCol .. "(" .. oldGradeStr .. ")|r"
    elseif resultCode == ENCHANT_RESULT.FAIL then 
        msg = "|cFFFFF8C7" .. characterName .. " failed their regrade, |cFFF8BD47Anchoring|r their " .. itemLink .. " like a complete and total coward."
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
        
        if settings.showInChat == true then
            api.Log:Info(msg)
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
        
        SaveSettings()
        ui.RefreshList()
    end
end

local function OnLoad()
	
    
    if not LossPornSessionWiped then
        settings.sessionLogs = {}
        SaveSettings()
        LossPornSessionWiped = true
    end

    if ui and ui.Initialize then
        ui.Initialize()
    end
    
    lossPornWindow = api.Interface:CreateEmptyWindow("lossPornWnd", "UIParent")

    function lossPornWindow:OnEvent(event, ...)
        if event == "GRADE_ENCHANT_BROADCAST" then
            local msgArgs = arg or {...}
            pcall(function() handleRegradeEvent(unpack(msgArgs)) end)
        end
    end
    lossPornWindow:SetHandler("OnEvent", lossPornWindow.OnEvent)
    lossPornWindow:RegisterEvent("GRADE_ENCHANT_BROADCAST")
	
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
    if lossPornWindow then
        lossPornWindow:ReleaseHandler("OnEvent")
        lossPornWindow:Show(false)
        pcall(function() api.Interface:Free(lossPornWindow) end)
        lossPornWindow = nil
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

	-- CHAT_MESSAGE/UPDATE are dispatched centrally; nothing to unregister here.
end

loss_porn_addon.OnLoad = OnLoad
loss_porn_addon.OnUnload = OnUnload
loss_porn_addon.OnUpdate = OnUpdate
loss_porn_addon.Toggle = function() if ui and ui.Toggle then ui.Toggle() end end


return loss_porn_addon
