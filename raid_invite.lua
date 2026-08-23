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
    keyword = "",
    inviteMode = 0, -- 0: OFF, 1: ON, 2: WHITELIST
    giveleadMode = true,
    floatingIconPos = {0, 100},
    showFloatingIcon = true,
    floatingIconScale = 100,
    floatingIconAlpha = 100,
    whitelist = {},
    blacklist = {},
    canvas_width = 0,
    isSidePanelOpen = false,
    giveleadWhitelistOnly = false,
    whitelistBypassPrivate = true,
    autoWhitelistRaid = false,
    clearedKeywordV2 = false,
    enhancedIsActive = false,
    enhancedKeyword = "",
    eluFilterMode = 2,
    enhancedFilterMode = 2, fastBlacklist = {}
}

local widgets = {}

local MSG_PREFIX = "[Elu Auto Invite] "

local function LogInfo(msg) api.Log:Info(MSG_PREFIX .. msg) end
local function LogErr(msg) api.Log:Err(MSG_PREFIX .. msg) end

local function LoadSettings()
    local data = EluTrackerSettings.raidInvite
    if type(data) == "table" then
        if data.keyword ~= nil then state.keyword = data.keyword end
        if data.inviteMode ~= nil then 
            state.inviteMode = data.inviteMode 
        elseif data.isActive ~= nil then
            if data.isActive then
                state.inviteMode = data.whitelistMode and 2 or 1
            else
                state.inviteMode = 0
            end
        end
        if data.giveleadMode ~= nil then state.giveleadMode = data.giveleadMode end
        if data.giveleadWhitelistOnly ~= nil then state.giveleadWhitelistOnly = data.giveleadWhitelistOnly end
        if data.whitelistBypassPrivate ~= nil then state.whitelistBypassPrivate = data.whitelistBypassPrivate end
        if data.autoWhitelistRaid ~= nil then state.autoWhitelistRaid = data.autoWhitelistRaid end
        if data.whitelist ~= nil then state.whitelist = data.whitelist end
        if data.blacklist ~= nil then state.blacklist = data.blacklist end
        if data.floatingIconPos ~= nil then state.floatingIconPos = data.floatingIconPos end
        if data.showFloatingIcon ~= nil then state.showFloatingIcon = data.showFloatingIcon end
        if data.floatingIconScale ~= nil then state.floatingIconScale = data.floatingIconScale end
        if data.floatingIconAlpha ~= nil then state.floatingIconAlpha = data.floatingIconAlpha end
        if data.clearedKeywordV2 ~= nil then state.clearedKeywordV2 = data.clearedKeywordV2 end
        if data.eluFilterMode ~= nil then state.eluFilterMode = data.eluFilterMode end
        if data.enhancedFilterMode ~= nil then state.enhancedFilterMode = data.enhancedFilterMode end; if data.fastBlacklist ~= nil then state.fastBlacklist = data.fastBlacklist end
    end
    
    local function SanitizeList(t)
        local clean = {}
        if type(t) == "table" then
            for i=1, #t do
                if type(t[i]) == "string" and t[i] ~= "" then table.insert(clean, t[i]) end
            end
        end
        return clean
    end
    state.whitelist = SanitizeList(state.whitelist)
    state.blacklist = SanitizeList(state.blacklist)
    state.fastBlacklist = SanitizeList(state.fastBlacklist)

    if not state.clearedKeywordV2 then
        state.keyword = ""
        state.clearedKeywordV2 = true
        local ok = pcall(function() SaveSettings() end)
    end
    
    state.inviteMode = 0 -- Always start OFF on relog
end

local function SaveSettings()
    local data = {
        keyword = state.keyword,
        inviteMode = state.inviteMode,
        giveleadMode = state.giveleadMode,
        giveleadWhitelistOnly = state.giveleadWhitelistOnly,
        whitelistBypassPrivate = state.whitelistBypassPrivate,
        autoWhitelistRaid = state.autoWhitelistRaid,
        whitelist = state.whitelist,
        blacklist = state.blacklist,
        floatingIconPos = state.floatingIconPos,
        showFloatingIcon = state.showFloatingIcon,
        floatingIconScale = state.floatingIconScale,
        floatingIconAlpha = state.floatingIconAlpha,
        clearedKeywordV2 = state.clearedKeywordV2,
        eluFilterMode = state.eluFilterMode,
        enhancedFilterMode = state.enhancedFilterMode, fastBlacklist = state.fastBlacklist
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
    if not speakerName or speakerName == "" then return end
    
    local myName = ""
    pcall(function() myName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player")) end)
    if speakerName == myName then return end
    
    local msgLower = string.lower(message)
    local keywordLower = string.lower(state.keyword)
    
    -- Check x givelead
    local giveMode = state.giveleadMode
    if type(giveMode) == "boolean" then
        if giveMode then giveMode = (state.giveleadWhitelistOnly and 3 or 2) else giveMode = 1 end
    end
    
    if giveMode > 1 and (msgLower == "x givelead" or (keywordLower ~= "" and msgLower == keywordLower .. " givelead")) then
        local formattedSpeaker = FormatName(speakerName)
        if giveMode == 2 or (giveMode == 3 and IsWhitelisted(formattedSpeaker)) then
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
    
    if state.enhancedIsActive and state.enhancedKeyword ~= "" then
        local match = false
        if state.enhancedFilterMode == 1 then
            match = (msgLower == string.lower(state.enhancedKeyword))
        else
            match = (string.find(msgLower, string.lower(state.enhancedKeyword), 1, true) ~= nil)
        end
        
        if match then
            if not IsBlacklisted(speakerName) then
                local existingMemberIndex = api.Team:GetMemberIndexByName(speakerName)
                if not existingMemberIndex then
                    LogInfo("Inviting " .. speakerName .. " (Enhanced)")
                    api.Team:InviteToTeam(speakerName, false)
                end
            end
        end
    end
    
    if state.inviteMode == 0 then return end
    if keywordLower == "" then return end
    
    local eluMatch = false
    if state.eluFilterMode == 1 then
        eluMatch = (msgLower == keywordLower)
    else
        eluMatch = (string.find(msgLower, keywordLower, 1, true) ~= nil)
    end
    
    if not eluMatch then return end
    if IsBlacklisted(speakerName) then return end
    
    -- Channel check
    local isGuild = (channelId == 7 or channelId == CHAT_CHANNEL_GUILD)
    local isFamily = (channelId == 9 or channelId == CHAT_CHANNEL_FAMILY)
    local isWhisper = (channelId == -3 or channelId == CHAT_CHANNEL_WHISPER)
    local isPublic = not isGuild and not isFamily and not isWhisper
    
    local allowed = false
    if isWhisper then allowed = true end
    if isGuild then allowed = true end
    if isFamily then allowed = true end
    if isPublic then allowed = true end
    
    if not allowed then return end
    
    if state.inviteMode == 2 then
        local bypass = state.whitelistBypassPrivate and not isPublic
        if not bypass and not IsWhitelisted(speakerName) then
            return -- Only whitelisted can be invited if whitelist mode is ON, unless bypassing private channels
        end
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
        
        if widgets.fBgOn and widgets.fBgOff and widgets.fBgWhite then
            widgets.fBgOn:SetExtent(55, 40)
            widgets.fBgOff:SetExtent(55, 40)
            widgets.fBgWhite:SetExtent(55, 40)
            widgets.fBgOn:SetVisible(state.inviteMode == 1)
            widgets.fBgWhite:SetVisible(state.inviteMode == 2)
            widgets.fBgOff:SetVisible(state.inviteMode == 0)
        end
        
        if widgets.fKeywordLbl then
            if state.inviteMode > 0 and state.keyword ~= "" then
                widgets.fKeywordLbl:SetText(state.keyword)
                widgets.fKeywordLbl:Show(true)
            else
                widgets.fKeywordLbl:Show(false)
            end
        end
    end
end

function raid_invite.StopEnhancedRecruiting()
    state.enhancedIsActive = false
    state.enhancedKeyword = ""
    
    if widgets.enhancedRecruitBtn then
        widgets.enhancedRecruitBtn:SetText("Start Recruiting")
    end
    if widgets.enhancedTextfield then
        widgets.enhancedTextfield:Enable(true)
    end
    if widgets.enhancedCanvas then
        widgets.enhancedCanvas:Show(false)
    end
end

local function GetModeString()
    if state.inviteMode == 1 then return "Turn ON (Whitelist)"
    elseif state.inviteMode == 2 then return "Turn OFF"
    else return "Turn ON" end
end

local function ToggleActive()
    if state.inviteMode == 0 then state.inviteMode = 1
    elseif state.inviteMode == 1 then state.inviteMode = 2
    else state.inviteMode = 0 end
    
    if state.inviteMode > 0 and state.enhancedIsActive then
        raid_invite.StopEnhancedRecruiting()
        
    end
    
    SaveSettings()
    UpdateFloatingIcon()
    
    if widgets.toggleBtn then
        widgets.toggleBtn:SetText(GetModeString())
    end
    
    if widgets.statusLbl then
        if state.inviteMode == 1 then
            widgets.statusLbl:SetText("[ON]")
            ApplyTextColor(widgets.statusLbl, {0, 1, 0, 1})
        elseif state.inviteMode == 2 then
            widgets.statusLbl:SetText("[ON WHITELIST]")
            ApplyTextColor(widgets.statusLbl, {0.3, 0.6, 1, 1})
        else
            widgets.statusLbl:SetText("[OFF]")
            ApplyTextColor(widgets.statusLbl, {1, 0, 0, 1})
        end
    end
    
    if widgets.toggleSideBtn then
        widgets.toggleSideBtn:SetText("Elu Auto Invite")
    end
    
    LogInfo("Auto Invite Mode is now: " .. tostring(state.inviteMode))
end

local function BuildSidePanel(parent)
    local panel = parent:CreateChildWidget("emptywidget", "eluRaidSidePanel", 0, true)
    panel:SetExtent(300, 380)
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
    ApplyTextColor(title, {1, 0.8, 0.2, 1})
    
    local statusLbl = panel:CreateChildWidget("label", "statusLbl", 0, true)
    statusLbl:SetExtent(200, 20)
    statusLbl:AddAnchor("TOP", title, "BOTTOM", 0, 5)
    if state.inviteMode == 1 then
        statusLbl:SetText("[ON]")
        ApplyTextColor(statusLbl, {0, 1, 0, 1})
    elseif state.inviteMode == 2 then
        statusLbl:SetText("[ON WHITELIST]")
        ApplyTextColor(statusLbl, {0.3, 0.6, 1, 1})
    else
        statusLbl:SetText("[OFF]")
        ApplyTextColor(statusLbl, {1, 0, 0, 1})
    end
    widgets.statusLbl = statusLbl
    
    widgets.toggleBtn = panel:CreateChildWidget("button", "toggleBtn", 0, true)
    widgets.toggleBtn:SetExtent(160, 32)
    widgets.toggleBtn:AddAnchor("TOP", statusLbl, "BOTTOM", 0, 5)
    widgets.toggleBtn:SetText(GetModeString())
    api.Interface:ApplyButtonSkin(widgets.toggleBtn, BUTTON_BASIC.DEFAULT)
    widgets.toggleBtn:SetHandler("OnClick", ToggleActive)
    
    local kwLabel = panel:CreateChildWidget("label", "kwLabel", 0, true)
    kwLabel:SetText("Keyword:")
    kwLabel:SetExtent(75, 20)
    kwLabel:AddAnchor("TOPLEFT", panel, 20, 140)
    ApplyTextColor(kwLabel, {1,1,1,1})
    kwLabel.style:SetAlign(ALIGN_LEFT)
    
    local kwInput = W_CTRL.CreateEdit("kwInput", panel)
    kwInput:SetExtent(125, 25)
    kwInput:AddAnchor("LEFT", kwLabel, "RIGHT", 10, 0)
    kwInput:SetText(state.keyword)
    kwInput:SetHandler("OnTextChanged", function() 
        state.keyword = kwInput:GetText()
        SaveSettings()
    end)
    widgets.kwInput = kwInput
    
    local filterLabel = panel:CreateChildWidget("label", "filterLabel", 0, true)
    filterLabel:SetText("Match:")
    filterLabel:SetExtent(75, 20)
    filterLabel:AddAnchor("TOPLEFT", panel, 20, 170)
    ApplyTextColor(filterLabel, {1,1,1,1})
    filterLabel.style:SetAlign(ALIGN_LEFT)
    
    local eluFilterCombo = api.Interface:CreateComboBox(panel)
    eluFilterCombo:SetExtent(125, 25)
    eluFilterCombo:AddAnchor("LEFT", filterLabel, "RIGHT", 10, 0)
    eluFilterCombo.dropdownItem = {"Equals", "Contains"}
    eluFilterCombo:Select(state.eluFilterMode or 2)
    eluFilterCombo:Show(true)
    
    eluFilterCombo:SetHandler("OnSelect", function()
        state.eluFilterMode = eluFilterCombo:GetSelectedIndex()
        SaveSettings()
    end)
    widgets.eluFilterCombo = eluFilterCombo
    
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
        lbl.style:SetAlign(ALIGN_LEFT)
        ApplyTextColor(lbl, {1,1,1,1})
        
        cb:SetChecked(state[stateKey], false)
        cb:SetHandler("OnCheckChanged", function()
            state[stateKey] = cb:GetChecked()
            SaveSettings()
        end)
    end
    
    local giveleadLabel = panel:CreateChildWidget("label", "giveleadLabel", 0, true)
    giveleadLabel:SetText("'x givelead':")
    giveleadLabel:SetExtent(75, 20)
    giveleadLabel:AddAnchor("TOPLEFT", panel, 20, 200)
    ApplyTextColor(giveleadLabel, {1,1,1,1})
    giveleadLabel.style:SetAlign(ALIGN_LEFT)
    
    local giveleadCombo = api.Interface:CreateComboBox(panel)
    giveleadCombo:SetExtent(125, 25)
    giveleadCombo:AddAnchor("LEFT", giveleadLabel, "RIGHT", 10, 0)
    giveleadCombo.dropdownItem = {"Off", "On", "Whitelist Only"}
    
    local giveIdx = 1
    if state.giveleadMode == true then
        if state.giveleadWhitelistOnly then giveIdx = 3 else giveIdx = 2 end
    elseif type(state.giveleadMode) == "number" then
        giveIdx = state.giveleadMode
    end
    giveleadCombo:Select(giveIdx)
    giveleadCombo:Show(true)
    giveleadCombo:SetHandler("OnSelect", function()
        state.giveleadMode = giveleadCombo:GetSelectedIndex()
        SaveSettings()
    end)
    widgets.giveleadCombo = giveleadCombo

    CreateCheckbox("cbWhiteBypass", "Disable Whitelist in Guild/Fam/Whis", 240, "whitelistBypassPrivate")
    
    local blBtn = panel:CreateChildWidget("button", "blBtn", 0, true)
    blBtn:SetExtent(120, 30)
    blBtn:AddAnchor("TOPLEFT", panel, 20, 275)
    blBtn:SetText("Blacklist")
    api.Interface:ApplyButtonSkin(blBtn, BUTTON_BASIC.DEFAULT)
    
    local wlBtn = panel:CreateChildWidget("button", "wlBtn", 0, true)
    wlBtn:SetExtent(120, 30)
    wlBtn:AddAnchor("TOPRIGHT", panel, -20, 275)
    wlBtn:SetText("Whitelist")
    api.Interface:ApplyButtonSkin(wlBtn, BUTTON_BASIC.DEFAULT)

    CreateCheckbox("cbAutoRaid", "Auto-Add Joining Members to Whitelist", 315, "autoWhitelistRaid")
    
    CreateCheckbox("cbIcon", "Show Floating Icon", 110, "showFloatingIcon")
    widgets.cbIcon = panel.cbIcon
    widgets.cbIcon:SetHandler("OnCheckChanged", function()
        state.showFloatingIcon = widgets.cbIcon:GetChecked()
        SaveSettings()
        UpdateFloatingIcon()
    end)
    
    -- Fast Auto Invite UI (below lists management)
    
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

    local function ToggleListWindow(listType)
        local wnd = widgets.listWindow
        if not wnd then
            wnd = api.Interface:CreateWindow("eluRList_" .. tostring(math.random(10000, 99999)), "Manage List", 0, 0)
            wnd:SetExtent(300, 460)
            wnd:AddAnchor("CENTER", "UIParent", 0, 0)
                
    
            
            wnd.listType = listType; wnd.isWhite = (listType == 1)
            wnd.page = 1
            widgets.listWindow = wnd
            
            local instructions = wnd:CreateChildWidget("label", "instructions", 0, true)
            instructions:SetExtent(280, 20)
            instructions:AddAnchor("TOP", wnd, 0, 50)
            instructions.style:SetAlign(ALIGN.CENTER)
            ApplyTextColor(instructions, FONT_COLOR.MIDDLE_TITLE)
            wnd.instructions = instructions
            
            local player_label = wnd:CreateChildWidget("label", "player_label", 0, true)
            player_label:SetText("Player Name:")
            player_label:SetExtent(100, 20)
            player_label:AddAnchor("TOP", wnd, 0, 80)
            player_label.style:SetAlign(ALIGN.CENTER)
            ApplyTextColor(player_label, FONT_COLOR.MIDDLE_TITLE)
            
            local input = W_CTRL.CreateEdit("listInput", wnd)
            input:SetExtent(160, 30)
            input:AddAnchor("TOP", wnd, -45, 110)
            wnd.input = input
            
            local addBtn = wnd:CreateChildWidget("button", "addBtn", 0, true)
            addBtn:SetExtent(80, 30)
            addBtn:AddAnchor("LEFT", input, "RIGHT", 10, 0)
            addBtn:SetText("Add Player")
            api.Interface:ApplyButtonSkin(addBtn, BUTTON_BASIC.DEFAULT)
            
            local list_label = wnd:CreateChildWidget("label", "list_label", 0, true)
            list_label:SetExtent(300, 20)
            list_label:AddAnchor("TOP", wnd, 0, 160)
            list_label.style:SetAlign(ALIGN.CENTER)
            ApplyTextColor(list_label, FONT_COLOR.MIDDLE_TITLE)
            wnd.list_label = list_label
            
            wnd.rowWidgets = {}
            for i = 1, 5 do
                local row = wnd:CreateChildWidget("emptywidget", "row"..i, 0, true)
                row:SetExtent(280, 25)
                row:AddAnchor("TOP", wnd, 0, 190 + (i-1)*35)
                
                local lbl = row:CreateChildWidget("label", "lbl", 0, true)
                lbl:SetExtent(180, 25)
                lbl:AddAnchor("LEFT", row, 0, 0)
                lbl.style:SetAlign(ALIGN_LEFT)
                row.lbl = lbl
                
                local removeBtn = row:CreateChildWidget("button", "removeBtn", 0, true)
                removeBtn:SetExtent(70, 25)
                removeBtn:AddAnchor("RIGHT", row, 0, 0)
                removeBtn:SetText("Remove")
                api.Interface:ApplyButtonSkin(removeBtn, BUTTON_BASIC.DEFAULT)
                
                removeBtn:SetHandler("OnClick", function()
                    local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
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
            pageLbl.style:SetAlign(ALIGN.CENTER)
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
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                local maxPage = math.ceil(#t / 5)
                if wnd.page < maxPage then
                    wnd.page = wnd.page + 1
                    wnd.RefreshList()
                end
            end)
            
            local exportBtn = wnd:CreateChildWidget("button", "exportBtn", 0, true)
            exportBtn:SetExtent(80, 30)
            exportBtn:SetText("Export")
            api.Interface:ApplyButtonSkin(exportBtn, BUTTON_BASIC.DEFAULT)
            AddTooltip(exportBtn, "Writes the list you are using to \na text file. \nSend that file to a friend as-is - they can import it.")
            
            local importBtn = wnd:CreateChildWidget("button", "importBtn", 0, true)
            importBtn:SetExtent(80, 30)
            importBtn:SetText("Import")
            api.Interface:ApplyButtonSkin(importBtn, BUTTON_BASIC.DEFAULT)
            AddTooltip(importBtn, "Reads a shared list from \na text file \nand adds it to the list you are using. Only adds - it never removes names.")
            
            local function ShowExportWindow()
                local expWnd = api.Interface:CreateWindow("eluRExportWnd_"..tostring(math.random(1000, 9999)), "Export Code", 0, 0)
                expWnd:SetExtent(300, 360)
                expWnd:AddAnchor("CENTER", "UIParent", 0, 0)
                
    
                
                
                local inst = expWnd:CreateChildWidget("textbox", "inst", 0, true)
                inst:SetExtent(260, 40)
                inst:AddAnchor("TOP", expWnd, 0, 50)
                inst.style:SetAlign(ALIGN.CENTER)
                ApplyTextColor(inst, FONT_COLOR.DEFAULT)
                inst:SetText("To share: Click the box below, press Ctrl+A, then Ctrl+C, and send it to your friend.")
                
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                local prefix = wnd.isWhite and "WL:" or "BL:"
                
                local input = W_CTRL.CreateMultiLineEdit("exportInput", expWnd)
                input:SetExtent(260, 200)
                input:AddAnchor("TOP", inst, "BOTTOM", 0, 10)
                input:SetMaxTextLength(65535)
                
                local clean_t = {}
                for i = 1, #t do
                    if t[i] ~= nil and tostring(t[i]) ~= "" then
                        table.insert(clean_t, tostring(t[i]))
                    end
                end
                
                local export_str = prefix .. table.concat(clean_t, ",")
                input:SetText(export_str)
                
                local closeBtn = expWnd:CreateChildWidget("button", "closeBtn", 0, true)
                closeBtn:SetExtent(80, 30)
                closeBtn:AddAnchor("BOTTOM", expWnd, 0, -20)
                closeBtn:SetText("Close")
                api.Interface:ApplyButtonSkin(closeBtn, BUTTON_BASIC.DEFAULT)
                closeBtn:SetHandler("OnClick", function() expWnd:Show(false) end)
                
                expWnd.titleBar.closeButton:SetHandler("OnClick", function() expWnd:Show(false) end)
                expWnd:Show(true)
            end

            local function ShowImportWindow()
                local impWnd = api.Interface:CreateWindow("eluRImportWnd_"..tostring(math.random(1000, 9999)), "Import Code", 0, 0)
                impWnd:SetExtent(300, 320)
                impWnd:AddAnchor("CENTER", "UIParent", 0, 0)
                
    
                
                
                local inst = impWnd:CreateChildWidget("textbox", "inst", 0, true)
                inst:SetExtent(260, 40)
                inst:AddAnchor("TOP", impWnd, 0, 50)
                inst.style:SetAlign(ALIGN.CENTER)
                ApplyTextColor(inst, FONT_COLOR.DEFAULT)
                inst:SetText("Paste (Ctrl+V) the code you received from your friend in the box below:")
                
                local input = W_CTRL.CreateMultiLineEdit("importInput", impWnd)
                input:SetExtent(260, 100)
                input:AddAnchor("TOP", inst, "BOTTOM", 0, 10)
                input:SetMaxTextLength(65535)
                
                local importTxtBtn = impWnd:CreateChildWidget("button", "importTxtBtn", 0, true)
                importTxtBtn:SetExtent(120, 30)
                importTxtBtn:AddAnchor("TOP", input, "BOTTOM", 0, 10)
                importTxtBtn:SetText("Import Text")
                api.Interface:ApplyButtonSkin(importTxtBtn, BUTTON_BASIC.DEFAULT)
                
                local orLbl = impWnd:CreateChildWidget("label", "orLbl", 0, true)
                orLbl:SetExtent(100, 20)
                orLbl:AddAnchor("TOP", importTxtBtn, "BOTTOM", 0, 5)
                orLbl.style:SetAlign(ALIGN.CENTER)
                ApplyTextColor(orLbl, FONT_COLOR.DEFAULT)
                orLbl:SetText("- OR -")
                
                local importFileBtn = impWnd:CreateChildWidget("button", "importFileBtn", 0, true)
                importFileBtn:SetExtent(150, 30)
                importFileBtn:AddAnchor("TOP", orLbl, "BOTTOM", 0, 5)
                importFileBtn:SetText("Import from File")
                api.Interface:ApplyButtonSkin(importFileBtn, BUTTON_BASIC.DEFAULT)
                
                local function ProcessImportString(content)
                    if type(content) == "string" and content ~= "" then
                        if wnd.isWhite and string.sub(content, 1, 3) == "BL:" then
                            api.Log:Err("[Elu Auto Invite] Error: You are trying to import a Blacklist into the Whitelist!")
                            return
                        elseif not wnd.isWhite and string.sub(content, 1, 3) == "WL:" then
                            api.Log:Err("[Elu Auto Invite] Error: You are trying to import a Whitelist into the Blacklist!")
                            return
                        end
                        
                        if string.sub(content, 1, 3) == "WL:" or string.sub(content, 1, 3) == "BL:" then
                            content = string.sub(content, 4)
                        end
                        
                        local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                        local count = 0
                        for name in string.gmatch(content, '([^,]+)') do
                            local n = name:gsub("^%s*(.-)%s*$", "%1")
                            if n ~= "" then
                                local found = false
                                for _, v in ipairs(t) do
                                    if string.lower(v) == string.lower(n) then found = true break end
                                end
                                if not found and #t < 100 then
                                    table.insert(t, n)
                                    count = count + 1
                                end
                            end
                        end
                        SaveSettings()
                        if wnd and wnd.RefreshList then wnd.RefreshList() end
                        LogInfo("Imported " .. tostring(count) .. " new names.")
                        impWnd:Show(false)
                    end
                end
                
                importTxtBtn:SetHandler("OnClick", function()
                    ProcessImportString(input:GetText())
                end)
                
                importFileBtn:SetHandler("OnClick", function()
                    local fileName = wnd.isWhite and "Elu_Tracker/whitelist.txt" or "Elu_Tracker/blacklist.txt"
                    local readOk, content = pcall(function() return api.File:Read(fileName) end)
                    if readOk and type(content) == "string" then
                        ProcessImportString(content)
                    else
                        LogInfo("Could not read " .. fileName)
                    end
                end)
                
                impWnd.titleBar.closeButton:SetHandler("OnClick", function() impWnd:Show(false) end)
                impWnd:Show(true)
            end

            exportBtn:SetHandler("OnClick", function()
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                local fileName = wnd.isWhite and "Elu_Tracker/whitelist.txt" or "Elu_Tracker/blacklist.txt"
                local clean_t = {}
for _, v in pairs(t) do if type(v) == "string" and v ~= "" then table.insert(clean_t, v) end end
local content = table.concat(clean_t, ",")
                local ok = pcall(function() api.File:Write(fileName, content) end)
                if ok then LogInfo("List exported successfully to " .. fileName) else LogInfo("Failed to export List") end
                ShowExportWindow()
            end)
            
            importBtn:SetHandler("OnClick", function()
                ShowImportWindow()
            end)
            
            wnd.exportBtn = exportBtn
            wnd.importBtn = importBtn

            local addRaidBtn = wnd:CreateChildWidget("button", "addRaidBtn", 0, true)
            addRaidBtn:SetExtent(80, 30)
            addRaidBtn:SetText("Add Raid")
            api.Interface:ApplyButtonSkin(addRaidBtn, BUTTON_BASIC.DEFAULT)
            addRaidBtn:SetHandler("OnClick", function()
                if not wnd.isWhite then return end
                
                local myName = ""
                local okMy, myUnitId = pcall(function() return api.Unit:GetUnitId("player") end)
                if okMy and myUnitId then
                    local okMy2, myInfo = pcall(function() return api.Unit:GetUnitInfoById(myUnitId) end)
                    if okMy2 and type(myInfo) == "table" and myInfo.name then
                        myName = FormatName(myInfo.name)
                    end
                end

                local seen = {}
                local function addName(rawName)
                    if type(rawName) ~= "string" then return end
                    local formatted = FormatName(rawName)
                    if formatted == "" or formatted == myName then return end
                    
                    local key = string.lower(formatted)
                    if seen[key] then return end
                    seen[key] = true
                    
                    local found = false
                    for _, v in ipairs(state.whitelist) do
                        if string.lower(v) == key then found = true break end
                    end
                    if not found and #state.whitelist < 100 then
                        table.insert(state.whitelist, formatted)
                    end
                end

                if api.Unit ~= nil and api.Unit.UnitInfo ~= nil then
                    for idx = 1, 50 do
                        local info = nil
                        pcall(function() info = api.Unit:UnitInfo("team" .. tostring(idx)) end)
                        if type(info) == "table" then addName(info.name or info.unitName or "") end
                    end
                end
                
                if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
                    for idx = 1, 50 do
                        local unitToken = "team" .. tostring(idx)
                        local unitId = nil
                        pcall(function() unitId = api.Unit:GetUnitId(unitToken) end)
                        
                        if unitId ~= nil then
                            if api.Unit.GetUnitInfoById ~= nil then
                                local infoById = nil
                                pcall(function() infoById = api.Unit:GetUnitInfoById(unitId) end)
                                if type(infoById) == "table" then addName(infoById.name or infoById.unitName or "") end
                            end
                            if api.Unit.GetUnitNameById ~= nil then
                                local nameById = nil
                                pcall(function() nameById = api.Unit:GetUnitNameById(unitId) end)
                                addName(nameById or "")
                            end
                        end
                    end
                end
                
                if api.Unit ~= nil and api.Unit.UnitName ~= nil then
                    for idx = 1, 50 do
                        local name = nil
                        pcall(function() name = api.Unit:UnitName("team" .. tostring(idx)) end)
                        addName(name or "")
                    end
                end

                SaveSettings()
                wnd.RefreshList()
            end)
            wnd.addRaidBtn = addRaidBtn
            
            local function RefreshList()
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                local maxPage = math.ceil(#t / 5)
                if maxPage < 1 then maxPage = 1 end
                if wnd.page > maxPage then wnd.page = maxPage end
                
                wnd.pageLbl:SetText(tostring(wnd.page) .. " / " .. tostring(maxPage))
                
                local labelColor = wnd.isWhite and {0, 0.8, 0.2, 1} or {1, 0.2, 0.2, 1}
                for i = 1, 5 do
                    local dataIndex = (wnd.page - 1) * 5 + i
                    if t[dataIndex] then
                        wnd.rowWidgets[i]:Show(true)
                        wnd.rowWidgets[i].lbl:SetText(t[dataIndex])
                        ApplyTextColor(wnd.rowWidgets[i].lbl, labelColor)
                        wnd.rowWidgets[i].dataIndex = dataIndex
                    else
                        wnd.rowWidgets[i]:Show(false)
                        wnd.rowWidgets[i].dataIndex = nil
                    end
                end
                
                if wnd.listType == 3 then
                    wnd.exportBtn:Show(false)
                    wnd.importBtn:Show(false)
                else
                    wnd.importBtn:RemoveAllAnchors()
                    wnd.importBtn:AddAnchor("BOTTOM", wnd, 0, -20)
                    wnd.exportBtn:RemoveAllAnchors()
                    wnd.exportBtn:AddAnchor("RIGHT", wnd.importBtn, "LEFT", -10, 0)
                    wnd.exportBtn:Show(true)
                    wnd.importBtn:Show(true)
                end
                
                if wnd.isWhite then
                    wnd.addRaidBtn:RemoveAllAnchors()
                    wnd.addRaidBtn:AddAnchor("LEFT", wnd.importBtn, "RIGHT", 10, 0)
                    wnd.addRaidBtn:Show(true)
                else
                    wnd.addRaidBtn:Show(false)
                end
            end
            wnd.RefreshList = RefreshList
            
            addBtn:SetHandler("OnClick", function()
                local n = input:GetText()
                if not n or n == "" then return end
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
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
        wnd.listType = listType; wnd.isWhite = (listType == 1)
        wnd.page = 1
        wnd:SetTitle(listType == 1 and "Whitelist Manager" or (listType == 2 and "Blacklist Manager" or "Quick Auto Invite Blacklist"))
        wnd.instructions:SetText(listType == 1 and "Add players to automatically invite them" or (listType == 2 and "Add players to prevent raid invites" or "Prevent Fast Auto invites (Separate from Elu)"))
        wnd.list_label:SetText(listType == 1 and "Current Whitelist:" or (listType == 2 and "Current Blacklist:" or "Fast Blacklist:"))
        
        local labelColor = listType == 1 and {0, 0.8, 0.2, 1} or {1, 0.2, 0.2, 1}
        ApplyTextColor(wnd.instructions, labelColor)
        ApplyTextColor(wnd.player_label, labelColor)
        ApplyTextColor(wnd.list_label, labelColor)
        ApplyTextColor(wnd.pageLbl, labelColor)
        
        wnd.RefreshList()
        wnd:Show(true)
        wnd:Raise()
    end
    
    blBtn:SetHandler("OnClick", function() ToggleListWindow(2) end)
    wlBtn:SetHandler("OnClick", function() ToggleListWindow(1) end)
    widgets.ToggleListWindow = ToggleListWindow
end

function raid_invite.OnLoad()
    LoadSettings()
    
    local raid_manager = ADDON:GetContent(UIC.RAID_MANAGER)
    if not raid_manager then return end
    state.canvas_width = raid_manager:GetWidth(); raid_manager:SetExtent(state.canvas_width, 460)
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
    fBgOn:SetVisible(state.inviteMode == 1)
    
    local fBgWhite = fIcon:CreateImageDrawable("Addon/Elu_Tracker/auto_whitelist_on.png", "background")
    fBgWhite:SetExtent(55, 40)
    fBgWhite:AddAnchor("CENTER", fIcon, 0, 0)
    fBgWhite:SetColor(1, 1, 1, 0.7)
    fBgWhite:SetVisible(state.inviteMode == 2)
    
    local fBgOff = fIcon:CreateImageDrawable("Addon/Elu_Tracker/auto_off.png", "background")
    fBgOff:SetExtent(55, 40)
    fBgOff:AddAnchor("CENTER", fIcon, 0, 0)
    fBgOff:SetColor(1, 1, 1, 0.7)
    fBgOff:SetVisible(state.inviteMode == 0)

    widgets.fBgOn = fBgOn
    widgets.fBgWhite = fBgWhite
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
    
    local fKeywordLbl = fIcon:CreateChildWidget("label", "fKeywordLbl", 0, true)
    fKeywordLbl:SetExtent(100, 20)
    fKeywordLbl:AddAnchor("TOP", fIcon, "BOTTOM", 0, 0)
    fKeywordLbl.style:SetAlign(ALIGN.CENTER)
    fKeywordLbl.style:SetShadow(true)
    ApplyTextColor(fKeywordLbl, {1, 1, 1, 1})
    widgets.fKeywordLbl = fKeywordLbl
    
    UpdateFloatingIcon()
    
    -- Fast Auto Invite UI
    local qai_label = raid_manager:CreateChildWidget("label", "qai_label", 0, true)
    qai_label:SetExtent(200, 20)
    qai_label:AddAnchor("BOTTOMLEFT", raid_manager, 20, -105)
    qai_label:SetText("Quick Auto Invite")
    qai_label.style:SetFontSize(14)
    qai_label.style:SetShadow(false)
    ApplyTextColor(qai_label, FONT_COLOR.MIDDLE_TITLE)
    widgets.qai_label = qai_label

    local recruit_button = raid_manager:CreateChildWidget("button", "enhanced_raid_setup_button", 0, true)
    recruit_button:SetExtent(105, 30)
    recruit_button:AddAnchor("BOTTOMLEFT", raid_manager, 20, -65)
    recruit_button:SetText("Start Recruiting")
    api.Interface:ApplyButtonSkin(recruit_button, BUTTON_BASIC.DEFAULT)
    widgets.enhancedRecruitBtn = recruit_button

    local textfield = W_CTRL.CreateEdit("enhanced_recruit_message", raid_manager)
    textfield:AddAnchor("BOTTOMLEFT", raid_manager, 135, -65)
    textfield:SetExtent(110, 30)
    textfield:SetMaxTextLength(64)
    textfield:CreateGuideText("X CR")
    textfield:Show(true)
    widgets.enhancedTextfield = textfield
    
    local enhancedFilterCombo = api.Interface:CreateComboBox(raid_manager)
    enhancedFilterCombo:SetExtent(90, 30)
    enhancedFilterCombo:AddAnchor("BOTTOMLEFT", raid_manager, 255, -65)
    enhancedFilterCombo.dropdownItem = {"Equals", "Contains"}
    enhancedFilterCombo:Select(state.enhancedFilterMode or 2)
    enhancedFilterCombo:Show(true)
    enhancedFilterCombo:SetHandler("OnSelect", function()
        state.enhancedFilterMode = enhancedFilterCombo:GetSelectedIndex()
        SaveSettings()
    end)
    widgets.enhancedFilterCombo = enhancedFilterCombo

    local fast_blacklist_button = raid_manager:CreateChildWidget("button", "fast_blacklist_button", 0, true)
    fast_blacklist_button:SetExtent(80, 30)
    fast_blacklist_button:AddAnchor("BOTTOMLEFT", raid_manager, 355, -65)
    fast_blacklist_button:SetText("Blacklist")
    api.Interface:ApplyButtonSkin(fast_blacklist_button, BUTTON_BASIC.DEFAULT)
    fast_blacklist_button:SetHandler("OnClick", function()
        if not widgets.sidePanel then
            BuildSidePanel(raid_manager)
        end
        if widgets.ToggleListWindow then
            widgets.ToggleListWindow(3)
        end
    end)
    widgets.fast_blacklist_button = fast_blacklist_button
    
    local canvas = api.Interface:CreateEmptyWindow("enhancedRecruitWindow")
    canvas:AddAnchor("CENTER", "UIParent", 0, 50)
    canvas:SetExtent(160, 70)
    canvas:Show(false)
    widgets.enhancedCanvas = canvas

    local bg = canvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.7)
    bg:AddAnchor("TOPLEFT", canvas, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", canvas, 0, 0)

    local canvas_lbl = canvas:CreateChildWidget("label", "canvas_lbl", 0, true)
    canvas_lbl:SetExtent(140, 20)
    canvas_lbl:AddAnchor("TOP", canvas, 0, 10)
    canvas_lbl.style:SetAlign(ALIGN.CENTER)
    canvas_lbl.style:SetShadow(true)
    ApplyTextColor(canvas_lbl, {1, 1, 1, 1})
    widgets.enhancedCanvasLbl = canvas_lbl

    local cancel_button = canvas:CreateChildWidget("button", "cancel_x", 0, true)
    cancel_button:SetText("Stop")
    cancel_button:SetExtent(80, 25)
    cancel_button:AddAnchor("BOTTOM", canvas, 0, -10)
    api.Interface:ApplyButtonSkin(cancel_button, BUTTON_BASIC.DEFAULT)
    
    local function StartEnhancedRecruiting()
        local msg = textfield:GetText()
        if not msg or msg == "" then
            LogErr("Please enter a recruit message.")
            return
        end
        state.enhancedIsActive = true
        state.enhancedKeyword = msg
        recruit_button:SetText("Stop")
        textfield:Enable(false)
        canvas_lbl:SetText("Keyword: " .. msg)
        canvas:Show(true)
        LogInfo("Now recruiting for: " .. msg)
        
        if state.inviteMode > 0 then
            state.inviteMode = 0
            SaveSettings()
            UpdateFloatingIcon()
            if widgets.toggleBtn then widgets.toggleBtn:SetText(GetModeString()) end
            if widgets.statusLbl then
                widgets.statusLbl:SetText("[OFF]")
                ApplyTextColor(widgets.statusLbl, {1, 0, 0, 1})
            end
            
        end
    end
    
    local function ToggleEnhancedRecruiting()
        if state.enhancedIsActive then
            raid_invite.StopEnhancedRecruiting()
            LogInfo("Stopped recruiting.")
        else
            StartEnhancedRecruiting()
        end
    end
    recruit_button:SetHandler("OnClick", ToggleEnhancedRecruiting)
    cancel_button:SetHandler("OnClick", function() 
        raid_invite.StopEnhancedRecruiting()
        LogInfo("Stopped recruiting.")
    end)
    
    canvas:EnableDrag(true)
    canvas:SetHandler("OnDragStart", function(self)
        if api.Input:IsShiftKeyDown() then self:StartMoving() end
    end)
    canvas:SetHandler("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    
    if not raid_invite.isLoaded then
        api.On("CHAT_MESSAGE", OnChatMessage)
        raid_invite.isLoaded = true
    end
end

function raid_invite.OnUpdate(dt)
    -- Leaving raid logic
    local inRaid = false
    if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
        if api.Unit:GetUnitId("team1") ~= nil or api.Unit:GetUnitId("party1") ~= nil then
            inRaid = true
        end
    end
    
    if raid_invite.wasInRaid and not inRaid then
        if state.autoWhitelistRaid then
            state.autoWhitelistRaid = false
            SaveSettings()
            if widgets.sidePanel and widgets.sidePanel.cbAutoRaid then
                widgets.sidePanel.cbAutoRaid:SetChecked(false, false)
            end
            
        end
        if state.inviteMode ~= 0 then
            state.inviteMode = 0
            SaveSettings()
            UpdateFloatingIcon()
            if widgets.toggleBtn then widgets.toggleBtn:SetText(GetModeString()) end
            if widgets.statusLbl then
                widgets.statusLbl:SetText("[OFF]")
                ApplyTextColor(widgets.statusLbl, {1, 0, 0, 1})
            end
            
        end
    end
    raid_invite.wasInRaid = inRaid
    
    if not state.autoWhitelistRaid then return end
    
    local currentTime = api.Time:GetUiMsec()
    if not raid_invite.lastWhitelistPoll or currentTime - raid_invite.lastWhitelistPoll > 5000 then
        raid_invite.lastWhitelistPoll = currentTime
        
        local myName = ""
        pcall(function() myName = FormatName(api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))) end)
        
        local didAdd = false
        local seen = {}
        local function addName(rawName)
            if type(rawName) ~= "string" then return end
            local formatted = FormatName(rawName)
            if formatted == "" or formatted == myName then return end
            
            local key = string.lower(formatted)
            if seen[key] then return end
            seen[key] = true
            
            local found = false
            for _, v in ipairs(state.whitelist) do
                if string.lower(v) == key then found = true break end
            end
            if not found and #state.whitelist < 100 then
                table.insert(state.whitelist, formatted)
                didAdd = true
            end
        end

        if api.Unit ~= nil and api.Unit.UnitInfo ~= nil then
            for idx = 1, 50 do
                local info = nil
                pcall(function() info = api.Unit:UnitInfo("team" .. tostring(idx)) end)
                if type(info) == "table" then addName(info.name or info.unitName or "") end
            end
        end
        
        if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
            for idx = 1, 50 do
                local unitToken = "team" .. tostring(idx)
                local unitId = nil
                pcall(function() unitId = api.Unit:GetUnitId(unitToken) end)
                
                if unitId ~= nil then
                    if api.Unit.GetUnitInfoById ~= nil then
                        local infoById = nil
                        pcall(function() infoById = api.Unit:GetUnitInfoById(unitId) end)
                        if type(infoById) == "table" then addName(infoById.name or infoById.unitName or "") end
                    end
                    if api.Unit.GetUnitNameById ~= nil then
                        local nameById = nil
                        pcall(function() nameById = api.Unit:GetUnitNameById(unitId) end)
                        addName(nameById or "")
                    end
                end
            end
        end
        
        if didAdd then
            SaveSettings()
            if widgets.listWindow and widgets.listWindow:IsVisible() and widgets.listWindow.isWhite then
                widgets.listWindow.RefreshList()
            end
        end
    end
end

function raid_invite.OnUnload()
    if widgets.raid_manager and state.canvas_width and state.canvas_width > 0 then widgets.raid_manager:SetExtent(state.canvas_width, 395) end
    if widgets.qai_label then widgets.qai_label:Show(false) end
    if widgets.enhancedRecruitBtn then widgets.enhancedRecruitBtn:Show(false) end
    if widgets.enhancedTextfield then widgets.enhancedTextfield:Show(false) end
    if widgets.enhancedFilterCombo then widgets.enhancedFilterCombo:Show(false) end
    if widgets.fast_blacklist_button then widgets.fast_blacklist_button:Show(false) end
    if widgets.enhancedCanvas then widgets.enhancedCanvas:Show(false) end
    state.inviteMode = 0
    if widgets.toggleSideBtn then widgets.toggleSideBtn:Show(false) end
    if widgets.sidePanel then widgets.sidePanel:Show(false) end
    if widgets.listWindow then widgets.listWindow:Show(false) end
    if widgets.floatingIcon then widgets.floatingIcon:Show(false) end
end

return raid_invite







