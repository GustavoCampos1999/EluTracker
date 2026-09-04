local settingsManager = require("Elu_Tracker/settings_manager")
local settings = settingsManager.Settings.lossPornSettings
local SaveSettings = settingsManager.SaveSettings

local api = require("api")

local ui = {}

local logWindow
local logList
local closeBtn
local filterComboBox
local currentFilterIndex = 1

local function DataSetFunc(subItem, data, setValue)
    if setValue then
        subItem.text:SetText(data.richText or "")
        if data.index and data.index % 2 == 0 then
            subItem.customBg:Show(true)
        else
            subItem.customBg:Show(false)
        end
    else
        subItem.text:SetText("")
        subItem.customBg:Show(false)
    end
end

local function LayoutSetFunc(frame, rowIndex, colIndex, subItem)
    if subItem.bg then subItem.bg:SetColor(1, 1, 1, 0) end
    
    local rowBg = subItem:CreateColorDrawable(0.93, 0.90, 0.83, 1, "background")
    rowBg:AddAnchor("TOPLEFT", subItem, 0, 0)
    rowBg:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    subItem.customBg = rowBg
    
    local textbox = subItem:CreateChildWidget("textbox", "text", 0, true)
    textbox:AddAnchor("TOPLEFT", subItem, 5, 2)
    textbox:AddAnchor("BOTTOMRIGHT", subItem, -5, -2)
    textbox.style:SetAlign(ALIGN.TOP_LEFT)
    textbox.style:SetFontSize(14)
    textbox.style:SetColor(0.4, 0.3, 0.2, 1)
end

function ui.Initialize()
    if logWindow then return end

    logWindow = api.Interface:CreateEmptyWindow("lossPornLogWnd_v20", "UIParent")
    logWindow:SetExtent(750, 450)
    logWindow:AddAnchor("CENTER", "UIParent", 0, 0)
    logWindow:Show(false)
    
    if logWindow.SetCloseOnEscape then logWindow:SetCloseOnEscape(true) end
    
    if logWindow.EnableDrag then logWindow:EnableDrag(true) end
    function logWindow:OnDragStart() logWindow:StartMoving() end
    logWindow:SetHandler("OnDragStart", logWindow.OnDragStart)
    function logWindow:OnDragStop() logWindow:StopMovingOrSizing() end
    logWindow:SetHandler("OnDragStop", logWindow.OnDragStop)

    local border = logWindow:CreateColorDrawable(0.6, 0.5, 0.4, 1, "background")
    border:AddAnchor("TOPLEFT", logWindow, 0, 0)
    border:AddAnchor("BOTTOMRIGHT", logWindow, 0, 0)
    
    local bg = logWindow:CreateColorDrawable(0.96, 0.94, 0.90, 1, "background")
    bg:AddAnchor("TOPLEFT", logWindow, 1, 1)
    bg:AddAnchor("BOTTOMRIGHT", logWindow, -1, -1)

    local topBar = logWindow:CreateColorDrawable(0.90, 0.86, 0.78, 1, "background")
    topBar:AddAnchor("TOPLEFT", logWindow, 1, 1)
    topBar:AddAnchor("BOTTOMRIGHT", logWindow, -1, -415)

    local title = logWindow:CreateChildWidget("label", "title", 0, true)
    title:AddAnchor("TOPLEFT", logWindow, 15, 10)
    title:SetExtent(200, 20)
    title:SetText("Regrade Log")
    title.style:SetFontSize(16)
    title.style:SetAlign(ALIGN.LEFT)
    title.style:SetColor(0.2, 0.1, 0, 1)

    local madeBy = logWindow:CreateChildWidget("label", "madeBy", 0, true)
    madeBy:AddAnchor("BOTTOMRIGHT", logWindow, -15, -10)
    madeBy:SetExtent(150, 20)
    madeBy:SetText("Made by: Eludelu")
    madeBy.style:SetFontSize(12)
    madeBy.style:SetAlign(ALIGN.RIGHT)
    madeBy.style:SetColor(0.6, 0.5, 0.4, 1)

    if W_CTRL and W_CTRL.CreateComboBox then
        filterComboBox = W_CTRL.CreateComboBox(logWindow)
        filterComboBox:SetWidth(150)
        filterComboBox:AddAnchor("TOPRIGHT", logWindow, -45, 5)
        filterComboBox.dropdownItem = { "All", "Success Only", "Failed/Destroyed" }
        filterComboBox:Select(1)
        
        function filterComboBox:SelectedProc(index)
            currentFilterIndex = index
            ui.RefreshList()
        end
    end

    -- Fails-in-chat mode: Off / System Chat / Alert Chat
    -- Centered as a unit across the window's width, and vertically
    -- centered inside the darker header stripe (that strip spans y=1..35,
    -- see topBar above -- center is y=18).
    local chatModeLabel = logWindow:CreateChildWidget("label", "chatModeLabel", 0, true)
    chatModeLabel:SetAutoResize(true)
    chatModeLabel:SetHeight(20)
    chatModeLabel:SetText("Fails in Chat:")
    chatModeLabel.style:SetColor(0.2, 0.2, 0.2, 1)
    chatModeLabel.style:SetAlign(ALIGN.LEFT)
    chatModeLabel:AddAnchor("TOPLEFT", logWindow, 0, 8) -- placeholder, recentered below

    local comboWidth = 115
    local chatModeCombo = W_CTRL.CreateComboBox(logWindow)
    chatModeCombo:SetWidth(comboWidth)
    chatModeCombo:AddAnchor("LEFT", chatModeLabel, "RIGHT", 6, 0)
    chatModeCombo.dropdownItem = { "Off", "System Chat", "Alert Chat" }
    chatModeCombo:Select(settings.chatMode or 1)

    -- NOTE: the correct selection callback for this widget is
    -- :SelectedProc(index) -- SetHandler("OnSelect", ...) never fires on
    -- this ComboBox type (a bug found and fixed elsewhere in this addon).
    function chatModeCombo:SelectedProc(index)
        settings.chatMode = index
        SaveSettings()
    end

    -- Now that the label has its real text, measure it and re-anchor the
    -- label+combo pair centered as a whole (the combo, anchored relative
    -- to the label, follows automatically). Same centering technique used
    -- elsewhere in this addon (see quick_equip.lua's enable checkbox row).
    local labelWidth = chatModeLabel:GetWidth() or 90
    local gap = 6
    local totalWidth = labelWidth + gap + comboWidth
    local windowWidth = logWindow:GetWidth() or 750
    local startX = math.floor((windowWidth - totalWidth) / 2)
    chatModeLabel:RemoveAllAnchors()
    chatModeLabel:AddAnchor("TOPLEFT", logWindow, startX, 8)


    -- Close Button
    closeBtn = logWindow:CreateChildWidget("button", "closeBtn", 0, true)
    closeBtn:SetExtent(30, 30)
    closeBtn:AddAnchor("TOPRIGHT", logWindow, -5, 2)
    local btnBg = closeBtn:CreateColorDrawable(0, 0, 0, 0, "background")
    btnBg:AddAnchor("TOPLEFT", closeBtn, 0, 0)
    btnBg:AddAnchor("BOTTOMRIGHT", closeBtn, 0, 0)
    local btnLbl = closeBtn:CreateChildWidget("label", "lbl", 0, true)
    btnLbl:SetText("X")
    btnLbl:AddAnchor("CENTER", closeBtn, 0, 0)
    btnLbl.style:SetColor(0.8, 0.2, 0.2, 1)
    
    function closeBtn:OnClick()
        logWindow:Show(false)
    end
    closeBtn:SetHandler("OnClick", closeBtn.OnClick)
    
    function closeBtn:OnEnter() btnBg:SetColor(0, 0, 0, 0.1) end
    closeBtn:SetHandler("OnEnter", closeBtn.OnEnter)
    
    function closeBtn:OnLeave() btnBg:SetColor(0, 0, 0, 0) end
    closeBtn:SetHandler("OnLeave", closeBtn.OnLeave)

    -- The Scrolling List Box
    if W_CTRL and W_CTRL.CreatePageScrollListCtrl then
        logList = W_CTRL.CreatePageScrollListCtrl("lossPornLogList_v20", logWindow)
        logList:Show(true)
        logList:AddAnchor("TOPLEFT", logWindow, 10, 45)
        logList:AddAnchor("BOTTOMRIGHT", logWindow, -10, -25)
        
        local listBgCover = logList:CreateColorDrawable(0.96, 0.94, 0.90, 1, "background")
        listBgCover:AddAnchor("TOPLEFT", logList, 0, 0)
        listBgCover:AddAnchor("BOTTOMRIGHT", logList, 0, 0)
        
        if logList.pageControl then
            logList.pageControl:Show(false)
        end

        if logList.listCtrl and logList.listCtrl.SetColumnHeight then
            logList.listCtrl:SetColumnHeight(1)
        end
        
        logList:InsertColumn("", 710, 1, DataSetFunc, nil, nil, LayoutSetFunc)
        logList:InsertRows(8, false)
        logList.listCtrl:DisuseSorting()
    end
    
    ui.RefreshList()
end

function ui.RefreshList()
    if not logWindow or not logList then return end
    
    
    local allLogs = settings.sessionLogs or {}
    
    if logList.DeleteAllDatas then logList:DeleteAllDatas() end
    
    local visibleIndex = 1
    for i = 1, #allLogs do
        local logItem = allLogs[i]
        
        local include = false
        if currentFilterIndex == 1 then
            include = true
        elseif currentFilterIndex == 2 and logItem.isSuccess then
            include = true
        elseif currentFilterIndex == 3 and not logItem.isSuccess then
            include = true
        end
        
        if include and type(logItem) == "table" and logItem.line1 and logItem.line2 then
            logList:InsertData(i, 1, {
                richText = logItem.line1 .. "\n" .. logItem.line2,
                index = visibleIndex
            })
            visibleIndex = visibleIndex + 1
        end
    end
end

function ui.Toggle()
    if not logWindow then
        ui.Initialize()
    end
    if logWindow then
        logWindow:Show(not logWindow:IsVisible())
        if logWindow:IsVisible() then
            ui.RefreshList()
        end
    end
end

function ui.Destroy()
    if logWindow then
        logWindow:Show(false)
        pcall(function() api.Interface:Free(logWindow) end)
        logWindow = nil
        logList = nil
        filterComboBox = nil
    end
end

return ui
