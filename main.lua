local elu_tracker_addon = {
	name = "Elu Tracker",
	author = "Eludelu",
	version = "2.0",
	desc = "Commerce & Fishing tools.",
	tags = {"Economy", "Fishing", "QoL"}
}

local packsAddon = require("Elu_Tracker/packs")
local guildCheckAddon = require("Elu_Tracker/guild_check")
local fishingAddon = require("Elu_Tracker/fishing")
local fishTrackerAddon = require("Elu_Tracker/fish_tracker")
local raidInviteAddon = require("Elu_Tracker/raid_invite")
local spotTrackerAddon = require("Elu_Tracker/spot_tracker")
local zealAlertAddon = require("Elu_Tracker/zeal_alert")
local stopwatchAddon = require("Elu_Tracker/stopwatch")
eluDisplayWindow = nil
local eluWasVisible = false
local eluBtn

local tripOverlay
local tripCount = 0
local eluCharcoalLabel = nil
local priceUpdateTimer = 0
local _charcoalInputRef = nil
local _charcoalSilverInputRef = nil
local _dragonInputRef = nil
local _dragonSilverInputRef = nil
local _pollTimer = 0

local function ConvertColor(color) return color / 255 end 

local memoryAHPrices = nil

local function LoadAHPrices()
    if not memoryAHPrices then
        local status, data = pcall(require, "Elu_Tracker/data/auction_house_prices")
        if status and type(data) == "table" then
            memoryAHPrices = data
        else
            memoryAHPrices = {
                [32103] = { average = 1.5 },
                [32106] = { average = 22 }
            }
        end
        local dataFile = api.File:Read("elu_commerce_prices.txt")
        if type(dataFile) == "table" then
            if dataFile.c ~= nil and memoryAHPrices[32103] then memoryAHPrices[32103].average = tonumber(dataFile.c) or memoryAHPrices[32103].average end
            if dataFile.d ~= nil and memoryAHPrices[32106] then memoryAHPrices[32106].average = tonumber(dataFile.d) or memoryAHPrices[32106].average end
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
    
    if fishTrackerAddon and fishTrackerAddon.OnUpdate then
        fishTrackerAddon:OnUpdate(dt)
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
    
    if guildCheckAddon and guildCheckAddon.OnUpdate then
        guildCheckAddon:OnUpdate(dt)
    end
    
    if spotTrackerAddon and spotTrackerAddon.OnUpdate then
        spotTrackerAddon:OnUpdate(dt)
    end
    
    if stopwatchAddon and stopwatchAddon.OnUpdate then
        stopwatchAddon:OnUpdate(dt)
    end
    
    if zealAlertAddon and zealAlertAddon.OnUpdate then
        zealAlertAddon:OnUpdate(dt)
    end
    
    if eluDisplayWindow then
        local isVis = eluDisplayWindow:IsVisible()
        if eluWasVisible and not isVis then
            if guildCheckAddon and guildCheckAddon.OnMainWindowHide then
                guildCheckAddon.OnMainWindowHide()
            end
        end
        eluWasVisible = isVis
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

    -- Set Price UI removed

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
    
    if guildCheckAddon and guildCheckAddon.CreateUI then
        guildCheckAddon.CreateUI(wnd)
    end
    
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

    if fishTrackerAddon and fishTrackerAddon.CreateUI then
        fishTrackerAddon.CreateUI(wnd)
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
        local finalPath = file
        local dataSessionsPath = "Elu_Tracker/data_sessions/" .. file
        local dataPath = "Elu_Tracker/data/" .. file
        
        local currentData = api.File:Read(finalPath)
        if type(currentData) ~= "table" then
            local dsData = api.File:Read(dataSessionsPath)
            if type(dsData) == "table" then
                api.File:Write(finalPath, dsData)
                api.File:Write(dataSessionsPath, {})
            else
                local oldData = api.File:Read(dataPath)
                if type(oldData) == "table" then
                    api.File:Write(finalPath, oldData)
                    api.File:Write(dataPath, {})
                end
            end
        end
    end

    LoadAHPrices()
    packsAddon = require("Elu_Tracker/packs")
    guildCheckAddon = require("Elu_Tracker/guild_check")
    fishingAddon = require("Elu_Tracker/fishing")
    fishTrackerAddon = require("Elu_Tracker/fish_tracker")
    raidInviteAddon = require("Elu_Tracker/raid_invite")
    spotTrackerAddon = require("Elu_Tracker/spot_tracker")
    lootTrackerAddon = require("Elu_Tracker/loot")

    function CreateLootTrackerWindow(wndParent)
        local wnd = wndParent:CreateChildWidget("emptywidget", "lootWindow", 0, true)
        wnd:SetExtent(600, 600)
        wnd:AddAnchor("TOP", wndParent, 0, 0)
        
        local sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wnd)
        sessionScrollList:Show(true)
        sessionScrollList:AddAnchor("TOPLEFT", wnd, 4, 10)
        sessionScrollList:AddAnchor("BOTTOMRIGHT", wnd, -4, -60)
        
        return wnd
    end
    
    local tabInfo = {
        {
            validationCheckFunc = function() return true end,
            title = "Commerce",
            subWindowConstructor = function(parent) CreateCommerceWindow(parent) end
        },
        {
            validationCheckFunc = function() return true end,
            title = "Loot Tracker",
            subWindowConstructor = function(parent) CreateLootTrackerWindow(parent) end
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
        },
        {
            validationCheckFunc = function() return true end,
            title = "Guild Check",
            subWindowConstructor = function(parent) CreateGuildCheckWindow(parent) end
        }
    }
    
    eluDisplayWindow = api.Interface:CreateWindow("eluDisplayWindow", "Elu Tracker", 600, 840, tabInfo)
    eluDisplayWindow:AddAnchor("CENTER", "UIParent", 0, 0)
    eluDisplayWindow:Show(false)
    eluWasVisible = false
    
    if eluDisplayWindow.titleBar and eluDisplayWindow.titleBar.bg then
        eluDisplayWindow.titleBar.bg:SetColor(ConvertColor(40), ConvertColor(44), ConvertColor(52), 1.0) 
    end
    if eluDisplayWindow.bg then
        eluDisplayWindow.bg:SetColor(ConvertColor(24), ConvertColor(26), ConvertColor(31), 0.95) 
    end

    local bagFrame = ADDON:GetContent(UIC.BAG)
    
    if bagFrame.eluBtn then
        bagFrame.eluBtn:Show(false)
        bagFrame.eluBtn:RemoveAllAnchors()
    end

    eluBtn = bagFrame:CreateChildWidget("button", "eluBtn", 0, true)
    eluBtn:AddAnchor("BOTTOMLEFT", bagFrame.expandBtn, -55, 5)
    eluBtn:SetExtent(50, 50)
    
    local blankBg = eluBtn:CreateColorDrawable(0,0,0,0, "background")
    eluBtn:SetNormalBackground(blankBg)
    eluBtn:SetPushedBackground(blankBg)
    eluBtn:SetHighlightBackground(blankBg)
    eluBtn:SetDisabledBackground(blankBg)
    
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

    local tripPosFile = "elu_trip_pos.txt"
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
    fishTrackerAddon:OnLoad()
    if raidInviteAddon and raidInviteAddon.OnLoad then raidInviteAddon.OnLoad() end
    spotTrackerAddon:OnLoad()
    zealAlertAddon:OnLoad()
    stopwatchAddon:OnLoad()
    lootTrackerAddon:OnLoad()

    api.On("UPDATE", OnUpdate)
    if api.Log and api.Log.Info then api.Log:Info("[Elu Tracker] Loaded Successfully!") end
end

local function OnUnload()
    if packsAddon then packsAddon:OnUnload(); packsAddon = nil end
    if guildCheckAddon then guildCheckAddon:OnUnload(); guildCheckAddon = nil end
    if fishingAddon then fishingAddon:OnUnload(); fishingAddon = nil end
    if fishTrackerAddon then fishTrackerAddon:OnUnload(); fishTrackerAddon = nil end
    if raidInviteAddon and raidInviteAddon.OnUnload then raidInviteAddon.OnUnload(); raidInviteAddon = nil end
    if spotTrackerAddon then spotTrackerAddon:OnUnload(); spotTrackerAddon = nil end
    if zealAlertAddon then zealAlertAddon:OnUnload(); zealAlertAddon = nil end
    if stopwatchAddon then stopwatchAddon:OnUnload(); stopwatchAddon = nil end
    if lootTrackerAddon then lootTrackerAddon:OnUnload(); lootTrackerAddon = nil end

    if eluDisplayWindow then
        eluDisplayWindow:Show(false)
        eluDisplayWindow:Show(false)
        eluDisplayWindow = nil
    end
    
    if tripOverlay then
        tripOverlay:Show(false)
        tripOverlay:Show(false)
        tripOverlay = nil
    end
    
    if eluBtn then
        eluBtn:Show(false)
        eluBtn:Show(false)
        eluBtn = nil
    end
    
    api.On("UPDATE", function() return end)
end


elu_tracker_addon.OnLoad = OnLoad
elu_tracker_addon.OnUnload = OnUnload

return elu_tracker_addon
