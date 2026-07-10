local api = require("api")

local guild_check = {}

local f1Window = nil
local f1Bg = nil
local f1Label = nil

local f2Window = nil
local f2Label = nil

local settingsFile = "elu_guild_check.txt"

local settings = {
    enabled = false,
    f1_enabled = true,
    f1_size = 25,
    f1_bg_alpha = 0.2,
    f1_r = 1,
    f1_g = 1,
    f1_b = 1,
    f1_x = -999,
    f1_y = -999,
    f2_enabled = true,
    f2_size = 18,
    f2_r = 1,
    f2_g = 1,
    f2_b = 1,
    f2_x = -999,
    f2_y = -999,
    locked = false
}

local currentGuildText = nil

local function SaveSettings()
    local success, err = pcall(function()
        api.File:Write(settingsFile, settings)
    end)
    if not success then
        api.Log:Info("[Guild Check] Save ERROR: " .. tostring(err))
    end
end

local function LoadSettings()
    local success, err = pcall(function()
        local data = api.File:Read(settingsFile)
        if type(data) == "table" then
            if data.enabled ~= nil then settings.enabled = data.enabled end
            
            if data.f1_enabled ~= nil then settings.f1_enabled = data.f1_enabled end
            if data.f1_size ~= nil then settings.f1_size = data.f1_size end
            if data.f1_bg_alpha ~= nil then settings.f1_bg_alpha = data.f1_bg_alpha end
            if data.f1_r ~= nil then settings.f1_r = data.f1_r end
            if data.f1_g ~= nil then settings.f1_g = data.f1_g end
            if data.f1_b ~= nil then settings.f1_b = data.f1_b end
            if data.f1_x ~= nil then settings.f1_x = data.f1_x end
            if data.f1_y ~= nil then settings.f1_y = data.f1_y end
            
            if data.f2_enabled ~= nil then settings.f2_enabled = data.f2_enabled end
            if data.f2_size ~= nil then settings.f2_size = data.f2_size end
            if data.f2_r ~= nil then settings.f2_r = data.f2_r end
            if data.f2_g ~= nil then settings.f2_g = data.f2_g end
            if data.f2_b ~= nil then settings.f2_b = data.f2_b end
            if data.f2_x ~= nil then settings.f2_x = data.f2_x end
            if data.f2_y ~= nil then settings.f2_y = data.f2_y end
        end
    end)
    if not success then
        api.Log:Info("[Guild Check] Load ERROR: " .. tostring(err))
    end
end

LoadSettings()

local function ApplyVisuals()
    if f1Window and f1Label and f1Bg then
        if settings.f1_enabled and settings.enabled and currentGuildText then
            f1Window:Show(true)
            local text = "<" .. currentGuildText .. ">"
            f1Label.style:SetFontSize(settings.f1_size)
            f1Label.style:SetColor(settings.f1_r, settings.f1_g, settings.f1_b, 1)
            f1Label:SetText(text)
            
            local textLen = string.len(text)
            local baseW = textLen * settings.f1_size * 0.52
            local kerningK = math.floor(textLen * 1.45)
            local offset = -math.floor(kerningK / 2)
            
            f1Window:SetExtent(baseW + kerningK + 50, settings.f1_size + 10)
            
            f1Label:RemoveAllAnchors()
            f1Label:AddAnchor("TOPLEFT", f1Window, offset, 0)
            f1Label:AddAnchor("BOTTOMRIGHT", f1Window, offset, 0)
            
            f1Bg:SetColor(0, 0, 0, settings.f1_bg_alpha)
            f1Bg:RemoveAllAnchors()
            f1Bg:AddAnchor("TOPLEFT", f1Window, 0, 0)
            f1Bg:AddAnchor("BOTTOMRIGHT", f1Window, 0, 0)
        else
            f1Window:Show(false)
        end
    end
    
    if f2Window and f2Label then
        if settings.f2_enabled and settings.enabled and currentGuildText then
            f2Window:Show(true)
            local text = "<" .. currentGuildText .. ">"
            f2Label.style:SetFontSize(settings.f2_size)
            f2Label.style:SetColor(settings.f2_r, settings.f2_g, settings.f2_b, 1)
            f2Label:SetText(text)
            
            local textLen2 = string.len(text)
            local baseW2 = textLen2 * settings.f2_size * 0.52
            local kerningK2 = math.floor(textLen2 * 1.45)
            local offset2 = -math.floor(kerningK2 / 2)
            
            f2Window:SetExtent(baseW2 + kerningK2 + 20, settings.f2_size + 10)
            
            f2Label:RemoveAllAnchors()
            f2Label:AddAnchor("TOPLEFT", f2Window, offset2, 0)
            f2Label:AddAnchor("BOTTOMRIGHT", f2Window, offset2, 0)
        else
            f2Window:Show(false)
        end
    end
end

local lastTargetId = nil
local lastTargetGuild = nil

local function refreshGuildText()
    local targetId = api.Unit:GetUnitId("target")
    
    if targetId then
        local info = nil
        if api.Unit.UnitInfo then info = api.Unit:UnitInfo("target") end
        if not info and api.Unit.GetUnitInfoById then info = api.Unit:GetUnitInfoById(targetId) end
        
        local guildName = nil
        if info and (info.type == "character" or info.type == "slave" or info.type == "housing") then
            guildName = info.expeditionName
        end
        
        if targetId == lastTargetId and guildName == lastTargetGuild then
            return -- No changes, avoid redrawing
        end
        
        lastTargetId = targetId
        lastTargetGuild = guildName
        
        if guildName and guildName ~= "" then
            currentGuildText = guildName
            ApplyVisuals()
            return
        end
    else
        if lastTargetId == nil and lastTargetGuild == nil then
            return -- No changes
        end
        lastTargetId = nil
        lastTargetGuild = nil
    end
    
    currentGuildText = nil
    ApplyVisuals()
end

function guild_check:OnUpdate(dt)
    if not settings.enabled then return end
    local success, err = pcall(refreshGuildText)
    if not success then
        api.Log:Info("[Guild Check Debug] ERROR in refreshGuildText: " .. tostring(err))
    end
end

function guild_check:OnLoad()
    f1Window = api.Interface:CreateEmptyWindow("eluGuildCheck_F1", "UIParent")
    if settings.f1_x == -999 then
        f1Window:AddAnchor("CENTER", "UIParent", 0, -100)
    else
        f1Window:AddAnchor("CENTER", "UIParent", "TOPLEFT", settings.f1_x, settings.f1_y)
    end
    f1Window:Show(false)
    f1Window:EnableDrag(true)
    
    f1Bg = f1Window:CreateColorDrawable(0, 0, 0, settings.f1_bg_alpha, "background")
    f1Label = f1Window:CreateChildWidget("label", "f1Label", 0, true)
    f1Label:SetAutoResize(false)
    f1Label.style:SetAlign(ALIGN.CENTER)
    f1Label.style:SetShadow(true)
    f1Label.style:SetOutline(true)
    f1Label:AddAnchor("TOPLEFT", f1Window, 0, 0)
    f1Label:AddAnchor("BOTTOMRIGHT", f1Window, 0, 0)
    
    function f1Window:OnDragStart()
        if api.Input:IsShiftKeyDown() then
            self:StartMoving()
        end
    end
    f1Window:SetHandler("OnDragStart", f1Window.OnDragStart)

    function f1Window:OnDragStop()
        self:StopMovingOrSizing()
        local ox, oy = self:GetOffset()
        local w, h = self:GetExtent()
        if ox and oy and w and h then
            settings.f1_x = ox + (w / 2)
            settings.f1_y = oy + (h / 2)
            
            -- Re-anchor to center so it expands correctly immediately
            self:RemoveAllAnchors()
            self:AddAnchor("CENTER", "UIParent", "TOPLEFT", settings.f1_x, settings.f1_y)
        end
        SaveSettings()
    end
    f1Window:SetHandler("OnDragStop", f1Window.OnDragStop)

    -- Explicitly proxy label drags to the parent window
    f1Label:EnableDrag(true)
    f1Label:SetHandler("OnDragStart", function() f1Window:OnDragStart() end)
    f1Label:SetHandler("OnDragStop", function() f1Window:OnDragStop() end)

    f2Window = api.Interface:CreateEmptyWindow("eluGuildCheck_F2", "UIParent")
    if settings.f2_x == -999 then
        f2Window:AddAnchor("CENTER", "UIParent", 0, 150)
    else
        f2Window:AddAnchor("CENTER", "UIParent", "TOPLEFT", settings.f2_x, settings.f2_y)
    end
    f2Window:Show(false)
    f2Window:EnableDrag(true)
    
    f2Label = f2Window:CreateChildWidget("label", "f2Label", 0, true)
    f2Label:SetAutoResize(false)
    f2Label.style:SetAlign(ALIGN.CENTER)
    f2Label.style:SetShadow(true)
    f2Label.style:SetOutline(true)
    f2Label:AddAnchor("TOPLEFT", f2Window, 0, 0)
    f2Label:AddAnchor("BOTTOMRIGHT", f2Window, 0, 0)
    
    function f2Window:OnDragStart()
        if api.Input:IsShiftKeyDown() then
            self:StartMoving()
        end
    end
    f2Window:SetHandler("OnDragStart", f2Window.OnDragStart)

    function f2Window:OnDragStop()
        self:StopMovingOrSizing()
        local ox, oy = self:GetOffset()
        local w, h = self:GetExtent()
        if ox and oy and w and h then
            settings.f2_x = ox + (w / 2)
            settings.f2_y = oy + (h / 2)
            
            -- Re-anchor to center so it expands correctly immediately
            self:RemoveAllAnchors()
            self:AddAnchor("CENTER", "UIParent", "TOPLEFT", settings.f2_x, settings.f2_y)
        end
        SaveSettings()
    end
    f2Window:SetHandler("OnDragStop", f2Window.OnDragStop)

    -- Explicitly proxy label drags to the parent window
    f2Label:EnableDrag(true)
    f2Label:SetHandler("OnDragStart", function() f2Window:OnDragStart() end)
    f2Label:SetHandler("OnDragStop", function() f2Window:OnDragStop() end)

    ApplyVisuals()
end

function guild_check:OnUnload()
    if f1Window then
        f1Window:Show(false)
        f1Window:RemoveAllAnchors()
    end
    if f2Window then
        f2Window:Show(false)
        f2Window:RemoveAllAnchors()
    end
    api.Log:Info("[Guild Check] Unloaded successfully.")
end

function guild_check.CreateUI(container)
    local title = container:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetText("Guild Check Settings")
    title.style:SetFontSize(22)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:AddAnchor("TOP", container, 0, 25)

    local function CreateFancyCheck(parent, name, lblText)
        local chk = parent:CreateChildWidget("checkbutton", name, 0, true)
        chk:SetExtent(18, 17)
        local bg1 = chk:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg1:SetExtent(18, 17)
        bg1:AddAnchor("CENTER", chk, 0, 0)
        bg1:SetCoords(0, 0, 18, 17)
        chk:SetNormalBackground(bg1)
        
        local bg2 = chk:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg2:SetExtent(18, 17)
        bg2:AddAnchor("CENTER", chk, 0, 0)
        bg2:SetCoords(18, 0, 18, 17)
        chk:SetCheckedBackground(bg2)
        
        local lbl = parent:CreateChildWidget("label", name.."Lbl", 0, true)
        lbl:SetAutoResize(true)
        lbl:SetText(lblText)
        lbl:AddAnchor("LEFT", chk, "RIGHT", 5, 0)
        ApplyTextColor(lbl, FONT_COLOR.DEFAULT)
        
        return chk
    end

    local function CreateSliderStepper(parent, name, lblText, initVal, minVal, maxVal, onChange)
        local grp = parent:CreateChildWidget("emptywidget", name.."Grp", 0, true)
        grp:SetExtent(160, 20)
        
        local lbl = grp:CreateChildWidget("label", name.."Lbl", 0, true)
        lbl:SetAutoResize(true)
        lbl:SetText(lblText)
        lbl:AddAnchor("LEFT", grp, 0, 0)
        ApplyTextColor(lbl, FONT_COLOR.DEFAULT)
        
        local btnMinus = grp:CreateChildWidget("button", name.."Minus", 0, true)
        btnMinus:SetExtent(20, 20)
        btnMinus:AddAnchor("LEFT", lbl, "RIGHT", 5, 0)
        btnMinus:SetText("-")
        ApplyButtonSkin(btnMinus, BUTTON_BASIC.DEFAULT)
        
        local valLbl = grp:CreateChildWidget("label", name.."Val", 0, true)
        valLbl:SetAutoResize(true)
        valLbl:SetText(tostring(initVal))
        valLbl:AddAnchor("LEFT", btnMinus, "RIGHT", 5, 0)
        ApplyTextColor(valLbl, FONT_COLOR.DEFAULT)
        
        local btnPlus = grp:CreateChildWidget("button", name.."Plus", 0, true)
        btnPlus:SetExtent(20, 20)
        btnPlus:AddAnchor("LEFT", valLbl, "RIGHT", 5, 0)
        btnPlus:SetText("+")
        ApplyButtonSkin(btnPlus, BUTTON_BASIC.DEFAULT)
        
        local currentVal = initVal
        local function UpdateValue(newVal)
            if newVal >= minVal and newVal <= maxVal then
                currentVal = newVal
                valLbl:SetText(tostring(currentVal))
                onChange(currentVal)
            end
        end

        grp.SetValue = function(self, v)
            currentVal = v
            valLbl:SetText(tostring(currentVal))
        end
        
        function btnMinus:OnClick() UpdateValue(currentVal - 1) end
        btnMinus:SetHandler("OnClick", btnMinus.OnClick)
        
        function btnPlus:OnClick() UpdateValue(currentVal + 1) end
        btnPlus:SetHandler("OnClick", btnPlus.OnClick)
        
        return grp
    end

    local colors = {
        {r=1, g=1, b=1}, {r=1, g=0, b=0}, {r=0, g=1, b=0}, 
        {r=0, g=0, b=1}, {r=1, g=1, b=0}, {r=0.6, g=0.6, b=0.6}
    }

    local function CreateColorPicker(parent, name, startX, startY, onColorSelect)
        local btnX = startX
        for i, c in ipairs(colors) do
            local btn = parent:CreateChildWidget("button", name.."Btn"..i, 0, true)
            btn:SetExtent(20, 20)
            btn:AddAnchor("TOPLEFT", parent, btnX, startY)
            
            local bg = btn:CreateColorDrawable(c.r, c.g, c.b, 1, "background")
            bg:AddAnchor("TOPLEFT", btn, 0, 0)
            bg:AddAnchor("BOTTOMRIGHT", btn, 0, 0)
            
            function btn:OnClick() onColorSelect(c.r, c.g, c.b) end
            btn:SetHandler("OnClick", btn.OnClick)
            btnX = btnX + 25
        end
    end


    local enableCheck = CreateFancyCheck(container, "enableCheck", "Enable Guild Check")
    enableCheck:AddAnchor("TOP", title, "BOTTOM", -50, 20)
    
    local panel = container:CreateChildWidget("emptywidget", "panel", 0, true)
    panel:SetExtent(500, 300)
    panel:AddAnchor("TOP", enableCheck, "BOTTOM", 0, 15)
    
    local helpLbl = panel:CreateChildWidget("label", "helpLbl", 0, true)
    helpLbl:SetAutoResize(true)
    helpLbl:AddAnchor("TOP", panel, "TOP", 0, 10)
    helpLbl:SetText("To move frames: Target a player, hold SHIFT, and drag the text.")
    ApplyTextColor(helpLbl, {0.3, 0.8, 1, 1})
    
    local resetContainer = panel:CreateChildWidget("emptywidget", "resetContainer", 0, true)
    resetContainer:SetExtent(250, 30)
    resetContainer:AddAnchor("TOP", helpLbl, "BOTTOM", 15, 25)

    local resetBtn = resetContainer:CreateChildWidget("button", "resetBtn", 0, true)
    resetBtn:SetExtent(120, 30)
    resetBtn:AddAnchor("LEFT", resetContainer, "LEFT", 0, 0)
    resetBtn:SetText("Reset Positions")
    ApplyButtonSkin(resetBtn, BUTTON_BASIC.DEFAULT)

    local resetDefBtn = resetContainer:CreateChildWidget("button", "resetDefBtn", 0, true)
    resetDefBtn:SetExtent(120, 30)
    resetDefBtn:AddAnchor("RIGHT", resetContainer, "RIGHT", 0, 0)
    resetDefBtn:SetText("Reset Defaults")
    ApplyButtonSkin(resetDefBtn, BUTTON_BASIC.DEFAULT)

    local f1SizeGrp, f1AlphaGrp, f2SizeGrp

    function resetDefBtn:OnClick()
        settings.f1_size = 25
        settings.f1_r = 1; settings.f1_g = 1; settings.f1_b = 1
        settings.f1_bg_alpha = 0.2
        settings.f2_size = 18
        settings.f2_r = 1; settings.f2_g = 1; settings.f2_b = 1
        
        if f1SizeGrp then f1SizeGrp:SetValue(25) end
        if f1AlphaGrp then f1AlphaGrp:SetValue(2) end
        if f2SizeGrp then f2SizeGrp:SetValue(18) end
        
        SaveSettings()
        ApplyVisuals()
        api.Log:Info("[Guild Check] Defaults applied.")
    end
    resetDefBtn:SetHandler("OnClick", resetDefBtn.OnClick)

    function resetBtn:OnClick()
        settings.f1_x = -999
        settings.f1_y = -999
        settings.f2_x = -999
        settings.f2_y = -999
        SaveSettings()
        if f1Window then
            f1Window:RemoveAllAnchors()
            f1Window:AddAnchor("CENTER", "UIParent", 0, -100)
        end
        if f2Window then
            f2Window:RemoveAllAnchors()
            f2Window:AddAnchor("CENTER", "UIParent", 0, 150)
        end
        api.Log:Info("[Guild Check] Frame positions reset to default.")
    end
    resetBtn:SetHandler("OnClick", resetBtn.OnClick)

    local col1_x = 75
    
    local f1Title = panel:CreateChildWidget("label", "f1Title", 0, true)
    f1Title:SetAutoResize(true)
    f1Title:SetText("Frame 1 (with BG)")
    f1Title.style:SetFontSize(16)
    ApplyTextColor(f1Title, {0.3, 0.6, 1, 1})
    f1Title:AddAnchor("TOPLEFT", panel, col1_x, 90)

    local f1Check = CreateFancyCheck(panel, "f1Check", "Show Frame 1")
    f1Check:AddAnchor("TOPLEFT", panel, col1_x, 120)
    f1Check:SetChecked(settings.f1_enabled, false)
    function f1Check:OnCheckChanged()
        settings.f1_enabled = self:GetChecked()
        ApplyVisuals()
        SaveSettings()
    end
    f1Check:SetHandler("OnCheckChanged", f1Check.OnCheckChanged)

    f1SizeGrp = CreateSliderStepper(panel, "f1SizeGrp", "Font Size:", settings.f1_size, 10, 50, function(val)
        settings.f1_size = val
        ApplyVisuals()
        SaveSettings()
    end)
    f1SizeGrp:AddAnchor("TOPLEFT", panel, col1_x, 155)

    local cLbl1 = panel:CreateChildWidget("label", "cLbl1", 0, true)
    cLbl1:SetAutoResize(true)
    cLbl1:SetText("Text Color:")
    cLbl1:AddAnchor("TOPLEFT", panel, col1_x, 195)
    ApplyTextColor(cLbl1, FONT_COLOR.DEFAULT)

    CreateColorPicker(panel, "f1ColorPicker", col1_x, 220, function(r, g, b)
        settings.f1_r = r
        settings.f1_g = g
        settings.f1_b = b
        ApplyVisuals()
        SaveSettings()
    end)

    f1AlphaGrp = CreateSliderStepper(panel, "f1AlphaGrp", "BG Intensity (1-10):", math.floor(settings.f1_bg_alpha * 10), 0, 10, function(val)
        settings.f1_bg_alpha = val / 10.0
        ApplyVisuals()
        SaveSettings()
    end)
    f1AlphaGrp:AddAnchor("TOPLEFT", panel, col1_x, 260)

    local col2_x = 305
    
    local f2Title = panel:CreateChildWidget("label", "f2Title", 0, true)
    f2Title:SetAutoResize(true)
    f2Title:SetText("Frame 2")
    f2Title.style:SetFontSize(16)
    ApplyTextColor(f2Title, {0.3, 0.6, 1, 1})
    f2Title:AddAnchor("TOPLEFT", panel, col2_x, 90)

    local f2Check = CreateFancyCheck(panel, "f2Check", "Show Frame 2")
    f2Check:AddAnchor("TOPLEFT", panel, col2_x, 120)
    f2Check:SetChecked(settings.f2_enabled, false)
    function f2Check:OnCheckChanged()
        settings.f2_enabled = self:GetChecked()
        ApplyVisuals()
        SaveSettings()
    end
    f2Check:SetHandler("OnCheckChanged", f2Check.OnCheckChanged)

    f2SizeGrp = CreateSliderStepper(panel, "f2SizeGrp", "Font Size:", settings.f2_size, 10, 50, function(val)
        settings.f2_size = val
        ApplyVisuals()
        SaveSettings()
    end)
    f2SizeGrp:AddAnchor("TOPLEFT", panel, col2_x, 155)

    local cLbl2 = panel:CreateChildWidget("label", "cLbl2", 0, true)
    cLbl2:SetAutoResize(true)
    cLbl2:SetText("Text Color:")
    cLbl2:AddAnchor("TOPLEFT", panel, col2_x, 195)
    ApplyTextColor(cLbl2, FONT_COLOR.DEFAULT)

    CreateColorPicker(panel, "f2ColorPicker", col2_x, 220, function(r, g, b)
        settings.f2_r = r
        settings.f2_g = g
        settings.f2_b = b
        ApplyVisuals()
        SaveSettings()
    end)

    local function UpdateVisibility()
        panel:Show(settings.enabled)
    end

    enableCheck:SetChecked(settings.enabled, false)
    UpdateVisibility()

    function enableCheck:OnCheckChanged()
        settings.enabled = self:GetChecked()
        api.Log:Info("[Guild Check] Status: " .. (settings.enabled and "ON" or "OFF"))
        SaveSettings()
        UpdateVisibility()
        ApplyVisuals()
    end
    enableCheck:SetHandler("OnCheckChanged", enableCheck.OnCheckChanged)
end

return guild_check
