local elu_tracker_addon = {
	name = "Elu Tracker",
	author = "Eludelu",
	version = "1.0",
	desc = "Commerce & Fishing track and Trip Counter."
}

local packsAddon = require("elu_tracker/packs")
local lootAddon = require("elu_tracker/loot")
local fishingAddon = require("elu_tracker/fishing")

eluDisplayWindow = nil
local eluBtn

local tripOverlay
local tripCount = 0
local eluCharcoalLabel = nil
local priceUpdateTimer = 0

local function ConvertColor(color) return color / 255 end 

local memoryAHPrices = nil

local function LoadAHPrices()
    if not memoryAHPrices then
        -- Define os valores padrões de fábrica caso o usuário nunca tenha salvo nada
        memoryAHPrices = {
            [32103] = { average = 1.50, volume = 1 },
            [32106] = { average = 20.00, volume = 1 }
        }
        -- Carrega direto do banco de dados persistente de configurações nativas do jogo
        local settings = api.GetSettings("elu_tracker")
        if settings and type(settings.manualPrices) == "table" then
            if settings.manualPrices[32103] then memoryAHPrices[32103].average = settings.manualPrices[32103] end
            if settings.manualPrices[32106] then memoryAHPrices[32106].average = settings.manualPrices[32106] end
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

local function SetManualPrices(charcoalStr, dragonStr)
    LoadAHPrices()
    
    -- Sanitização inteligente: remove letras/espaços mantendo apenas números e pontuações válidas
    local cClean = string.gsub(string.gsub(tostring(charcoalStr or ""), ",", "."), "[^0-9.]", "")
    local dClean = string.gsub(string.gsub(tostring(dragonStr or ""), ",", "."), "[^0-9.]", "")

    local charcoalVal = tonumber(cClean)
    local dragonVal = tonumber(dClean)

    -- Template Automático: Se digitou sem ponto/vírgula (Ex: 150 ou 2000), o sistema calcula os centavos sozinho
    if charcoalVal and charcoalVal > 100 and not string.find(tostring(charcoalStr), "[.,]") then charcoalVal = charcoalVal / 100 end
    if dragonVal and dragonVal > 1000 and not string.find(tostring(dragonStr), "[.,]") then dragonVal = dragonVal / 100 end

    -- Fallbacks de segurança se o campo vier vazio
    charcoalVal = charcoalVal or memoryAHPrices[32103].average
    dragonVal = dragonVal or memoryAHPrices[32106].average

    memoryAHPrices[32103].average = charcoalVal
    memoryAHPrices[32106].average = dragonVal

    -- Salva de forma robusta e limpa no arquivo de persistência do jogo
    local settings = api.GetSettings("elu_tracker")
    if settings then
        if not settings.manualPrices then settings.manualPrices = {} end
        settings.manualPrices[32103] = charcoalVal
        settings.manualPrices[32106] = dragonVal
        api.SaveSettings()
    end

    -- Força a atualização do texto principal no mesmo milissegundo do clique
    if eluCharcoalLabel then
        eluCharcoalLabel:SetText(string.format("Charcoal: %.4fg | Dragon: %.4fg", charcoalVal, dragonVal))
    end
    api.Log:Info(string.format("[Elu Tracker] Preços atualizados: Charcoal: %.2fg | Dragon: %.2fg", charcoalVal, dragonVal))
end
local bagFrameFixed = false
local function OnUpdate(dt)
    priceUpdateTimer = priceUpdateTimer + (type(dt) == "number" and dt or 0)
    if priceUpdateTimer > 2000 then 
        priceUpdateTimer = 0
        if eluCharcoalLabel and eluCharcoalLabel:IsVisible() then
            local charcoalPrice = GetAHPriceSafe(32103)
            local dragonPrice = GetAHPriceSafe(32106)
            eluCharcoalLabel:SetText(string.format("Charcoal: %.4fg | Dragon: %.4fg", charcoalPrice, dragonPrice))
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
    charcoalLabel:SetText("Fetching Prices...")
    charcoalLabel:AddAnchor("TOP", title, "BOTTOM", 0, 15)
    eluCharcoalLabel = charcoalLabel

    local setPriceBtn = wnd:CreateChildWidget("button", "setPriceBtn", 0, true)
    setPriceBtn:SetText("Set Price")
    setPriceBtn:SetExtent(80, 25)
    setPriceBtn:AddAnchor("TOPRIGHT", wnd, -15, 10)
    ApplyButtonSkin(setPriceBtn, BUTTON_BASIC.DEFAULT)

 
-- Painel expansível (escondido por padrão)
    local pricePanel = wnd:CreateChildWidget("emptywidget", "pricePanel", 0, true)
    pricePanel:SetExtent(160, 110)
    pricePanel:AddAnchor("TOPRIGHT", setPriceBtn, "BOTTOMRIGHT", 0, 5)
    pricePanel:Show(false)

    local pBg = pricePanel:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    pBg:SetTextureInfo("bg_quest")
    pBg:SetColor(0, 0, 0, 0.95)
    pBg:AddAnchor("TOPLEFT", pricePanel, 0, 0)
    pBg:AddAnchor("BOTTOMRIGHT", pricePanel, 0, 0)

    -- Input do Charcoal (Alinhado com precisão)
    local charcoalInput = pricePanel:CreateChildWidget("editbox", "charcoalInput", 0, true)
    charcoalInput:SetExtent(50, 20)
    charcoalInput:AddAnchor("TOPRIGHT", pricePanel, -15, 15)
    charcoalInput.style:SetAlign(ALIGN.CENTER)
    local cbg = charcoalInput:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    cbg:SetTextureInfo("bg_quest")
    cbg:SetColor(0, 0, 0, 0.6)
    cbg:AddAnchor("TOPLEFT", charcoalInput, -2, -2)
    cbg:AddAnchor("BOTTOMRIGHT", charcoalInput, 2, 2)

    local charcoalLabel = pricePanel:CreateChildWidget("label", "charcoalLabel", 0, true)
    charcoalLabel:SetText("Charcoal:")
    charcoalLabel:AddAnchor("RIGHT", charcoalInput, "LEFT", -10, 0)
    ApplyTextColor(charcoalLabel, FONT_COLOR.DEFAULT)

    -- Input do Dragon
    local dragonInput = pricePanel:CreateChildWidget("editbox", "dragonInput", 0, true)
    dragonInput:SetExtent(50, 20)
    dragonInput:AddAnchor("TOPRIGHT", charcoalInput, "BOTTOMRIGHT", 0, 10)
    dragonInput.style:SetAlign(ALIGN.CENTER)
    local dbg = dragonInput:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    dbg:SetTextureInfo("bg_quest")
    dbg:SetColor(0, 0, 0, 0.6)
    dbg:AddAnchor("TOPLEFT", dragonInput, -2, -2)
    dbg:AddAnchor("BOTTOMRIGHT", dragonInput, 2, 2)

    local dragonLabel = pricePanel:CreateChildWidget("label", "dragonLabel", 0, true)
    dragonLabel:SetText("Dragon:")
    dragonLabel:AddAnchor("RIGHT", dragonInput, "LEFT", -10, 0)
    ApplyTextColor(dragonLabel, FONT_COLOR.DEFAULT)

    -- Botão Save
    local savePriceBtn = pricePanel:CreateChildWidget("button", "savePriceBtn", 0, true)
    savePriceBtn:SetText("Save")
    savePriceBtn:SetExtent(60, 24)
    savePriceBtn:AddAnchor("BOTTOM", pricePanel, 0, -10)
    ApplyButtonSkin(savePriceBtn, BUTTON_BASIC.DEFAULT)

    -- Toggle (Abre/Fecha a janela)
    function setPriceBtn:OnClick()
        local isVisible = pricePanel:IsVisible()
        if not isVisible then
            pricePanel:Raise()
            charcoalInput:SetText(string.format("%.2f", GetAHPriceSafe(32103)))
            dragonInput:SetText(string.format("%.2f", GetAHPriceSafe(32106)))
        end
        pricePanel:Show(not isVisible)
    end
    setPriceBtn:SetHandler("OnClick", setPriceBtn.OnClick)

    -- Salva o preço e encolhe a janela
    local function SaveAndClose()
        SetManualPrices(charcoalInput:GetText(), dragonInput:GetText())
        pricePanel:Show(false)
        charcoalInput:ClearFocus()
        dragonInput:ClearFocus()
        priceUpdateTimer = 2000 -- Força atualização imediata do texto da aba
    end

    function savePriceBtn:OnClick() SaveAndClose() end
    savePriceBtn:SetHandler("OnClick", savePriceBtn.OnClick)

    function charcoalInput:OnEnterPressed() SaveAndClose() end
    charcoalInput:SetHandler("OnEnterPressed", charcoalInput.OnEnterPressed)

    function dragonInput:OnEnterPressed() SaveAndClose() end
    dragonInput:SetHandler("OnEnterPressed", dragonInput.OnEnterPressed)
    
    local sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wnd)
    sessionScrollList:Show(true)
    sessionScrollList:AddAnchor("TOPLEFT", wnd, 4, 40)
    sessionScrollList:AddAnchor("BOTTOMRIGHT", wnd, -4, -4)
    return wnd
end 

local function CreateLootTrackerWindow(wndParent)
    local wnd = wndParent:CreateChildWidget("emptywidget", "lootWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Loot Tracker")
    title:AddAnchor("TOP", wnd, 0, 10)
    
    local sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wnd)
    sessionScrollList:Show(true)
    sessionScrollList:AddAnchor("TOPLEFT", wnd, 4, 4)
    sessionScrollList:AddAnchor("BOTTOMRIGHT", wnd, -4, -4)
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

local function CreateTripCounterWindow(wndParent)
    local wnd = wndParent:CreateChildWidget("emptywidget", "tripWindow", 0, true)
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
    toggleBtn:SetText("Toggle Overlay")
    toggleBtn:AddAnchor("TOP", desc, "BOTTOM", 0, 20)
    ApplyButtonSkin(toggleBtn, BUTTON_BASIC.DEFAULT)
    function toggleBtn:OnClick()
        if tripOverlay then
            local isVisible = not tripOverlay:IsVisible()
            tripOverlay:Show(isVisible)
            tripOverlay.countLabel:SetText("Trip: " .. tostring(tripCount or 0))
        end
    end
    toggleBtn:SetHandler("OnClick", toggleBtn.OnClick)

    local resetBtn = wnd:CreateChildWidget("button", "resetBtn", 0, true)
    resetBtn:SetText("Reset Progress")
    resetBtn:AddAnchor("TOP", toggleBtn, "BOTTOM", 0, 10)
    ApplyButtonSkin(resetBtn, BUTTON_BASIC.DEFAULT)
    function resetBtn:OnClick()
        tripCount = 0
        if tripOverlay and tripOverlay.countLabel then
            tripOverlay.countLabel:SetText("Trip: " .. tostring(tripCount or 0))
        end
        api.Log:Info("[Elu Tracker] Trip Counter has been reset.")
    end
    resetBtn:SetHandler("OnClick", resetBtn.OnClick)

    return wnd
end

local function OnLoad()
    LoadAHPrices()
    packsAddon = require("elu_tracker/packs")
    lootAddon = require("elu_tracker/loot")
    fishingAddon = require("elu_tracker/fishing")
    
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
            title = "Trip Counter",
            subWindowConstructor = function(parent) CreateTripCounterWindow(parent) end
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

    function tripOverlay:OnDragStart() self:StartMoving() end
    tripOverlay:SetHandler("OnDragStart", tripOverlay.OnDragStart)

    function tripOverlay:OnDragStop() self:StopMovingOrSizing() end
    tripOverlay:SetHandler("OnDragStop", tripOverlay.OnDragStop)
    
    local bg = tripOverlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.7)
    bg:AddAnchor("TOPLEFT", tripOverlay, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", tripOverlay, 0, 0)
    
    local closeBtn = tripOverlay:CreateChildWidget("button", "closeBtn", 0, true)
    closeBtn:SetText("X")
    closeBtn:SetExtent(15, 15)
    closeBtn:AddAnchor("TOPRIGHT", tripOverlay, -2, 2)
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
    lootAddon:OnLoad()
    fishingAddon:OnLoad()

    api.On("UPDATE", OnUpdate)
end

local function OnUnload()
    if packsAddon then packsAddon:OnUnload(); packsAddon = nil end
    if lootAddon then lootAddon:OnUnload(); lootAddon = nil end
    if fishingAddon then fishingAddon:OnUnload(); fishingAddon = nil end

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