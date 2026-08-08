local DEBUG = true
local function DebugLog(msg)
    if DEBUG and api.Log then api.Log:Info('[EluInvite] ' .. tostring(msg)) end
end

local settingsManager = require('Elu_Tracker/settings_manager')
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local api = require("api")

local raid_invite = {}

-- State
local state = {
    keyword = "x elu",
    isActive = false,
    autoInvitePublic = true,
    whitelistMode = false,
    giveleadMode = true,
    floatingIconPos = {0, 100},
    showFloatingIcon = true,
    floatingIconScale = 100,
    floatingIconAlpha = 100,
    whitelist = {},
    blacklist = {},
    canvas_width = 0,
    isSidePanelOpen = false
}

local widgets = {}

local MSG_PREFIX = "[Elu Auto Invite] "

local function LogInfo(msg) api.Log:Info(MSG_PREFIX .. msg) end
local function LogErr(msg) api.Log:Err(MSG_PREFIX .. msg) end

local function LoadSettings()
    local data = EluTrackerSettings.raidInvite
    if type(data) == "table" then
        if data.keyword ~= nil then state.keyword = data.keyword end
        if data.isActive ~= nil then state.isActive = data.isActive end
        if data.autoInvitePublic ~= nil then state.autoInvitePublic = data.autoInvitePublic end
        if data.whitelistMode ~= nil then state.whitelistMode = data.whitelistMode end
        if data.giveleadMode ~= nil then state.giveleadMode = data.giveleadMode end
        if data.whitelist ~= nil then state.whitelist = data.whitelist end
        if data.blacklist ~= nil then state.blacklist = data.blacklist end
        if data.floatingIconPos ~= nil then state.floatingIconPos = data.floatingIconPos end
        if data.showFloatingIcon ~= nil then state.showFloatingIcon = data.showFloatingIcon end
        if data.floatingIconScale ~= nil then state.floatingIconScale = data.floatingIconScale end
        if data.floatingIconAlpha ~= nil then state.floatingIconAlpha = data.floatingIconAlpha end
    end
end

local function SaveSettings()
    local data = {
        keyword = state.keyword,
        isActive = state.isActive,
        autoInvitePublic = state.autoInvitePublic,
        whitelistMode = state.whitelistMode,
        giveleadMode = state.giveleadMode,
        whitelist = state.whitelist,
        blacklist = state.blacklist,
        floatingIconPos = state.floatingIconPos,
        showFloatingIcon = state.showFloatingIcon,
        floatingIconScale = state.floatingIconScale,
        floatingIconAlpha = state.floatingIconAlpha
    }
    EluTrackerSettings.raidInvite = data
    SaveEluTrackerSettings()
end

-- Chat Handling
local function IsBlacklisted(name)
    local lName = string.lower(name)
    for _, v in ipairs(state.blacklist) do
        if string.lower(v) == lName then return true end
    end
    return false
end

local function IsWhitelisted(name)
    local lName = string.lower(name)
    for _, v in ipairs(state.whitelist) do
        if string.lower(v) == lName then return true end
    end
    return false
end

local function FormatName(name)
    if type(name) ~= "string" then return "" end
    local text = tostring(name or ""):gsub("^%s*(.-)%s*$", "%1")
    if text == "" then return "" end
    return string.upper(string.sub(text, 1, 1)) .. string.lower(string.sub(text, 2))
end

local function OnChatMessage(channelId, speakerId, _, speakerName, message)
    if not state.isActive then return end
    if not state.isActive or not speakerName or speakerName == "" then return end
    
    local myName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))
    if speakerName == myName then return end
    
    local msgLower = string.lower(message)
    local keywordLower = string.lower(state.keyword)
    
    -- Check x givelead
    if state.giveleadMode and (msgLower == "x givelead" or msgLower == keywordLower .. " givelead") then
        local formattedSpeaker = FormatName(speakerName)
        if not state.whitelistMode or IsWhitelisted(formattedSpeaker) then
            LogInfo("Giving leadership to " .. formattedSpeaker)
            local raidNum = nil
            pcall(function()
                raidNum = api.Team:GetMemberIndexByName(formattedSpeaker)
            end)
            if raidNum ~= nil then
                pcall(function() api.Team:MakeTeamOwner("team" .. tostring(raidNum)) end)
            end
            return
        end
    end
    
    if msgLower ~= keywordLower then return end
    if IsBlacklisted(speakerName) then return end
    
    -- Channel check
    -- Chat channels: 7 = Guild, 9 = Family (typically), -3 = Whisper (typically).
    -- Using generalized identifiers based on standard addon frameworks:
    local isGuild = (channelId == 7 or channelId == CHAT_CHANNEL_GUILD)
    local isFamily = (channelId == 9 or channelId == CHAT_CHANNEL_FAMILY)
    local isWhisper = (channelId == -3 or channelId == CHAT_CHANNEL_WHISPER)
    local isPublic = not isGuild and not isFamily and not isWhisper
    
    local allowed = false
    if isWhisper then allowed = true end
    if isGuild then allowed = true end
    if isFamily then allowed = true end
    if isPublic and state.autoInvitePublic then allowed = true end
    
    if not allowed then return end
    
    if state.whitelistMode and isPublic and not IsWhitelisted(speakerName) then
        return -- Only whitelisted can be invited in public chat if whitelist mode is ON
    end
    
    -- Check if already in raid
    local existingMemberIndex = api.Team:GetMemberIndexByName(speakerName)
    if not existingMemberIndex then
        LogInfo("Inviting " .. speakerName)
        DebugLog("Inviting player: " .. tostring(speakerName))
        api.Team:InviteToTeam(speakerName, false)
    end
end

-- UI
local function UpdateFloatingIcon()
    if widgets.floatingIcon then
        widgets.floatingIcon:Show(state.showFloatingIcon)
        widgets.floatingIcon:SetExtent(55, 40)
        
        if widgets.fBgOn and widgets.fBgOff then
            widgets.fBgOn:SetExtent(55, 40)
            widgets.fBgOff:SetExtent(55, 40)
            widgets.fBgOn:SetVisible(state.isActive)
            widgets.fBgOff:SetVisible(not state.isActive)
        end
    end
end

local function ToggleActive()
    state.isActive = not state.isActive
    SaveSettings()
    UpdateFloatingIcon()
    
    if widgets.toggleBtn then
        widgets.toggleBtn:SetText(state.isActive and "Turn OFF" or "Turn ON")
    end
    
    if widgets.statusLbl then
        if state.isActive then
            widgets.statusLbl:SetText("[ON]")
            ApplyTextColor(widgets.statusLbl, {0, 1, 0, 1})
        else
            widgets.statusLbl:SetText("[OFF]")
            ApplyTextColor(widgets.statusLbl, {1, 0, 0, 1})
        end
    end
    
    if widgets.toggleSideBtn then
        -- This is the button on the Raid Manager. Just says "Elu Auto Invite"
        widgets.toggleSideBtn:SetText("Elu Auto Invite")
    end
    
    LogInfo("Auto Invite is now " .. (state.isActive and "ON" or "OFF"))
end

local function BuildSidePanel(parent)
    local panel = parent:CreateChildWidget("emptywidget", "eluRaidSidePanel", 0, true)
    panel:SetExtent(260, 375)
    panel:AddAnchor("TOPLEFT", parent, "TOPRIGHT", 5, 0)
    panel:Show(false)
    widgets.sidePanel = panel
    
    local bg = panel:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.9)
    bg:AddAnchor("TOPLEFT", panel, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", panel, 0, 0)
    
    local title = panel:CreateChildWidget("label", "title", 0, true)
    title:SetText("Elu Auto Invite")
    title:SetExtent(200, 20)
    title:AddAnchor("TOP", panel, 0, 15)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    
    local statusLbl = panel:CreateChildWidget("label", "statusLbl", 0, true)
    statusLbl:SetExtent(200, 20)
    statusLbl:AddAnchor("TOP", title, "BOTTOM", 0, 5)
    if state.isActive then
        statusLbl:SetText("[ON]")
        ApplyTextColor(statusLbl, {0, 1, 0, 1})
    else
        statusLbl:SetText("[OFF]")
        ApplyTextColor(statusLbl, {1, 0, 0, 1})
    end
    widgets.statusLbl = statusLbl
    
    widgets.toggleBtn = panel:CreateChildWidget("button", "toggleBtn", 0, true)
    widgets.toggleBtn:SetExtent(120, 32)
    widgets.toggleBtn:AddAnchor("TOP", statusLbl, "BOTTOM", 0, 5)
    widgets.toggleBtn:SetText(state.isActive and "Turn OFF" or "Turn ON")
    api.Interface:ApplyButtonSkin(widgets.toggleBtn, BUTTON_BASIC.DEFAULT)
    widgets.toggleBtn:SetHandler("OnClick", ToggleActive)
    
    local kwLabel = panel:CreateChildWidget("label", "kwLabel", 0, true)
    kwLabel:SetText("Keyword:")
    kwLabel:SetExtent(60, 20)
    kwLabel:AddAnchor("TOPLEFT", panel, 20, 110)
    ApplyTextColor(kwLabel, FONT_COLOR.DEFAULT)
    
    local kwInput = W_CTRL.CreateEdit("kwInput", panel)
    kwInput:SetExtent(125, 25)
    kwInput:AddAnchor("LEFT", kwLabel, "RIGHT", 10, 0)
    kwInput:SetText(state.keyword)
    kwInput:SetHandler("OnTextChanged", function() 
        state.keyword = kwInput:GetText()
        SaveSettings()
    end)
    widgets.kwInput = kwInput
    
    -- Checkboxes
    local function CreateCheckbox(id, text, yOffset, stateKey)
        local cb = panel:CreateChildWidget("checkbutton", id, 0, true)
        cb:SetExtent(18, 17)
        cb:AddAnchor("TOPLEFT", panel, 20, yOffset)
        
        local bg1 = cb:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg1:SetExtent(18, 17)
        bg1:AddAnchor("CENTER", cb, 0, 0)
        bg1:SetCoords(0, 0, 18, 17)
        cb:SetNormalBackground(bg1)
        
        local bg2 = cb:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg2:SetExtent(18, 17)
        bg2:AddAnchor("CENTER", cb, 0, 0)
        bg2:SetCoords(18, 0, 18, 17)
        cb:SetCheckedBackground(bg2)
        
        local lbl = panel:CreateChildWidget("label", id.."Lbl", 0, true)
        lbl:SetExtent(200, 20)
        lbl:SetText(text)
        lbl:AddAnchor("LEFT", cb, "RIGHT", 5, 0)
        ApplyTextColor(lbl, FONT_COLOR.DEFAULT)
        
        cb:SetChecked(state[stateKey], false)
        cb:SetHandler("OnCheckChanged", function()
            state[stateKey] = cb:GetChecked()
            SaveSettings()
        end)
    end
    
    
    
    
    CreateCheckbox("cbPublic", "Enable Public Chats", 150, "autoInvitePublic")
    CreateCheckbox("cbWhite", "Whitelist Mode", 180, "whitelistMode")
    CreateCheckbox("cbGive", "Enable 'x givelead'", 210, "giveleadMode")
    
    -- Floating Icon Settings
    local line1 = panel:CreateChildWidget("label", "line1", 0, true)
    line1:SetText("----------------------------------")
    line1:AddAnchor("TOP", panel, 0, 240)
    ApplyTextColor(line1, FONT_COLOR.DEFAULT)

    CreateCheckbox("cbIcon", "Show Floating Icon", 255, "showFloatingIcon")
    widgets.cbIcon = panel.cbIcon
    widgets.cbIcon:SetHandler("OnCheckChanged", function()
        state.showFloatingIcon = widgets.cbIcon:GetChecked()
        SaveSettings()
        UpdateFloatingIcon()
    end)
    
    
    
    
    
                
    -- Lists Management
    -- Blacklist
    local blBtn = panel:CreateChildWidget("button", "blBtn", 0, true)
    blBtn:SetExtent(210, 30)
    blBtn:AddAnchor("TOP", panel, 0, 295)
    blBtn:SetText("Manage Blacklist")
    api.Interface:ApplyButtonSkin(blBtn, BUTTON_BASIC.DEFAULT)
    
    -- Whitelist
    local wlBtn = panel:CreateChildWidget("button", "wlBtn", 0, true)
    wlBtn:SetExtent(210, 30)
    wlBtn:AddAnchor("TOP", blBtn, "BOTTOM", 0, 5)
    wlBtn:SetText("Manage Whitelist")
    api.Interface:ApplyButtonSkin(wlBtn, BUTTON_BASIC.DEFAULT)
    
            local tooltipIdCounter = 0
    local function AddTooltip(widget, text)
        tooltipIdCounter = tooltipIdCounter + 1
        local tooltip = api.Interface:CreateWidget("emptywidget", "eluTooltip_" .. tostring(math.random(10000, 99999)) .. "_" .. tostring(tooltipIdCounter), "UIParent")
        tooltip:SetExtent(280, 80)
        tooltip:AddAnchor("BOTTOM", widget, "TOP", 0, -5)
        tooltip:Show(false)
        
        local bg = tooltip:CreateNinePartDrawable("ui/common_new/default.dds", "background")
        bg:SetTextureInfo("tooltip")
        bg:AddAnchor("TOPLEFT", tooltip, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", tooltip, 0, 0)
        bg:SetColor(1, 1, 1, 0.95)
        
        local lbl = tooltip:CreateChildWidget("textbox", "lbl", 0, true)
        lbl:AddAnchor("TOPLEFT", tooltip, 10, 10)
        lbl:AddAnchor("BOTTOMRIGHT", tooltip, -10, -10)
        lbl.style:SetAlign(ALIGN_LEFT)
        lbl.style:SetFontSize(14)
        lbl:SetAutoWordwrap(true)
        lbl:SetText(text)
        ApplyTextColor(lbl, {1, 1, 1, 1}) -- White text for tooltip
        
        widget:SetHandler("OnEnter", function()
            tooltip:Show(true)
            tooltip:Raise()
        end)
        widget:SetHandler("OnLeave", function()
            tooltip:Show(false)
        end)
    end

    local function ToggleListWindow(isWhite)
        local wnd = widgets.listWindow
        if not wnd then
            wnd = api.Interface:CreateWindow("eluRList_" .. tostring(math.random(10000, 99999)), "Manage List", 0, 0)
            wnd:SetExtent(420, 460)
            wnd:AddAnchor("CENTER", "UIParent", 0, 0)
            wnd.isWhite = isWhite
            wnd.page = 1
            widgets.listWindow = wnd
            
            local instructions = wnd:CreateChildWidget("label", "instructions", 0, true)
            instructions:SetExtent(380, 20)
            instructions:AddAnchor("TOP", wnd, 0, 50)
            instructions.style:SetAlign(ALIGN_CENTER)
            ApplyTextColor(instructions, FONT_COLOR.MIDDLE_TITLE)
            wnd.instructions = instructions
            
            local player_label = wnd:CreateChildWidget("label", "player_label", 0, true)
            player_label:SetText("Player Name:")
            player_label:SetExtent(100, 20)
            player_label:AddAnchor("TOP", wnd, 0, 80)
            player_label.style:SetAlign(ALIGN_CENTER)
            ApplyTextColor(player_label, FONT_COLOR.MIDDLE_TITLE)
            
            local input = W_CTRL.CreateEdit("listInput", wnd)
            input:SetExtent(200, 30)
            input:AddAnchor("TOP", wnd, -55, 110)
            wnd.input = input
            
            local addBtn = wnd:CreateChildWidget("button", "addBtn", 0, true)
            addBtn:SetExtent(100, 30)
            addBtn:AddAnchor("LEFT", input, "RIGHT", 10, 0)
            addBtn:SetText("Add Player")
            api.Interface:ApplyButtonSkin(addBtn, BUTTON_BASIC.DEFAULT)
            
            local list_label = wnd:CreateChildWidget("label", "list_label", 0, true)
            list_label:SetExtent(300, 20)
            list_label:AddAnchor("TOP", wnd, 0, 160)
            list_label.style:SetAlign(ALIGN_CENTER)
            ApplyTextColor(list_label, FONT_COLOR.MIDDLE_TITLE)
            wnd.list_label = list_label
            
            wnd.rowWidgets = {}
            for i = 1, 5 do
                local row = wnd:CreateChildWidget("emptywidget", "row"..i, 0, true)
                row:SetExtent(340, 25)
                row:AddAnchor("TOP", wnd, 0, 190 + (i-1)*35)
                
                local lbl = row:CreateChildWidget("label", "lbl", 0, true)
                lbl:SetExtent(240, 25)
                lbl:AddAnchor("LEFT", row, 0, 0)
                lbl.style:SetAlign(ALIGN_LEFT)
                ApplyTextColor(lbl, FONT_COLOR.MIDDLE_TITLE)
                row.lbl = lbl
                
                local removeBtn = row:CreateChildWidget("button", "removeBtn", 0, true)
                removeBtn:SetExtent(80, 25)
                removeBtn:AddAnchor("RIGHT", row, 0, 0)
                removeBtn:SetText("Remove")
                api.Interface:ApplyButtonSkin(removeBtn, BUTTON_BASIC.DEFAULT)
                
                removeBtn:SetHandler("OnClick", function()
                    local t = wnd.isWhite and state.whitelist or state.blacklist
                    if row.dataIndex and t[row.dataIndex] then
                        table.remove(t, row.dataIndex)
                        SaveSettings()
                        wnd.RefreshList()
                    end
                end)
                
                wnd.rowWidgets[i] = row
            end
            
            local pageLbl = wnd:CreateChildWidget("label", "pageLbl", 0, true)
            pageLbl:SetExtent(80, 25)
            pageLbl:AddAnchor("TOP", wnd, 0, 375)
            pageLbl.style:SetAlign(ALIGN_CENTER)
            ApplyTextColor(pageLbl, FONT_COLOR.MIDDLE_TITLE)
            wnd.pageLbl = pageLbl

            local prevBtn = wnd:CreateChildWidget("button", "prevBtn", 0, true)
            prevBtn:SetExtent(30, 25)
            prevBtn:AddAnchor("RIGHT", pageLbl, "LEFT", -10, 0)
            prevBtn:SetText("<")
            api.Interface:ApplyButtonSkin(prevBtn, BUTTON_BASIC.DEFAULT)
            prevBtn:SetHandler("OnClick", function()
                if wnd.page > 1 then
                    wnd.page = wnd.page - 1
                    wnd.RefreshList()
                end
            end)

            local nextBtn = wnd:CreateChildWidget("button", "nextBtn", 0, true)
            nextBtn:SetExtent(30, 25)
            nextBtn:AddAnchor("LEFT", pageLbl, "RIGHT", 10, 0)
            nextBtn:SetText(">")
            api.Interface:ApplyButtonSkin(nextBtn, BUTTON_BASIC.DEFAULT)
            nextBtn:SetHandler("OnClick", function()
                local t = wnd.isWhite and state.whitelist or state.blacklist
                local maxPage = math.ceil(#t / 5)
                if wnd.page < maxPage then
                    wnd.page = wnd.page + 1
                    wnd.RefreshList()
                end
            end)
            
            local exportBtn = wnd:CreateChildWidget("button", "exportBtn", 0, true)
            exportBtn:SetExtent(90, 30)
            exportBtn:SetText("Export")
            api.Interface:ApplyButtonSkin(exportBtn, BUTTON_BASIC.DEFAULT)
            AddTooltip(exportBtn, "Writes the list you are using to \nElu_Tracker/whitelist.txt \nSend that file to a friend as-is - they can import it without renaming.")
            
            local importBtn = wnd:CreateChildWidget("button", "importBtn", 0, true)
            importBtn:SetExtent(90, 30)
            importBtn:SetText("Import")
            api.Interface:ApplyButtonSkin(importBtn, BUTTON_BASIC.DEFAULT)
            AddTooltip(importBtn, "Reads a shared list from \nElu_Tracker/whitelist.txt \nand adds it to the list you are using. Only adds - it never removes names.")
            
            exportBtn:SetHandler("OnClick", function()
                local content = table.concat(state.whitelist, ",")
                local ok = pcall(function() api.File:Write("Elu_Tracker/whitelist.txt", content) end)
                if ok then LogInfo("Whitelist exported successfully to Elu_Tracker/whitelist.txt") else LogInfo("Failed to export Whitelist") end
            end)
            
            importBtn:SetHandler("OnClick", function()
                local readOk, content = pcall(function() return api.File:Read("Elu_Tracker/whitelist.txt") end)
                if readOk and type(content) == "string" and content ~= "" then
                    local count = 0
                    for name in string.gmatch(content, '([^,]+)') do
                        local n = name:gsub("^%s*(.-)%s*$", "%1")
                        if n ~= "" then
                            local found = false
                            for _, v in ipairs(state.whitelist) do
                                if string.lower(v) == string.lower(n) then found = true break end
                            end
                            if not found and #state.whitelist < 100 then
                                table.insert(state.whitelist, n)
                                count = count + 1
                            end
                        end
                    end
                    SaveSettings()
                    wnd.RefreshList()
                    LogInfo("Imported " .. tostring(count) .. " new names from whitelist.txt")
                else
                    LogInfo("Could not read Elu_Tracker/whitelist.txt")
                end
            end)
            
            wnd.exportBtn = exportBtn
            wnd.importBtn = importBtn

            local addRaidBtn = wnd:CreateChildWidget("button", "addRaidBtn", 0, true)
            addRaidBtn:SetExtent(90, 30)
            addRaidBtn:SetText("Add Raid")
            api.Interface:ApplyButtonSkin(addRaidBtn, BUTTON_BASIC.DEFAULT)
            addRaidBtn:SetHandler("OnClick", function()
                if not wnd.isWhite then return end
                for i = 1, 50 do
                    local name = api.Team:GetMemberName("team" .. tostring(i))
                    if name and name ~= "" then
                        local myName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))
                        if name ~= myName then
                            local found = false
                            for _, v in ipairs(state.whitelist) do
                                if string.lower(v) == string.lower(name) then found = true break end
                            end
                            if not found and #state.whitelist < 100 then
                                table.insert(state.whitelist, name)
                            end
                        end
                    end
                end
                SaveSettings()
                wnd.RefreshList()
            end)
            wnd.addRaidBtn = addRaidBtn
            
            local function RefreshList()
                local t = wnd.isWhite and state.whitelist or state.blacklist
                local maxPage = math.ceil(#t / 5)
                if maxPage < 1 then maxPage = 1 end
                if wnd.page > maxPage then wnd.page = maxPage end
                
                wnd.pageLbl:SetText(tostring(wnd.page) .. " / " .. tostring(maxPage))
                
                for i = 1, 5 do
                    local dataIndex = (wnd.page - 1) * 5 + i
                    if t[dataIndex] then
                        wnd.rowWidgets[i]:Show(true)
                        wnd.rowWidgets[i].lbl:SetText(t[dataIndex])
                        wnd.rowWidgets[i].dataIndex = dataIndex
                    else
                        wnd.rowWidgets[i]:Show(false)
                        wnd.rowWidgets[i].dataIndex = nil
                    end
                end
                
                if wnd.isWhite then
                    wnd.importBtn:RemoveAllAnchors()
                    wnd.importBtn:AddAnchor("BOTTOM", wnd, 0, -20)
                    wnd.exportBtn:RemoveAllAnchors()
                    wnd.exportBtn:AddAnchor("RIGHT", wnd.importBtn, "LEFT", -10, 0)
                    wnd.addRaidBtn:RemoveAllAnchors()
                    wnd.addRaidBtn:AddAnchor("LEFT", wnd.importBtn, "RIGHT", 10, 0)
                    wnd.exportBtn:Show(true)
                    wnd.importBtn:Show(true)
                    wnd.addRaidBtn:Show(true)
                else
                    wnd.exportBtn:Show(false)
                    wnd.importBtn:Show(false)
                    wnd.addRaidBtn:Show(false)
                end
            end
            wnd.RefreshList = RefreshList
            
            addBtn:SetHandler("OnClick", function()
                local n = input:GetText()
                if not n or n == "" then return end
                local t = wnd.isWhite and state.whitelist or state.blacklist
                if #t >= 100 then return end -- Max 100 items
                for _, v in ipairs(t) do
                    if string.lower(v) == string.lower(n) then return end
                end
                table.insert(t, n)
                SaveSettings()
                RefreshList()
                input:SetText("")
            end)
            
            local function OnClose()
                wnd:Show(false)
            end
            wnd.titleBar.closeButton:SetHandler("OnClick", OnClose)
        end
        wnd.isWhite = isWhite
        wnd.page = 1
        wnd:SetTitle(isWhite and "Whitelist Manager" or "Blacklist Manager")
        wnd.instructions:SetText(isWhite and "Add players to automatically invite them" or "Add players to prevent raid invites")
        wnd.list_label:SetText(isWhite and "Current Whitelist:" or "Current Blacklist:")
        wnd.RefreshList()
        wnd:Show(true)
        wnd:Raise()
    end
    
    blBtn:SetHandler("OnClick", function() ToggleListWindow(false) end)
    wlBtn:SetHandler("OnClick", function() ToggleListWindow(true) end)
end

function raid_invite.OnLoad()
    LoadSettings()
    
    local raid_manager = ADDON:GetContent(UIC.RAID_MANAGER)
    if not raid_manager then return end
    state.canvas_width = raid_manager:GetWidth()
    widgets.raid_manager = raid_manager
    
    local toggleSideBtn = raid_manager:CreateChildWidget("button", "eluRaidSideBtn", 0, true)
    toggleSideBtn:SetExtent(130, 30)
    toggleSideBtn:AddAnchor("BOTTOMRIGHT", raid_manager, "TOPRIGHT", -15, -5)
    toggleSideBtn:SetText("Elu Auto Invite")
    api.Interface:ApplyButtonSkin(toggleSideBtn, BUTTON_BASIC.DEFAULT)
    
    toggleSideBtn:SetHandler("OnClick", function()
        state.isSidePanelOpen = not state.isSidePanelOpen
        if not widgets.sidePanel then
            BuildSidePanel(raid_manager)
        end
        widgets.sidePanel:Show(state.isSidePanelOpen)
    end)
    widgets.toggleSideBtn = toggleSideBtn
    
    local fIcon = api.Interface:CreateEmptyWindow("eluRaidFloatingIcon", "UIParent")
    fIcon:SetExtent(55, 40)
    fIcon:AddAnchor("TOPLEFT", "UIParent", state.floatingIconPos[1], state.floatingIconPos[2])
    fIcon:Show(state.showFloatingIcon)
    
    local fBgOn = fIcon:CreateImageDrawable("Addon/Elu_Tracker/auto_on.png", "background")
    fBgOn:SetExtent(55, 40)
    fBgOn:AddAnchor("CENTER", fIcon, 0, 0)
    fBgOn:SetColor(1, 1, 1, 0.7)
    fBgOn:SetVisible(state.isActive)
    
    local fBgOff = fIcon:CreateImageDrawable("Addon/Elu_Tracker/auto_off.png", "background")
    fBgOff:SetExtent(55, 40)
    fBgOff:AddAnchor("CENTER", fIcon, 0, 0)
    fBgOff:SetColor(1, 1, 1, 0.7)
    fBgOff:SetVisible(not state.isActive)

    widgets.fBgOn = fBgOn
    widgets.fBgOff = fBgOff
    
    fIcon:EnableDrag(true)
    fIcon:SetHandler("OnDragStart", function() 
        if api.Input:IsShiftKeyDown() then fIcon:StartMoving() end 
    end)
    fIcon:SetHandler("OnDragStop", function() 
        fIcon:StopMovingOrSizing() 
        local x, y = fIcon:GetOffset()
        state.floatingIconPos = {x, y}
        SaveSettings()
    end)
    
    local clickOverlay = fIcon:CreateChildWidget("button", "clickOverlay", 0, true)
    clickOverlay:AddAnchor("TOPLEFT", fIcon, 0, 0)
    clickOverlay:AddAnchor("BOTTOMRIGHT", fIcon, 0, 0)
    clickOverlay.style:SetColor(0,0,0,0)
    clickOverlay:SetHandler("OnClick", ToggleActive)
    
    clickOverlay:EnableDrag(true)
    clickOverlay:SetHandler("OnDragStart", function() 
        if api.Input:IsShiftKeyDown() then fIcon:StartMoving() end 
    end)
    clickOverlay:SetHandler("OnDragStop", function() 
        fIcon:StopMovingOrSizing() 
        local x, y = fIcon:GetOffset()
        state.floatingIconPos = {x, y}
        SaveSettings()
    end)
    
    widgets.floatingIcon = fIcon
    UpdateFloatingIcon()
    
    if not raid_invite.isLoaded then
        api.On("CHAT_MESSAGE", OnChatMessage)
        raid_invite.isLoaded = true
    end
end

function raid_invite.OnUnload()
    state.isActive = false
    if widgets.toggleSideBtn then widgets.toggleSideBtn:Show(false) end
    if widgets.sidePanel then widgets.sidePanel:Show(false) end
    if widgets.listWindow then widgets.listWindow:Show(false) end
    if widgets.floatingIcon then widgets.floatingIcon:Show(false) end
end

return raid_invite
