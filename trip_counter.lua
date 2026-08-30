local trip_counter = {}

local tripOverlay
local tripCount = 0
local tripPosFile = "elu_tracker_settings.lua"

function trip_counter.OnLoad()
    tripOverlay = api.Interface:CreateEmptyWindow("tripOverlay", "UIParent")
    tripOverlay:SetExtent(160, 90)
    tripOverlay:AddAnchor("TOPLEFT", "UIParent", 300, 100)
    tripOverlay:Show(false)
    tripOverlay:EnableDrag(true)

    local function SaveTripPos()
    if tripOverlay then
        local x, y = tripOverlay:GetOffset()
        if x and y then
            pcall(function()
                if api.File and api.File.Read and api.File.Write then
                    local data = api.File:Read(tripPosFile)
                    if type(data) ~= "table" then data = {} end
                    data.tripPos = { x = x, y = y }
                    api.File:Write(tripPosFile, data)
                end
            end)
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
    local function ApplyTextColor(widget, color) widget.style:SetColor(color[1], color[2], color[3], color[4]) end
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
    api.Interface:ApplyButtonSkin(compBtn, BUTTON_BASIC.DEFAULT)

    function compBtn:OnClick()
        tripCount = (tripCount or 0) + 1
        countLabel:SetText("Trip: " .. tostring(tripCount or 0))
    end
    compBtn:SetHandler("OnClick", compBtn.OnClick)
    tripOverlay.compBtn = compBtn
end

function trip_counter.Toggle()
    if tripOverlay then
        local isVis = not tripOverlay:IsVisible()
        tripOverlay:Show(isVis)
    end
end

function trip_counter.OnUnload()
    if tripOverlay then
        tripOverlay:Show(false)
        tripOverlay = nil
    end
end

return trip_counter
