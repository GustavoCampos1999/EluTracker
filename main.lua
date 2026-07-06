local elu_tracker_addon = {
	name = "Elu Tracker",
	author = "Eludelu",
	version = "1.0",
	desc = "Commerce & Fishing tools.",
	tags = {"Economy", "Fishing", "QoL"}
}

local packsAddon = require("elu_tracker/packs")
local guildCheckAddon = require("elu_tracker/guild_check")
local fishingAddon = require("elu_tracker/fishing")
local spotTrackerAddon = require("elu_tracker/spot_tracker")
local zealAlertAddon = require("elu_tracker/zeal_alert")
local stopwatchAddon = require("elu_tracker/stopwatch")
eluDisplayWindow = nil
local eluBtn

local tripOverlay
local tripCount = 0
local eluCharcoalLabel = nil
local priceUpdateTimer = 0
local _charcoalInputRef = nil
local _charcoalSilverInputRef = nil
local _dragonInputRef = nil
local _dragonSilverInputRef = nil
local _pricePanelRef = nil
local _pollTimer = 0
local _pendingCharcoalPrice = nil
local _pendingCharcoalSilver = nil
local _pendingDragonPrice = nil
local _pendingDragonSilver = nil

local function ConvertColor(color) return color / 255 end 

local memoryAHPrices = nil

local function LoadAHPrices()
    if not memoryAHPrices then
        memoryAHPrices = {
            [32103] = { average = 1.5 },
            [32106] = { average = 22 }
        }
        local data = api.File:Read("elu_tracker/data_sessions/elu_commerce_prices.txt")
        if type(data) == "table" then
            if data.c ~= nil then memoryAHPrices[32103].average = tonumber(data.c) or memoryAHPrices[32103].average end
            if data.d ~= nil then memoryAHPrices[32106].average = tonumber(data.d) or memoryAHPrices[32106].average end
        end
    end
end

local function GetAHPriceSafe(itemId)
    LoadAHPrices()
    if memoryAHPrices[itemId] and memoryAHPrices[itemId].average then
        return memoryAHPrices[itemId].average
    end
    return 0
end

local function SetManualPrices(cGold, cSilver, dGold, dSilver)
    LoadAHPrices()
    
    local function parseNum(val)
        if type(val) == "string" then val = val:gsub(",", ".") end
        return tonumber(val) or 0
    end

    local cG = parseNum(cGold)
    local cS = parseNum(cSilver)
    local dG = parseNum(dGold)
    local dS = parseNum(dSilver)

    local charcoalVal = cG + (cS / 100)
    local dragonVal = dG + (dS / 100)

    if charcoalVal == 0 then charcoalVal = memoryAHPrices[32103].average end
    if dragonVal == 0 then dragonVal = memoryAHPrices[32106].average end

    memoryAHPrices[32103].average = charcoalVal
    memoryAHPrices[32106].average = dragonVal

    local tableToSave = { c = charcoalVal, d = dragonVal }
    api.File:Write("elu_tracker/data_sessions/elu_commerce_prices.txt", tableToSave)

    if eluCharcoalLabel then
        eluCharcoalLabel:SetText(string.format("Charcoal: %.2fg | Dragon: %.2fg", charcoalVal, dragonVal))
    end
    api.Log:Info(string.format("[Elu Tracker] Prices updated! Charcoal: %.2fg | Dragon: %.2fg", charcoalVal, dragonVal))
end
local bagFrameFixed = false
local function OnUpdate(dt)
    priceUpdateTimer = priceUpdateTimer + (type(dt) == "number" and dt or 0)
    if priceUpdateTimer > 2000 then 
        priceUpdateTimer = 0
        if eluCharcoalLabel and eluCharcoalLabel:IsVisible() then
            local charcoalPrice = GetAHPriceSafe(32103)
            local dragonPrice = GetAHPriceSafe(32106)
            eluCharcoalLabel:SetText(string.format("Charcoal: %.2fg | Dragon: %.2fg", charcoalPrice, dragonPrice))
        end
    end
    
    if not bagFrameFixed then
        local bagFrame = ADDON:GetContent(UIC.BAG)
        if bagFrame and bagFrame.paystubBtn then
            bagFrame.paystubBtn.Show = function() end 
            bagFrame.paystubBtn:Show(false)
            bagFrame.paystubBtn:SetExtent(0, 0)
            bagFrame.paystubBtn:RemoveAllAnchors()
            bagFrame.paystubBtn:AddAnchor("TOPLEFT", "UIParent", -9999, -9999)
            bagFrameFixed = true
        end
    end
    
    if spotTrackerAddon and spotTrackerAddon.OnUpdate then
        spotTrackerAddon:OnUpdate(dt)
    end
    
    if stopwatchAddon and stopwatchAddon.OnUpdate then
        stopwatchAddon:OnUpdate(dt)
    end
    
end


local function CreateCommerceWindow(wndParent)
    local wnd = wndParent:CreateChildWidget("emptywidget", "commerceWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)

    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Pending Pack Payments")
    title:AddAnchor("TOP", wnd, 0, 10)

    local charcoalLabel = wnd:CreateChildWidget("label", "charcoalLabel", 0, true)
    charcoalLabel.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(charcoalLabel, FONT_COLOR.EXP_ORANGE)
    charcoalLabel.style:SetAlign(ALIGN.CENTER)
    charcoalLabel:SetText("Loading...")
    charcoalLabel:AddAnchor("TOP", title, "BOTTOM", 0, 15)
    eluCharcoalLabel = charcoalLabel

    local setPriceBtn = wnd:CreateChildWidget("button", "setPriceBtn", 0, true)
    setPriceBtn:SetText("Set Price")
    setPriceBtn:SetExtent(80, 25)
    setPriceBtn:AddAnchor("TOPRIGHT", wnd, -15, 10)
    ApplyButtonSkin(setPriceBtn, BUTTON_BASIC.DEFAULT)

    local pricePanel = wnd:CreateChildWidget("emptywidget", "pricePanel", 0, true)
    pricePanel:SetExtent(200, 115)
    pricePanel:AddAnchor("TOPRIGHT", setPriceBtn, "BOTTOMRIGHT", 0, 5)
    pricePanel:Show(false)

    local pBg = pricePanel:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    pBg:SetTextureInfo("bg_quest")
    pBg:SetColor(0, 0, 0, 0.95)
    pBg:AddAnchor("TOPLEFT", pricePanel, 0, 0)
    pBg:AddAnchor("BOTTOMRIGHT", pricePanel, 0, 0)

    local charcoalGoldInput = W_CTRL.CreateEdit("charcoalGoldInput", pricePanel)
    charcoalGoldInput:SetExtent(45, 20)
    charcoalGoldInput:AddAnchor("TOPRIGHT", pricePanel, -55, 15)
    charcoalGoldInput.style:SetAlign(ALIGN.CENTER)
    charcoalGoldInput:SetDigit(true)

    local charcoalSilverInput = W_CTRL.CreateEdit("charcoalSilverInput", pricePanel)
    charcoalSilverInput:SetExtent(35, 20)
    charcoalSilverInput:AddAnchor("LEFT", charcoalGoldInput, "RIGHT", 5, 0)
    charcoalSilverInput.style:SetAlign(ALIGN.CENTER)
    charcoalSilverInput:SetDigit(true)

    local lblG = pricePanel:CreateChildWidget("label", "lblG", 0, true)
    lblG:SetText("G")
    lblG:AddAnchor("BOTTOM", charcoalGoldInput, "TOP", 0, -2)
    ApplyTextColor(lblG, {1, 0.8, 0, 1})

    local lblS = pricePanel:CreateChildWidget("label", "lblS", 0, true)
    lblS:SetText("S")
    lblS:AddAnchor("BOTTOM", charcoalSilverInput, "TOP", 0, -2)
    ApplyTextColor(lblS, {0.8, 0.8, 0.8, 1})

    local charcoalRowLabel = pricePanel:CreateChildWidget("label", "charcoalRowLabel", 0, true)
    charcoalRowLabel:SetText("Charcoal:")
    charcoalRowLabel:AddAnchor("RIGHT", charcoalGoldInput, "LEFT", -10, 0)
    charcoalRowLabel:SetAutoResize(true)
    ApplyTextColor(charcoalRowLabel, FONT_COLOR.DEFAULT)

    local dragonGoldInput = W_CTRL.CreateEdit("dragonGoldInput", pricePanel)
    dragonGoldInput:SetExtent(45, 20)
    dragonGoldInput:AddAnchor("TOPRIGHT", charcoalGoldInput, "BOTTOMRIGHT", 0, 10)
    dragonGoldInput.style:SetAlign(ALIGN.CENTER)
    dragonGoldInput:SetDigit(true)

    local dragonSilverInput = W_CTRL.CreateEdit("dragonSilverInput", pricePanel)
    dragonSilverInput:SetExtent(35, 20)
    dragonSilverInput:AddAnchor("LEFT", dragonGoldInput, "RIGHT", 5, 0)
    dragonSilverInput.style:SetAlign(ALIGN.CENTER)
    dragonSilverInput:SetDigit(true)

    local dragonRowLabel = pricePanel:CreateChildWidget("label", "dragonRowLabel", 0, true)
    dragonRowLabel:SetText("Dragon:")
    dragonRowLabel:AddAnchor("RIGHT", dragonGoldInput, "LEFT", -10, 0)
    dragonRowLabel:SetAutoResize(true)
    ApplyTextColor(dragonRowLabel, FONT_COLOR.DEFAULT)

    local savePriceBtn = pricePanel:CreateChildWidget("button", "savePriceBtn", 0, true)
    savePriceBtn:SetText("Save")
    savePriceBtn:SetExtent(60, 24)
    savePriceBtn:AddAnchor("BOTTOM", pricePanel, 0, -8)
    ApplyButtonSkin(savePriceBtn, BUTTON_BASIC.DEFAULT)

    _charcoalInputRef = charcoalGoldInput
    _charcoalSilverInputRef = charcoalSilverInput
    _dragonInputRef = dragonGoldInput
    _dragonSilverInputRef = dragonSilverInput
    _pricePanelRef = pricePanel

    local function DoSave()
        local function safeNum(txt)
            if type(txt) ~= "string" then txt = tostring(txt) end
            local m = string.match(txt, "%d+")
            if m then return tonumber(m) else return 0 end
        end

        local cG = safeNum(charcoalGoldInput:GetText())
        local cS = safeNum(charcoalSilverInput:GetText())
        local dG = safeNum(dragonGoldInput:GetText())
        local dS = safeNum(dragonSilverInput:GetText())
        
        local cVal = (cG or 0) + ((cS or 0) / 100)
        local dVal = (dG or 0) + ((dS or 0) / 100)

        if cVal <= 0 then 
            cVal = GetAHPriceSafe(32103) 
        end
        if dVal <= 0 then 
            dVal = GetAHPriceSafe(32106) 
        end

        memoryAHPrices[32103].average = cVal
        memoryAHPrices[32106].average = dVal
        api.File:Write("elu_tracker/data_sessions/elu_commerce_prices.txt", { c = cVal, d = dVal })

        if eluCharcoalLabel then
            eluCharcoalLabel:SetText(string.format("Charcoal: %.2fg | Dragon: %.2fg", cVal, dVal))
        end
        api.Log:Info(string.format("[EluTracker] Preco salvo -> Charcoal: %.2fg | Dragon: %.2fg", cVal, dVal))

        _pendingCharcoalPrice = nil
        _pendingCharcoalSilver = nil
        _pendingDragonPrice = nil
        _pendingDragonSilver = nil
        pricePanel:Show(false)
        charcoalGoldInput:ClearFocus()
        charcoalSilverInput:ClearFocus()
        dragonGoldInput:ClearFocus()
        dragonSilverInput:ClearFocus()
        
        if packsAddon and packsAddon.RefreshUI then
            packsAddon.RefreshUI()
        end
    end

    function setPriceBtn:OnClick()
        local isVisible = pricePanel:IsVisible()
        if not isVisible then
            pricePanel:Raise()
            local cPrice = GetAHPriceSafe(32103)
            local dPrice = GetAHPriceSafe(32106)
            _pendingCharcoalPrice = math.floor(cPrice)
            _pendingCharcoalSilver = math.floor((cPrice % 1) * 100)
            _pendingDragonPrice = math.floor(dPrice)
            _pendingDragonSilver = math.floor((dPrice % 1) * 100)
            charcoalGoldInput:SetText(tostring(_pendingCharcoalPrice))
            charcoalSilverInput:SetText(string.format("%02d", _pendingCharcoalSilver))
            dragonGoldInput:SetText(tostring(_pendingDragonPrice))
            dragonSilverInput:SetText(string.format("%02d", _pendingDragonSilver))
        end
        pricePanel:Show(not isVisible)
    end
    setPriceBtn:SetHandler("OnClick", setPriceBtn.OnClick)

    function savePriceBtn:OnClick() DoSave() end
    savePriceBtn:SetHandler("OnClick", savePriceBtn.OnClick)

    function charcoalGoldInput:OnEnterPressed() DoSave() end
    charcoalGoldInput:SetHandler("OnEnterPressed", charcoalGoldInput.OnEnterPressed)

    function charcoalSilverInput:OnEnterPressed() DoSave() end
    charcoalSilverInput:SetHandler("OnEnterPressed", charcoalSilverInput.OnEnterPressed)

    function dragonGoldInput:OnEnterPressed() DoSave() end
    dragonGoldInput:SetHandler("OnEnterPressed", dragonGoldInput.OnEnterPressed)

    function dragonSilverInput:OnEnterPressed() DoSave() end
    dragonSilverInput:SetHandler("OnEnterPressed", dragonSilverInput.OnEnterPressed)

    local sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wnd)
    sessionScrollList:Show(true)
    sessionScrollList:AddAnchor("TOPLEFT", wnd, 4, 40)
    sessionScrollList:AddAnchor("BOTTOMRIGHT", wnd, -4, -4)
    return wnd
end

local function CreateGuildCheckWindow(wndParent)
    local wnd = wndParent:CreateChildWidget("emptywidget", "guildCheckWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)
    
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Guild Check")
    title:AddAnchor("TOP", wnd, 0, 10)
    
    local desc = wnd:CreateChildWidget("label", "desc", 0, true)
    desc:SetAutoResize(true)
    desc:SetHeight(FONT_SIZE.LARGE)
    desc.style:SetAlign(ALIGN.CENTER)
    desc.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(desc, FONT_COLOR.DEFAULT)
    desc:SetText("Under construction")
    desc:AddAnchor("CENTER", wnd, 0, 0)
    
    return wnd
end 

local function CreateFishingWindow(wndParent)
    local wnd = wndParent:CreateChildWidget("emptywidget", "fishingWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Fish Payments")
    title:AddAnchor("TOP", wnd, 0, 10)
    
    local sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wnd)
    sessionScrollList:Show(true)
    sessionScrollList:AddAnchor("TOPLEFT", wnd, 4, 4)
    sessionScrollList:AddAnchor("BOTTOMRIGHT", wnd, -4, -4)
    return wnd
end 

local function CreateMiscWindow(wndParent)
    local wnd = wndParent:CreateChildWidget("emptywidget", "miscWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)

    local bg = wnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(ConvertColor(220), ConvertColor(220), ConvertColor(220), 0.5)
    bg:AddAnchor("TOPLEFT", wnd, 10, 10)
    bg:AddAnchor("BOTTOMRIGHT", wnd, -10, -10)
    
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title.style:SetFontSize(FONT_SIZE.XXLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Trip Counter")
    title:AddAnchor("TOP", wnd, 0, 30)

    local desc = wnd:CreateChildWidget("textbox", "desc", 0, true)
    desc:SetExtent(500, 40)
    desc.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(desc, FONT_COLOR.DEFAULT)
    desc:SetText("Use the overlay to count trips sequentially.")
    desc:AddAnchor("TOP", title, "BOTTOM", 0, 10)

    local toggleBtn = wnd:CreateChildWidget("button", "toggleBtn", 0, true)
    toggleBtn:SetText("Toggle Trip Counter")
    toggleBtn:AddAnchor("TOP", desc, "BOTTOM", -70, 20)
    ApplyButtonSkin(toggleBtn, BUTTON_BASIC.DEFAULT)
    function toggleBtn:OnClick()
        if tripOverlay then
            local isVisible = not tripOverlay:IsVisible()
            tripOverlay:Show(isVisible)
            tripOverlay.countLabel:SetText("Trip: " .. tostring(tripCount or 0))
        end
    end
    toggleBtn:SetHandler("OnClick", toggleBtn.OnClick)

    local toggleStopwatchBtn = wnd:CreateChildWidget("button", "toggleStopwatchBtn", 0, true)
    toggleStopwatchBtn:SetText("Toggle Stopwatch")
    toggleStopwatchBtn:AddAnchor("TOP", desc, "BOTTOM", 70, 20)
    ApplyButtonSkin(toggleStopwatchBtn, BUTTON_BASIC.DEFAULT)
    function toggleStopwatchBtn:OnClick()
        if stopwatchAddon and stopwatchAddon.ToggleStopwatch then
            stopwatchAddon.ToggleStopwatch()
        end
    end
    toggleStopwatchBtn:SetHandler("OnClick", toggleStopwatchBtn.OnClick)


    if spotTrackerAddon and spotTrackerAddon.CreateUI then
        spotTrackerAddon.CreateUI(wnd)
    end

    if zealAlertAddon and zealAlertAddon.CreateUI then
        zealAlertAddon.CreateUI(wnd)
    end

    return wnd
end

local function OnLoad()
    local migrationFiles = {
        "elu_commerce_prices.txt",
        "elu_trip_pos.txt",
        "elu_tracker_pack_sessions.lua",
        "elu_tracker_fishing_sessions.lua",
        "elu_spot_timers.txt",
        "elu_tracker_misc.txt",
        "elu_spot_pos.txt",
        "elu_stopwatch_pos.txt",
        "elu_zeal_settings.txt"
    }
    for _, file in ipairs(migrationFiles) do
        local finalPath = "elu_tracker/data_sessions/" .. file
        local intermediatePath = "elu_tracker/data/" .. file
        local rootPath = file
        
        local currentData = api.File:Read(finalPath)
        if type(currentData) ~= "table" then
            local intermediateData = api.File:Read(intermediatePath)
            if type(intermediateData) == "table" then
                api.File:Write(finalPath, intermediateData)
            else
                local rootData = api.File:Read(rootPath)
                if type(rootData) == "table" then
                    api.File:Write(finalPath, rootData)
                end
            end
        end
    end

    LoadAHPrices()
    packsAddon = require("elu_tracker/packs")
    guildCheckAddon = require("elu_tracker/guild_check")
    fishingAddon = require("elu_tracker/fishing")
    spotTrackerAddon = require("elu_tracker/spot_tracker")
    
    local tabInfo = {
        {
            validationCheckFunc = function() return true end,
            title = "Commerce",
            subWindowConstructor = function(parent) CreateCommerceWindow(parent) end
        },
        {
            validationCheckFunc = function() return true end,
            title = "Guild Check",
            subWindowConstructor = function(parent) CreateGuildCheckWindow(parent) end
        },
        {
            validationCheckFunc = function() return true end,
            title = "Fishing",
            subWindowConstructor = function(parent) CreateFishingWindow(parent) end
        },
        {
            validationCheckFunc = function() return true end,
            title = "Misc.",
            subWindowConstructor = function(parent) return CreateMiscWindow(parent) end
        }
    }
    
    eluDisplayWindow = api.Interface:CreateWindow("eluDisplayWindow", "Elu Tracker", 600, 840, tabInfo)
    eluDisplayWindow:AddAnchor("CENTER", "UIParent", 0, 0)
    eluDisplayWindow:Show(false)
if eluDisplayWindow.titleBar and eluDisplayWindow.titleBar.bg then
        eluDisplayWindow.titleBar.bg:SetColor(ConvertColor(40), ConvertColor(44), ConvertColor(52), 1.0) 
    end
    if eluDisplayWindow.bg then
        eluDisplayWindow.bg:SetColor(ConvertColor(24), ConvertColor(26), ConvertColor(31), 0.95) 
    end

    local bagFrame = ADDON:GetContent(UIC.BAG)
    
    eluBtn = bagFrame:CreateChildWidget("button", "eluBtn", 0, true)
    eluBtn:AddAnchor("BOTTOMLEFT", bagFrame.expandBtn, -55, 5)
    eluBtn:SetExtent(50, 50)
    local btnBg = eluBtn:CreateImageDrawable("Addon/elu_tracker/icon.png", "background")
    btnBg:AddAnchor("TOPLEFT", eluBtn, 0, 0)
    btnBg:AddAnchor("BOTTOMRIGHT", eluBtn, 0, 0)
    eluBtn:Show(true)
    eluBtn:Raise()
    function eluBtn:OnClick()
        eluDisplayWindow:Show(not eluDisplayWindow:IsVisible())
    end 
    eluBtn:SetHandler("OnClick", eluBtn.OnClick)
    function eluBtn:OnEnter()
        btnBg:RemoveAllAnchors()
        btnBg:AddAnchor("TOPLEFT", eluBtn, -4, -4)
        btnBg:AddAnchor("BOTTOMRIGHT", eluBtn, 4, 4)
    end
    eluBtn:SetHandler("OnEnter", eluBtn.OnEnter)
    
    function eluBtn:OnLeave()
        btnBg:RemoveAllAnchors()
        btnBg:AddAnchor("TOPLEFT", eluBtn, 0, 0)
        btnBg:AddAnchor("BOTTOMRIGHT", eluBtn, 0, 0)
    end
    eluBtn:SetHandler("OnLeave", eluBtn.OnLeave)

    tripOverlay = api.Interface:CreateEmptyWindow("tripOverlay", "UIParent")
    tripOverlay:SetExtent(160, 90)
    tripOverlay:AddAnchor("TOPLEFT", "UIParent", 300, 100)
    tripOverlay:Show(false)
    tripOverlay:EnableDrag(true)

    local tripPosFile = "elu_tracker/data_sessions/elu_trip_pos.txt"
    local function SaveTripPos()
        if tripOverlay then
            local x, y = tripOverlay:GetOffset()
            if x and y then
                api.File:Write(tripPosFile, { x = x, y = y })
            end
        end
    end

    local function LoadTripPos()
        local data = api.File:Read(tripPosFile)
        if type(data) == "table" and data.x and data.y then
            tripOverlay:RemoveAllAnchors()
            tripOverlay:AddAnchor("TOPLEFT", "UIParent", data.x, data.y)
        end
    end

    function tripOverlay:OnDragStart() self:StartMoving() end
    tripOverlay:SetHandler("OnDragStart", tripOverlay.OnDragStart)

    function tripOverlay:OnDragStop() 
        self:StopMovingOrSizing() 
        SaveTripPos()
    end
    tripOverlay:SetHandler("OnDragStop", tripOverlay.OnDragStop)
    LoadTripPos()
    
    local bg = tripOverlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.7)
    bg:AddAnchor("TOPLEFT", tripOverlay, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", tripOverlay, 0, 0)
    
    local closeBtn = tripOverlay:CreateChildWidget("button", "closeBtn", 0, true)
    closeBtn:SetText("X")
    closeBtn:SetExtent(16, 16)
    closeBtn:AddAnchor("TOPRIGHT", tripOverlay, -5, 5)
    closeBtn.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(closeBtn, FONT_COLOR.RED)
    function closeBtn:OnClick() tripOverlay:Show(false) end
    closeBtn:SetHandler("OnClick", closeBtn.OnClick)
    
    local resetOverlayBtn = tripOverlay:CreateChildWidget("button", "resetOverlayBtn", 0, true)
    resetOverlayBtn:SetText("R")
    resetOverlayBtn:SetExtent(15, 15)
    resetOverlayBtn:AddAnchor("RIGHT", closeBtn, "LEFT", -5, 0)
    ApplyTextColor(resetOverlayBtn, FONT_COLOR.EXP_ORANGE)
    function resetOverlayBtn:OnClick()
        tripCount = 0
        if tripOverlay and tripOverlay.countLabel then
            tripOverlay.countLabel:SetText("Trip: " .. tostring(tripCount))
        end
    end
    resetOverlayBtn:SetHandler("OnClick", resetOverlayBtn.OnClick)

    local countLabel = tripOverlay:CreateChildWidget("label", "countLabel", 0, true)
    countLabel:AddAnchor("TOP", tripOverlay, 0, 20)
    countLabel.style:SetFontSize(FONT_SIZE.LARGE)
    countLabel:SetText("Trip: " .. tostring(tripCount or 0))
    tripOverlay.countLabel = countLabel
    
    local compBtn = tripOverlay:CreateChildWidget("button", "compBtn", 0, true)
    compBtn:SetText("Complete Trip")
    compBtn:AddAnchor("BOTTOM", tripOverlay, 0, -15)
    ApplyButtonSkin(compBtn, BUTTON_BASIC.DEFAULT)

    function compBtn:OnClick()
        tripCount = (tripCount or 0) + 1
        countLabel:SetText("Trip: " .. tostring(tripCount or 0))
    end
    compBtn:SetHandler("OnClick", compBtn.OnClick)
    tripOverlay.compBtn = compBtn

    packsAddon:OnLoad()
    guildCheckAddon:OnLoad()
    fishingAddon:OnLoad()
    spotTrackerAddon:OnLoad()
    zealAlertAddon:OnLoad()
    stopwatchAddon:OnLoad()

    api.On("UPDATE", OnUpdate)
end

local function OnUnload()
    if packsAddon then packsAddon:OnUnload(); packsAddon = nil end
    if guildCheckAddon then guildCheckAddon:OnUnload(); guildCheckAddon = nil end
    if fishingAddon then fishingAddon:OnUnload(); fishingAddon = nil end
    if spotTrackerAddon then spotTrackerAddon:OnUnload(); spotTrackerAddon = nil end
    if zealAlertAddon then zealAlertAddon:OnUnload(); zealAlertAddon = nil end
    if stopwatchAddon then stopwatchAddon:OnUnload(); stopwatchAddon = nil end

    if eluDisplayWindow then
        eluDisplayWindow:Show(false)
        api.Interface:Free(eluDisplayWindow)
        eluDisplayWindow = nil
    end
    
    if tripOverlay then
        tripOverlay:Show(false)
        api.Interface:Free(tripOverlay)
        tripOverlay = nil
    end
    
    if eluBtn then
        eluBtn:Show(false)
        api.Interface:Free(eluBtn)
        eluBtn = nil
    end
    
    api.On("UPDATE", function() return end)
end


elu_tracker_addon.OnLoad = OnLoad
elu_tracker_addon.OnUnload = OnUnload

return elu_tracker_addon
