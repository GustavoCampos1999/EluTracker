local api = require('api')
local settingsManager = require('Elu_Tracker/settings_manager')
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local quick_equip_addon = {}

local GEAR_PIECES = { 1, 3, 4, 8, 6, 9, 5, 7, 15, 2, 10, 11, 12, 13, 16, 17, 18, 19, 28 }
local ALT_SLOTS = { [11] = true, [13] = true, [17] = true }

local settings = {
    enabled = false,
    x = 200,
    y = 40,
    gear_sets = {}
}

local DEFAULT_X = 200
local DEFAULT_Y = 40

local currentCharKey = nil
local charCheckTimer = 0
local enableCheckWidget = nil

local function GetCurrentCharKey()
    local charName = nil
    pcall(function()
        local id = api.Unit:GetUnitId("player")
        if id then
            local name = api.Unit:GetUnitNameById(id)
            if type(name) == "string" then
                name = name:gsub("^%s*(.-)%s*$", "%1")
                if name ~= "" then
                    charName = string.lower(name)
                end
            end
        end
    end)
    return charName
end

local function CloneGearSets(src)
    if type(src) ~= "table" then return {} end
    local copy = {}
    for i, set in ipairs(src) do
        if type(set) == "table" then
            local gearCopy = {}
            if type(set.gear) == "table" then
                for j, item in ipairs(set.gear) do
                    if type(item) == "table" then
                        gearCopy[j] = {
                            name = item.name,
                            grade = item.grade,
                            slot = item.slot,
                            alternative = item.alternative,
                        }
                    end
                end
            end
            copy[i] = {
                name = set.name,
                gear = gearCopy,
                titleId = set.titleId,
                titleName = set.titleName,
            }
        end
    end
    return copy
end

local function CharacterOwnsLegacySets(legacySets)
    if type(legacySets) ~= "table" or #legacySets == 0 then
        return false
    end
    local firstSet = legacySets[1]
    if type(firstSet) ~= "table" or type(firstSet.gear) ~= "table" or #firstSet.gear == 0 then
        return false
    end
    local requiredMatches = math.min(2, #firstSet.gear)
    local matchCount = 0
    for _, gItem in ipairs(firstSet.gear) do
        if type(gItem) == "table" and type(gItem.name) == "string" then
            local found = false
            if gItem.slot then
                local okEq, eqItem = pcall(function()
                    return api.Equipment:GetEquippedItemTooltipInfo(gItem.slot)
                end)
                if okEq and eqItem and eqItem.name == gItem.name then
                    found = true
                end
            end
            if not found then
                pcall(function()
                    for bagSlot = 1, 150 do
                        local bagItem = api.Bag:GetBagItemInfo(1, bagSlot)
                        if bagItem and bagItem.name == gItem.name then
                            found = true
                            break
                        end
                    end
                end)
            end
            if found then
                matchCount = matchCount + 1
                if matchCount >= requiredMatches then
                    return true
                end
            end
        end
    end
    return false
end

local function SaveQuickEquipSettings()
    if type(EluTrackerSettings.quickEquip) ~= "table" then
        EluTrackerSettings.quickEquip = {}
    end
    local qe = EluTrackerSettings.quickEquip
    if type(qe.characters) ~= "table" then
        qe.characters = {}
    end

    local ck = currentCharKey or GetCurrentCharKey()
    if ck then
        currentCharKey = ck
        qe.characters[ck] = {
            enabled = settings.enabled,
            x = settings.x,
            y = settings.y,
            gear_sets = settings.gear_sets,
        }
    end
    qe.x = settings.x
    qe.y = settings.y
    SaveEluTrackerSettings()
end

local function LoadQuickEquipSettings()
    local data = EluTrackerSettings.quickEquip
    if type(data) ~= "table" then return end
    if type(data.characters) ~= "table" then
        data.characters = {}
    end

    local ck = GetCurrentCharKey()
    if ck then
        currentCharKey = ck
        local charData = data.characters[ck]
        if type(charData) == "table" then
            settings.enabled = (charData.enabled == true)
            settings.x = charData.x or data.x or DEFAULT_X
            settings.y = charData.y or data.y or DEFAULT_Y
            settings.gear_sets = type(charData.gear_sets) == "table" and charData.gear_sets or {}
        else
            local hasUnclaimedLegacy = (not data.legacyClaimed) and type(data.gear_sets) == "table" and #data.gear_sets > 0
            if hasUnclaimedLegacy and CharacterOwnsLegacySets(data.gear_sets) then
                settings.enabled = (data.enabled == true)
                settings.x = data.x or DEFAULT_X
                settings.y = data.y or DEFAULT_Y
                settings.gear_sets = CloneGearSets(data.gear_sets)
                data.legacyClaimed = true
            else
                settings.enabled = false
                settings.x = data.x or DEFAULT_X
                settings.y = data.y or DEFAULT_Y
                settings.gear_sets = {}
            end
            data.characters[ck] = {
                enabled = settings.enabled,
                x = settings.x,
                y = settings.y,
                gear_sets = settings.gear_sets,
            }
            SaveEluTrackerSettings()
        end
    else
        settings.enabled = false
        settings.x = data.x or DEFAULT_X
        settings.y = data.y or DEFAULT_Y
        settings.gear_sets = {}
    end
end

LoadQuickEquipSettings()

local mainCanvas
local promptCanvas
local contextMenu
local gearSetButtons = {}
local buttonRects = {}
local addSetButton
local widgetCounter = 0

local MIN_EQUIP_GAP_MS = 60
local POLL_INTERVAL_MS = 30
local WAIT_TIMEOUT_MS = 1300
local MAX_RETRIES = 1
local gear_to_process = {}
local inFlightEquip = nil

local dragState = nil
local buttonLocalX = {}
local dragIndicator = nil
local BAR_HEIGHT = 40

local renderGearSetUI
local closeContextMenu
local closePrompt

local TOOLTIP_GAP = 6
local hoverTooltipWnd = nil

local function hideHoverTooltip()
    if hoverTooltipWnd then
        hoverTooltipWnd:Show(false)
    end
    pcall(function()
        if mainCanvas then
            api.Interface:SetTooltipOnPos(nil, mainCanvas, 0, 0)
        end
    end)
end

local function showHoverTooltip(targetBtn, lines, isCompact)
    if not targetBtn or type(lines) ~= "table" or #lines == 0 then
        hideHoverTooltip()
        return
    end

    if not hoverTooltipWnd then
        local tip = api.Interface:CreateEmptyWindow("eluQuickEquip_hoverTooltip", "UIParent")
        tip:SetExtent(330, 110)
        tip:Show(false)
        if tip.Clickable then
            pcall(function() tip:Clickable(false) end)
        end

        pcall(function()
            local bg = tip:CreateNinePartDrawable("ui/common_new/default.dds", "background")
            bg:SetTextureInfo("tooltip")
            bg:AddAnchor("TOPLEFT", tip, 0, 0)
            bg:AddAnchor("BOTTOMRIGHT", tip, 0, 0)
            bg:SetColor(1, 1, 1, 0.95)
        end)

        tip.lineLabels = {}
        for idx = 1, 6 do
            local lbl = tip:CreateChildWidget("label", "line_" .. idx, 0, true)
            lbl:SetExtent(306, 20)
            lbl.style:SetAlign(ALIGN.LEFT)
            lbl.style:SetFontSize(idx == 1 and (FONT_SIZE.LARGE or 15) or (FONT_SIZE.MIDDLE or 13))
            if lbl.style.SetShadow then pcall(function() lbl.style:SetShadow(true) end) end
            if lbl.Clickable then pcall(function() lbl:Clickable(false) end) end
            ApplyTextColor(lbl, { 0.92, 0.88, 0.78, 1 })
            lbl:Show(false)
            tip.lineLabels[idx] = lbl
        end

        hoverTooltipWnd = tip
    end

    local boxWidth = isCompact and 220 or 335
    local padX = 12
    local padY = 10
    local lineHeight = 20
    local lineCount = math.min(#lines, #hoverTooltipWnd.lineLabels)

    for idx = 1, #hoverTooltipWnd.lineLabels do
        local lbl = hoverTooltipWnd.lineLabels[idx]
        if idx <= lineCount then
            lbl:SetExtent(boxWidth - padX * 2, lineHeight)
            lbl:SetText(tostring(lines[idx] or ""))
            lbl:RemoveAllAnchors()
            lbl:AddAnchor("TOPLEFT", hoverTooltipWnd, padX, padY + (idx - 1) * lineHeight)
            if idx == 1 then
                ApplyTextColor(lbl, { 1, 0.96, 0.84, 1 })
            else
                ApplyTextColor(lbl, { 0.88, 0.85, 0.78, 1 })
            end
            lbl:Show(true)
        else
            lbl:Show(false)
        end
    end

    local boxHeight = padY * 2 + lineCount * lineHeight
    hoverTooltipWnd:SetExtent(boxWidth, boxHeight)

    local screenH = 1080
    pcall(function()
        screenH = api.Interface:GetScreenHeight() or 1080
    end)

    local btnX, btnY = targetBtn:GetOffset()
    local canvasY = (settings and settings.y) or btnY or DEFAULT_Y
    local refY = math.max(btnY or 0, canvasY or 0)

    hoverTooltipWnd:RemoveAllAnchors()
    if (refY + BAR_HEIGHT + TOOLTIP_GAP + boxHeight + 20) > screenH or refY > (screenH * 0.55) then
        hoverTooltipWnd:AddAnchor("BOTTOMLEFT", targetBtn, "TOPLEFT", 0, -TOOLTIP_GAP)
    else
        hoverTooltipWnd:AddAnchor("TOPLEFT", targetBtn, "BOTTOMLEFT", 0, TOOLTIP_GAP)
    end

    hoverTooltipWnd:Show(true)
    pcall(function() hoverTooltipWnd:Raise() end)
end

local function equipBagItem(slot, equip_alternate_slot)
    api.Bag:EquipBagItem(slot, equip_alternate_slot)
end

local function disableAllGearSetButtons()
    for _, btn in ipairs(gearSetButtons) do
        if btn then btn:Enable(false) end
    end
end

local function enableAllGearSetButtons()
    for _, btn in ipairs(gearSetButtons) do
        if btn then btn:Enable(true) end
    end
end

local function captureCurrentTitle()
    if not api.Player or not api.Player.GetShowingAppellation then
        return nil, nil
    end
    local ok, a1, a2 = pcall(function()
        return api.Player:GetShowingAppellation()
    end)
    if not ok or a1 == nil then
        return nil, nil
    end
    if type(a1) == "table" then
        local id = a1[1] or a1.type or a1.id or a1.appellationType
        local name = a1[2] or a1.name or a1.title
        if type(id) == "number" and id > 0 then
            return id, type(name) == "string" and name or nil
        end
    elseif type(a1) == "number" and a1 > 0 then
        return a1, type(a2) == "string" and a2 or nil
    end
    return nil, nil
end

local function applySavedTitle(loadout)
    if type(loadout) ~= "table" or type(loadout.titleId) ~= "number" or loadout.titleId <= 0 then
        return
    end
    if not api.Player or not api.Player.ChangeAppellation then
        return
    end
    local currentTitleId = captureCurrentTitle()
    if currentTitleId ~= loadout.titleId then
        pcall(function()
            api.Player:ChangeAppellation(loadout.titleId)
        end)
    end
end

local function isItemEquippedInSlot(slotId, itemName, itemGrade)
    if not slotId then
        return false
    end
    local ok, eq = pcall(function()
        return api.Equipment:GetEquippedItemTooltipInfo(slotId)
    end)
    return ok and eq ~= nil and eq.name == itemName and eq.itemGrade == itemGrade
end

local function findItemInBag(itemName, itemGrade)
    for slot_num = 1, 150 do
        local bagItem = api.Bag:GetBagItemInfo(1, slot_num)
        if bagItem ~= nil and bagItem.name == itemName and bagItem.itemGrade == itemGrade then
            return slot_num
        end
    end
    return nil
end

local function startNextEquip()
    inFlightEquip = nil
    while #gear_to_process > 0 do
        local gearItem = table.remove(gear_to_process, 1)
        if gearItem and gearItem.name then
            if not isItemEquippedInSlot(gearItem.slot, gearItem.name, gearItem.grade) then
                local bagSlot = findItemInBag(gearItem.name, gearItem.grade)
                if bagSlot then
                    local isAlt = (gearItem.alternative == true) or (gearItem.slot ~= nil and ALT_SLOTS[gearItem.slot] == true)
                    equipBagItem(bagSlot, isAlt)
                    inFlightEquip = {
                        gear_item = gearItem,
                        bagSlot = bagSlot,
                        elapsedMs = 0,
                        pollAccum = 0,
                        retryCount = 0,
                    }
                    return
                end
            end
        end
    end
    enableAllGearSetButtons()
end

local function enqueueLoadoutEquipment(loadout)
    applySavedTitle(loadout)

    gear_to_process = {}
    inFlightEquip = nil
    local gearList = (type(loadout) == "table" and type(loadout.gear) == "table") and loadout.gear or {}

    for i = 1, #gearList do
        table.insert(gear_to_process, gearList[i])
    end

    if #gear_to_process == 0 then
        enableAllGearSetButtons()
        return
    end

    disableAllGearSetButtons()
    startNextEquip()
end

local function captureCurrentGear()
    local items = {}
    for _, slotId in ipairs(GEAR_PIECES) do
        local item = api.Equipment:GetEquippedItemTooltipInfo(slotId)
        if item ~= nil then
            local newItem = { name = item.name, grade = item.itemGrade, slot = slotId }
            if ALT_SLOTS[slotId] then
                newItem.alternative = true
            end
            table.insert(items, newItem)
        end
    end
    return items
end

function closePrompt()
    if promptCanvas then
        promptCanvas:Show(false)
    end
end

local promptConfirmCallback = nil

local function openNamePrompt(question, defaultText, onConfirm)
    closePrompt()
    promptConfirmCallback = onConfirm

    if not promptCanvas then
        local popup = api.Interface:CreateEmptyWindow("eluQuickEquip_prompt", "UIParent")
        popup:SetExtent(300, 160)
        popup:AddAnchor("CENTER", "UIParent", 0, 0)
        popup:EnableDrag(true)
        pcall(function() popup:SetCloseOnEscape(true) end)
        pcall(function()
            popup:SetHandler("OnCloseByEsc", function() closePrompt() end)
        end)

        local background = popup:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        background:SetTextureInfo("bg_quest")
        background:SetColor(0, 0, 0, 0.85)
        background:AddAnchor("TOPLEFT", popup, 0, 0)
        background:AddAnchor("BOTTOMRIGHT", popup, 0, 0)

        function popup:OnDragStart() self:StartMoving() end
        popup:SetHandler("OnDragStart", popup.OnDragStart)
        function popup:OnDragStop() self:StopMovingOrSizing() end
        popup:SetHandler("OnDragStop", popup.OnDragStop)

        local closeBtn = popup:CreateChildWidget("button", "closeBtn", 0, true)
        closeBtn:SetText("X")
        closeBtn:SetExtent(18, 18)
        closeBtn:AddAnchor("TOPRIGHT", popup, -6, 6)
        closeBtn.style:SetAlign(ALIGN.CENTER)
        ApplyTextColor(closeBtn, FONT_COLOR.RED)
        function closeBtn:OnClick() closePrompt() end
        closeBtn:SetHandler("OnClick", closeBtn.OnClick)

        local label = popup:CreateChildWidget("label", "label", 0, true)
        label.style:SetAlign(ALIGN.CENTER)
        label:SetExtent(260, 25)
        label:AddAnchor("TOP", popup, 0, 25)
        popup.promptLabel = label

        local textEdit = W_CTRL.CreateEdit("eluQuickEquip_promptInput", popup)
        textEdit:SetExtent(240, 30)
        textEdit:AddAnchor("TOP", label, "BOTTOM", 0, 8)
        popup.textEdit = textEdit

        local function doConfirm()
            local text = popup.textEdit and popup.textEdit:GetText() or ""
            local cb = promptConfirmCallback
            closePrompt()
            if cb then cb(text) end
        end

        function textEdit:OnEnterPressed() doConfirm() end
        textEdit:SetHandler("OnEnterPressed", textEdit.OnEnterPressed)

        local confirmButton = popup:CreateChildWidget("button", "confirmButton", 0, true)
        confirmButton:SetText("Confirm")
        confirmButton:SetExtent(100, 30)
        confirmButton:AddAnchor("BOTTOM", popup, 0, -20)
        api.Interface:ApplyButtonSkin(confirmButton, BUTTON_BASIC.DEFAULT)
        function confirmButton:OnClick() doConfirm() end
        confirmButton:SetHandler("OnClick", confirmButton.OnClick)

        promptCanvas = popup
    end

    promptCanvas.promptLabel:SetText(question or "Enter a name:")
    promptCanvas.textEdit:SetText(defaultText or "")
    promptCanvas:Show(true)
    pcall(function() promptCanvas:Raise() end)
    return promptCanvas
end

function closeContextMenu()
    if contextMenu then
        contextMenu:Show(false)
    end
end

local currentCtxIndex = nil

local function openContextMenu(gearSetIndex)
    closeContextMenu()

    local gearSet = settings.gear_sets[gearSetIndex]
    if not gearSet then
        return
    end

    currentCtxIndex = gearSetIndex
    local btnHeight = 28
    local btnGap = 4
    local padX = 8
    local padY = 8
    local menuWidth = 116
    local menuHeight = (padY * 2) + (btnHeight * 3) + (btnGap * 2)

    if not contextMenu then
        local menu = api.Interface:CreateEmptyWindow("eluQuickEquip_ctxMenu", "UIParent")
        menu:SetExtent(menuWidth, menuHeight)
        pcall(function() menu:SetCloseOnEscape(true) end)
        pcall(function()
            menu:SetHandler("OnCloseByEsc", function() closeContextMenu() end)
        end)

        pcall(function()
            menu:RegisterEvent("MOUSE_DOWN")
            menu:SetHandler("OnEvent", function(this, event, widgetId)
                if event == "MOUSE_DOWN" and contextMenu and contextMenu:IsVisible() and not menu:IsDescendantWidget(widgetId) then
                    closeContextMenu()
                end
            end)
        end)

        local background = menu:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        background:SetTextureInfo("bg_quest")
        background:SetColor(0, 0, 0, 0.92)
        background:AddAnchor("TOPLEFT", menu, 0, 0)
        background:AddAnchor("BOTTOMRIGHT", menu, 0, 0)

        menu.options = {}
        local optionDefs = { "Replace", "Rename", "Delete" }
        for i, optName in ipairs(optionDefs) do
            local btn = menu:CreateChildWidget("button", "eluQuickEquip_ctxOpt" .. i, 0, true)
            btn:SetText(optName)
            api.Interface:ApplyButtonSkin(btn, BUTTON_BASIC.DEFAULT)
            btn:SetExtent(menuWidth - (padX * 2), btnHeight)
            btn:RemoveAllAnchors()
            btn:AddAnchor("TOP", menu, 0, padY + (i - 1) * (btnHeight + btnGap))
            if optName == "Delete" then
                ApplyTextColor(btn, FONT_COLOR.RED)
            end
            menu.options[i] = btn
        end

        menu.options[1].OnClick = function()
            local idx = currentCtxIndex
            closeContextMenu()
            if not idx or not settings.gear_sets then return end
            local target = settings.gear_sets[idx]
            if target then
                target.gear = captureCurrentGear()
                local tId, tName = captureCurrentTitle()
                target.titleId = tId
                target.titleName = tName
                SaveQuickEquipSettings()
                renderGearSetUI()
            end
        end
        menu.options[1]:SetHandler("OnClick", menu.options[1].OnClick)

        menu.options[2].OnClick = function()
            local idx = currentCtxIndex
            closeContextMenu()
            if not idx or not settings.gear_sets then return end
            local target = settings.gear_sets[idx]
            if not target then return end
            openNamePrompt("Rename gear set", target.name, function(newName)
                newName = (newName or ""):match("^%s*(.-)%s*$")
                if newName == "" then return end
                if settings.gear_sets[idx] then
                    settings.gear_sets[idx].name = newName
                    SaveQuickEquipSettings()
                    renderGearSetUI()
                end
            end)
        end
        menu.options[2]:SetHandler("OnClick", menu.options[2].OnClick)

        menu.options[3].OnClick = function()
            local idx = currentCtxIndex
            closeContextMenu()
            if not idx or not settings.gear_sets then return end
            if settings.gear_sets[idx] then
                table.remove(settings.gear_sets, idx)
                SaveQuickEquipSettings()
                renderGearSetUI()
            end
        end
        menu.options[3]:SetHandler("OnClick", menu.options[3].OnClick)

        contextMenu = menu
    end

    local okSize, screenW, screenH = pcall(function()
        return api.Interface:GetScreenWidth(), api.Interface:GetScreenHeight()
    end)
    if not okSize or not screenW or not screenH then
        screenW, screenH = 2560, 1080
    end

    local canvasY = settings.y or DEFAULT_Y
    local rect = buttonRects[gearSetIndex]
    local anchorX
    local anchorY

    if rect then
        anchorX = math.floor(((rect.x1 + rect.x2) - menuWidth) / 2)
    else
        local mx = api.Input:GetMousePos()
        anchorX = mx or (settings.x or DEFAULT_X)
    end

    if (canvasY + BAR_HEIGHT + menuHeight + 6) > screenH or canvasY > (screenH * 0.55) then
        anchorY = canvasY - menuHeight - 4
    else
        anchorY = canvasY + BAR_HEIGHT + 4
    end

    if anchorX < 4 then anchorX = 4 end
    if (anchorX + menuWidth) > screenW - 4 then
        anchorX = screenW - menuWidth - 4
    end
    if anchorY < 4 then anchorY = 4 end

    contextMenu:SetExtent(menuWidth, menuHeight)
    contextMenu:RemoveAllAnchors()
    contextMenu:AddAnchor("TOPLEFT", "UIParent", anchorX, anchorY)
    contextMenu:Show(true)
    pcall(function() contextMenu:Raise() end)
end

local function findClosestButtonIndex(mx)
    local closestIndex = nil
    local closestDist = nil
    for i, rect in ipairs(buttonRects) do
        local center = (rect.x1 + rect.x2) / 2
        local dist = math.abs(mx - center)
        if not closestDist or dist < closestDist then
            closestDist = dist
            closestIndex = i
        end
    end
    return closestIndex
end

local function updateDragIndicator()
    if not dragState or not mainCanvas or not dragIndicator then
        if dragIndicator then dragIndicator:Show(false) end
        return
    end
    local mx = api.Input:GetMousePos()
    local targetIndex = mx and findClosestButtonIndex(mx)
    local rect = targetIndex and buttonLocalX[targetIndex]
    if not rect then
        dragIndicator:Show(false)
        return
    end
    dragIndicator:RemoveAllAnchors()
    dragIndicator:AddAnchor("TOPLEFT", mainCanvas, rect.x1 - 2, 2)
    dragIndicator:SetExtent((rect.x2 - rect.x1) + 4, BAR_HEIGHT - 4)
    dragIndicator:Show(true)
end

local function moveGearSet(fromIndex, targetIndex)
    if not settings.gear_sets[fromIndex] or fromIndex == targetIndex then
        return
    end
    local moved = table.remove(settings.gear_sets, fromIndex)
    local insertAt = targetIndex
    if insertAt < 1 then insertAt = 1 end
    if insertAt > #settings.gear_sets + 1 then insertAt = #settings.gear_sets + 1 end
    table.insert(settings.gear_sets, insertAt, moved)
    SaveQuickEquipSettings()
    renderGearSetUI()
end

function renderGearSetUI()
    closeContextMenu()
    hideHoverTooltip()

    gearSetButtons = gearSetButtons or {}
    buttonRects = {}
    buttonLocalX = {}

    local canvas_x = settings.x or DEFAULT_X
    local canvas_y = settings.y or DEFAULT_Y

    if not mainCanvas then
        mainCanvas = api.Interface:CreateEmptyWindow("eluQuickEquip_bar", "UIParent")
        mainCanvas.background = mainCanvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        mainCanvas.background:SetTextureInfo("bg_quest")
        mainCanvas.background:SetColor(0, 0, 0, 0.6)
        mainCanvas.background:AddAnchor("TOPLEFT", mainCanvas, 0, 0)
        mainCanvas.background:AddAnchor("BOTTOMRIGHT", mainCanvas, 0, 0)

        function mainCanvas:OnDragStart()
            if api.Input:IsShiftKeyDown() then
                mainCanvas:StartMoving()
                api.Cursor:ClearCursor()
                api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
            end
        end
        mainCanvas:SetHandler("OnDragStart", mainCanvas.OnDragStart)

        function mainCanvas:OnDragStop()
            local current_x, current_y = self:GetOffset()
            settings.x = current_x
            settings.y = current_y
            SaveQuickEquipSettings()
            self:StopMovingOrSizing()
            api.Cursor:ClearCursor()
            renderGearSetUI()
        end
        mainCanvas:SetHandler("OnDragStop", mainCanvas.OnDragStop)
    end

    mainCanvas:RemoveAllAnchors()
    mainCanvas:AddAnchor("TOPLEFT", "UIParent", canvas_x, canvas_y)

    local baseCanvasHeight = BAR_HEIGHT
    local buttonBaseWidth = 68
    local buttonHeight = 30
    local buttonY = math.floor((baseCanvasHeight - buttonHeight) / 2)
    local buttonGap = 5
    local leftPadding = 8
    local rightPadding = 8
    local addButtonExtraGap = 2

    local numGearSets = settings.gear_sets and #settings.gear_sets or 0
    mainCanvas:SetExtent(90, baseCanvasHeight)

    local dynamicButtonsWidth = 0

    for i, gear_set in ipairs(settings.gear_sets or {}) do
        local buttonX = leftPadding + dynamicButtonsWidth
        local setBtn = gearSetButtons[i]
        if not setBtn then
            setBtn = api.Interface:CreateWidget('button', "eluQuickEquip_btn_" .. i, mainCanvas)
            if setBtn.RegisterForClicks then
                pcall(function() setBtn:RegisterForClicks("LeftButton") end)
                pcall(function() setBtn:RegisterForClicks("RightButton") end)
            end
            if setBtn.RegisterForDrag then pcall(function() setBtn:RegisterForDrag("LeftButton") end) end
            if setBtn.EnableDrag then pcall(function() setBtn:EnableDrag(true) end) end
            gearSetButtons[i] = setBtn
        end

        local setLabel = tostring(gear_set.name or ("Set " .. i))
        setBtn:SetText(setLabel)
        api.Interface:ApplyButtonSkin(setBtn, BUTTON_BASIC.DEFAULT)
        if setBtn.RegisterForClicks then
            pcall(function() setBtn:RegisterForClicks("LeftButton") end)
            pcall(function() setBtn:RegisterForClicks("RightButton") end)
        end

        local textW = 0
        pcall(function()
            if setBtn.style and setBtn.style.GetTextWidth then
                textW = setBtn.style:GetTextWidth(setLabel) or 0
            end
        end)
        if textW <= 0 then
            textW = #setLabel * 8
        end
        local calcWidth = math.max(buttonBaseWidth, math.floor(textW + 24))
        setBtn:SetExtent(calcWidth, buttonHeight)

        setBtn:RemoveAllAnchors()
        setBtn:AddAnchor("TOPLEFT", mainCanvas, buttonX, buttonY)
        setBtn:Show(true)

        local actualButtonWidth = calcWidth
        buttonRects[i] = { x1 = canvas_x + buttonX, x2 = canvas_x + buttonX + actualButtonWidth }
        buttonLocalX[i] = { x1 = buttonX, x2 = buttonX + actualButtonWidth }
        dynamicButtonsWidth = dynamicButtonsWidth + actualButtonWidth + buttonGap

        local currentIdx = i
        local currentSet = gear_set
        function setBtn:OnClick(mb)
            local clickType = (type(self) == "string" and self) or mb
            local ctrlDown = api.Input:IsControlKeyDown()
            if clickType == "RightButton" or ctrlDown then
                closeContextMenu()
                openContextMenu(currentIdx)
                return
            end
            closeContextMenu()
            disableAllGearSetButtons()
            enqueueLoadoutEquipment(currentSet)
        end
        setBtn:SetHandler("OnClick", setBtn.OnClick)

        function setBtn:OnDragStart()
            if not api.Input:IsShiftKeyDown() then
                return
            end
            closeContextMenu()
            dragState = { index = currentIdx }
            self:StartMoving()
            api.Cursor:ClearCursor()
            api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
        end
        setBtn:SetHandler("OnDragStart", setBtn.OnDragStart)

        function setBtn:OnDragStop()
            self:StopMovingOrSizing()
            api.Cursor:ClearCursor()
            local dragging = dragState
            dragState = nil
            if not dragging or dragging.index ~= currentIdx then
                return
            end
            local mx = api.Input:GetMousePos()
            local targetIndex = findClosestButtonIndex(mx)
            if targetIndex and targetIndex ~= currentIdx then
                moveGearSet(currentIdx, targetIndex)
            else
                renderGearSetUI()
            end
        end
        setBtn:SetHandler("OnDragStop", setBtn.OnDragStop)

        local name = gear_set.name or "Unnamed Set"
        local tipLines = { name }
        if type(gear_set.titleName) == "string" and gear_set.titleName ~= "" then
            table.insert(tipLines, "Title: " .. gear_set.titleName)
        elseif type(gear_set.titleId) == "number" and gear_set.titleId > 0 then
            table.insert(tipLines, "Title ID: " .. tostring(gear_set.titleId))
        end
        table.insert(tipLines, "Left-click: equip this gear set.")
        table.insert(tipLines, "Right-click (or Ctrl + click): replace / rename / delete.")
        table.insert(tipLines, "Shift + drag: reorder.")
        function setBtn:OnEnter()
            showHoverTooltip(self, tipLines, false)
        end
        function setBtn:OnLeave()
            hideHoverTooltip()
        end
        setBtn:SetHandler("OnEnter", setBtn.OnEnter)
        setBtn:SetHandler("OnLeave", setBtn.OnLeave)
    end

    for j = numGearSets + 1, #gearSetButtons do
        if gearSetButtons[j] then
            gearSetButtons[j]:Show(false)
        end
    end

    local useExtraGap = numGearSets > 0 and addButtonExtraGap or 0
    local addButtonX = leftPadding + dynamicButtonsWidth + useExtraGap
    local addBtnWidth = 36

    if not addSetButton then
        addSetButton = api.Interface:CreateWidget('button', "eluQuickEquip_addBtn", mainCanvas)
        api.Interface:ApplyButtonSkin(addSetButton, BUTTON_BASIC.DEFAULT)
        addSetButton:SetText("+")
        addSetButton:SetExtent(addBtnWidth, buttonHeight)

        function addSetButton:OnEnter()
            showHoverTooltip(self, { "Quick Equip", "Add Preset (Gear + Title)" }, true)
        end
        function addSetButton:OnLeave()
            hideHoverTooltip()
        end
        addSetButton:SetHandler("OnEnter", addSetButton.OnEnter)
        addSetButton:SetHandler("OnLeave", addSetButton.OnLeave)

        local function saveNewSet(setNameInput)
            local setName = ""
            if setNameInput and setNameInput ~= "" then
                setName = setNameInput
            else
                setName = "New Gear Set (" .. (#settings.gear_sets + 1) .. ")"
            end

            local tId, tName = captureCurrentTitle()
            local loadout = {
                name = setName,
                gear = captureCurrentGear(),
                titleId = tId,
                titleName = tName,
            }

            local loadout_exists = false
            if settings.gear_sets then
                for i, v in ipairs(settings.gear_sets) do
                    if v.name == setName then
                        settings.gear_sets[i] = loadout
                        loadout_exists = true
                        break
                    end
                end
            end

            if not loadout_exists then
                settings.gear_sets = settings.gear_sets or {}
                table.insert(settings.gear_sets, loadout)
            end

            SaveQuickEquipSettings()
            renderGearSetUI()
        end

        addSetButton.OnClick = function()
            closeContextMenu()
            openNamePrompt("Enter Gear Set Name", "", saveNewSet)
        end
        addSetButton:SetHandler("OnClick", addSetButton.OnClick)
    end

    addSetButton:SetExtent(addBtnWidth, buttonHeight)
    addSetButton:RemoveAllAnchors()
    addSetButton:AddAnchor("TOPLEFT", mainCanvas, addButtonX, buttonY)
    addSetButton:Show(true)

    local addButtonWidth = addBtnWidth
    local totalRequiredWidth = leftPadding + dynamicButtonsWidth + addButtonWidth + rightPadding + useExtraGap
    mainCanvas:SetExtent(totalRequiredWidth, baseCanvasHeight)

    if not dragIndicator then
        dragIndicator = mainCanvas:CreateChildWidget("emptywidget", "eluQuickEquip_dragIndicator", 0, true)
        dragIndicator.bg = dragIndicator:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        dragIndicator.bg:SetTextureInfo("bg_quest")
        dragIndicator.bg:SetColor(1, 0.82, 0.15, 0.55)
        dragIndicator.bg:AddAnchor("TOPLEFT", dragIndicator, 0, 0)
        dragIndicator.bg:AddAnchor("BOTTOMRIGHT", dragIndicator, 0, 0)
    end
    dragIndicator:SetExtent(buttonBaseWidth, baseCanvasHeight - 4)
    dragIndicator:Show(false)

    if not inFlightEquip and #gear_to_process == 0 then
        enableAllGearSetButtons()
    end

    mainCanvas:Show(true)
    mainCanvas:EnableDrag(true)
end

local function destroyBarUI()
    closeContextMenu()
    closePrompt()
    hideHoverTooltip()

    if mainCanvas then
        mainCanvas:Show(false)
    end
    dragState = nil
end

local function setEnabled(enabled)
    settings.enabled = enabled and true or false
    SaveQuickEquipSettings()
    if settings.enabled then
        renderGearSetUI()
    else
        destroyBarUI()
    end
end

function quick_equip_addon.CreateUI(wndParent)
    LoadQuickEquipSettings()

    local container = wndParent:CreateChildWidget("emptywidget", "quickEquipMiscSection", 0, true)
    container:SetExtent(500, 30)

    local enableCheck = container:CreateChildWidget("checkbutton", "quickEquipEnableCheck", 0, true)
    enableCheck:SetExtent(18, 17)
    enableCheck:AddAnchor("TOPLEFT", container, 0, 5)
    enableCheckWidget = enableCheck

    local bg1 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg1:SetExtent(18, 17)
    bg1:AddAnchor("CENTER", enableCheck, 0, 0)
    bg1:SetCoords(0, 0, 18, 17)
    enableCheck:SetNormalBackground(bg1)

    local bg2 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg2:SetExtent(18, 17)
    bg2:AddAnchor("CENTER", enableCheck, 0, 0)
    bg2:SetCoords(18, 0, 18, 17)
    enableCheck:SetCheckedBackground(bg2)

    local bg3 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg3:SetExtent(18, 17)
    bg3:AddAnchor("CENTER", enableCheck, 0, 0)
    bg3:SetCoords(0, 0, 18, 17)
    enableCheck:SetPushedBackground(bg3)

    local bg4 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg4:SetExtent(18, 17)
    bg4:AddAnchor("CENTER", enableCheck, 0, 0)
    bg4:SetCoords(18, 0, 18, 17)
    enableCheck:SetHighlightBackground(bg4)

    local enableLbl = container:CreateChildWidget("label", "quickEquipEnableLbl", 0, true)
    enableLbl:SetAutoResize(true)
    enableLbl:SetText("Quick Equip: Enable gear-swap bar")
    enableLbl:AddAnchor("LEFT", enableCheck, "RIGHT", 6, 0)
    ApplyTextColor(enableLbl, FONT_COLOR.DEFAULT)

    local checkboxGap = 6
    local labelWidth = enableLbl:GetWidth() or 220
    local resetBtnSpace = 12 + 24
    local totalWidth = 18 + checkboxGap + labelWidth + resetBtnSpace
    local containerWidth = container:GetWidth() or 500
    local startX = math.floor((containerWidth - totalWidth) / 2)
    enableCheck:RemoveAllAnchors()
    enableCheck:AddAnchor("TOPLEFT", container, startX, 5)

    enableCheck:SetChecked(settings.enabled, false)

    function enableCheck:OnCheckChanged()
        setEnabled(self:GetChecked())
    end
    enableCheck:SetHandler("OnCheckChanged", enableCheck.OnCheckChanged)

    local resetPosBtn = container:CreateChildWidget("button", "quickEquipResetPosBtn", 0, true)
    resetPosBtn:AddAnchor("LEFT", enableLbl, "RIGHT", 12, 0)
    api.Interface:ApplyButtonSkin(resetPosBtn, BUTTON_BASIC.RESET)

    function resetPosBtn:OnEnter()
        local x, y = self:GetOffset()
        api.Interface:SetTooltipOnPos("Resets the Quick Equip bar to its default position\nif it gets lost off-screen.", container, x, y + 25)
    end
    function resetPosBtn:OnLeave()
        local x, y = self:GetOffset()
        api.Interface:SetTooltipOnPos(nil, container, x, y + 25)
    end
    resetPosBtn:SetHandler("OnEnter", resetPosBtn.OnEnter)
    resetPosBtn:SetHandler("OnLeave", resetPosBtn.OnLeave)

    function resetPosBtn:OnClick()
        settings.x = DEFAULT_X
        settings.y = DEFAULT_Y
        SaveQuickEquipSettings()
        if settings.enabled and mainCanvas then
            mainCanvas:RemoveAllAnchors()
            mainCanvas:AddAnchor("TOPLEFT", "UIParent", DEFAULT_X, DEFAULT_Y)
        elseif settings.enabled then
            renderGearSetUI()
        end
    end
    resetPosBtn:SetHandler("OnClick", resetPosBtn.OnClick)

    return container
end

local function SyncCharacterStateIfNeeded()
    local ck = GetCurrentCharKey()
    if ck and ck ~= currentCharKey then
        LoadQuickEquipSettings()
        if enableCheckWidget then
            pcall(function() enableCheckWidget:SetChecked(settings.enabled, false) end)
        end
        if settings.enabled then
            renderGearSetUI()
        else
            destroyBarUI()
        end
    end
end

function quick_equip_addon:OnLoad()
    LoadQuickEquipSettings()
    if enableCheckWidget then
        pcall(function() enableCheckWidget:SetChecked(settings.enabled, false) end)
    end
    if settings.enabled then
        renderGearSetUI()
    else
        destroyBarUI()
    end
end

function quick_equip_addon:OnUnload()
    enableCheckWidget = nil
    currentCharKey = nil
    gear_to_process = {}
    inFlightEquip = nil
    destroyBarUI()
end

function quick_equip_addon:OnUpdate(dt)
    local stepMs = (type(dt) == "number" and dt > 0) and dt or 16
    if inFlightEquip then
        inFlightEquip.elapsedMs = inFlightEquip.elapsedMs + stepMs
        inFlightEquip.pollAccum = inFlightEquip.pollAccum + stepMs
        if inFlightEquip.elapsedMs >= MIN_EQUIP_GAP_MS and inFlightEquip.pollAccum >= POLL_INTERVAL_MS then
            inFlightEquip.pollAccum = 0
            local gItem = inFlightEquip.gear_item
            local landed = false
            if gItem.slot then
                landed = isItemEquippedInSlot(gItem.slot, gItem.name, gItem.grade)
            else
                local cur = api.Bag:GetBagItemInfo(1, inFlightEquip.bagSlot)
                landed = not (cur and cur.name == gItem.name and cur.itemGrade == gItem.grade)
            end

            if landed then
                startNextEquip()
            elseif inFlightEquip.elapsedMs >= WAIT_TIMEOUT_MS then
                if inFlightEquip.retryCount < MAX_RETRIES then
                    local retrySlot = findItemInBag(gItem.name, gItem.grade)
                    if retrySlot then
                        inFlightEquip.retryCount = inFlightEquip.retryCount + 1
                        inFlightEquip.bagSlot = retrySlot
                        inFlightEquip.elapsedMs = 0
                        inFlightEquip.pollAccum = 0
                        local isAlt = (gItem.alternative == true) or (gItem.slot ~= nil and ALT_SLOTS[gItem.slot] == true)
                        equipBagItem(retrySlot, isAlt)
                    else
                        startNextEquip()
                    end
                else
                    startNextEquip()
                end
            end
        end
    end

    charCheckTimer = charCheckTimer + (type(dt) == "number" and dt or 0)
    if charCheckTimer >= 500 then
        charCheckTimer = 0
        SyncCharacterStateIfNeeded()
    end
    if dragState then updateDragIndicator() end
end

return quick_equip_addon
