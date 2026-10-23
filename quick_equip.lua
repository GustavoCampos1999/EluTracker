-- quick_equip.lua
-- Gear set swapper, integrated into Elu Tracker (formerly the standalone
-- "set_swap" addon by Winterflame). Save your currently equipped gear as a
-- named preset and re-equip the whole set with one click.
--
-- Controls:
--   Left-click a preset      -> equip that gear set
--   Ctrl + click a preset    -> context menu: Replace / Rename / Delete
--                                (the addon API has no working right-click
--                                 event for this widget, confirmed by live
--                                 testing, so Ctrl+Click is used instead)
--   Shift + drag a preset    -> reorder it among the other presets
--   Shift + drag empty bar   -> move the whole Quick Equip bar
--   "+" button               -> save currently equipped gear as a new preset
--                                (Esc or the X closes the popup without saving)

local api = require('api')
local settingsManager = require('Elu_Tracker/settings_manager')
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local quick_equip_addon = {}

-- Equip-slot ids to snapshot/equip, in the same order as the original addon.
local GEAR_PIECES = { 1, 3, 4, 8, 6, 9, 5, 7, 15, 2, 10, 11, 12, 13, 16, 17, 18, 19, 28 }
local ALT_SLOTS = { [11] = true, [13] = true, [17] = true }

-- Starts disabled on a fresh install; the saved value (once the user turns
-- it on from the Misc tab) persists across reload/relog like every other
-- Elu Tracker setting.
local settings = {
    enabled = false,
    x = 200,
    y = 40,
    gear_sets = {}
}

-- Default on-screen position used by the reset button in the Misc tab.
-- Defined as constants so CreateUI and renderGearSetUI always agree on
-- what "default" means without duplicating the numbers.
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
            }
        end
    end
    return copy
end

-- Checks whether the currently logged-in character owns the legacy gear sets
-- (by matching equipped or bag items), so migrating pre-existing global sets
-- gives them to the character that actually owns that gear instead of an alt.
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
            -- First time this character is seen under per-character storage:
            -- only migrate legacy top-level gear_sets if this character actually owns those items.
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
        -- Player unit not ready yet at require-time: load safe defaults until OnLoad/OnUpdate detects character
        settings.enabled = false
        settings.x = data.x or DEFAULT_X
        settings.y = data.y or DEFAULT_Y
        settings.gear_sets = {}
    end
end

-- Load immediately at require-time (not only inside :OnLoad()). CreateUI()
-- for the Misc tab is invoked by CreateWindow's subWindowConstructor, which
-- runs BEFORE :OnLoad() later in main.lua's load sequence -- if we only
-- loaded from :OnLoad(), the checkbox would render the stale module-level
-- default (enabled=false) even when the saved value on disk was true,
-- desyncing the checkbox from the addon's real state after every reload.
LoadQuickEquipSettings()

local mainCanvas
local promptCanvas
local contextMenu
local gearSetButtons = {}
local buttonRects = {} -- absolute on-screen x1/x2 per button, rebuilt on every render
local addSetButton
local widgetCounter = 0

local enqueuedItems = {}
local isProcessingEquip = false
local retryDelay = 50        -- Delay before checking whether an equip attempt landed, and before retrying if not
local maxRetries = 1         -- Maximum number of retries for an item

local dragState = nil -- { index = n } while a shift-drag reorder is in progress
local buttonLocalX = {} -- canvas-relative x1/x2 per button, parallel to buttonRects; used to
                         -- position the live drop-target highlight without depending on the
                         -- bar's absolute screen position
local dragIndicator = nil -- highlight widget shown over the slot a dragged preset would land in
local BAR_HEIGHT = 40 -- shared with renderGearSetUI's mainCanvas height, so the highlight always matches the bar

local processNextEquip     -- forward declaration
local renderGearSetUI      -- forward declaration
local closeContextMenu     -- forward declaration
local closePrompt          -- forward declaration

-- Singleton architecture: Widgets are created once and reused forever with fixed IDs.
-- In ArcheAge Classic (CryEngine 32-bit), api.Interface:Free() does not exist in the C++ engine.
-- Destroying and recreating widgets creates memory leaks and duplicates in the C++ UI tree.
-- By reusing the existing widgets, zero new memory or windows are allocated on reloads or preset changes.

-- Hover tooltips: flip near a screen edge, same idea as the ctrl+click
-- context menu (openContextMenu) -- try to show the tooltip below the
-- button, and flip it above when there isn't room below.
--
-- Quirks of api.Interface:SetTooltipOnPos with this widget/anchor combo
-- (mainCanvas as target, self:GetOffset() as the base position), found by
-- live debug logging:
--   * self:GetOffset() on these buttons returns the button's ABSOLUTE
--     screen Y, not a parent-relative offset.
--   * the tooltip box anchors from its own BOTTOM edge and grows upward
--     from the Y coordinate given -- it is not a normal top-left anchor.
-- So "show below the button" means anchoring the Y coordinate *further
-- down* than the button (bottom edge + gap + box height), and "show
-- above" means anchoring it *just above* the button (top edge - gap);
-- the box then grows upward from that point in both cases.
local TOOLTIP_GAP = 15
-- Extra safety margin used only for the flip DECISION (not for the actual
-- anchor offset). The real rendered tooltip box is a bit taller than our
-- estHeight guess, so without this the below-branch was still getting
-- picked (and clipped) when the button was close to, but not exactly at,
-- the bottom edge. Padding the decision makes it flip a little earlier,
-- before the real box has a chance to run off the bottom of the screen.
local TOOLTIP_SAFETY = 40

local function getTooltipOffsetY(PosY, estHeight)
    local screenH = api.Interface:GetScreenHeight()
    if PosY + TOOLTIP_GAP + estHeight + TOOLTIP_SAFETY > screenH then
        -- not enough room below: flip above the button
        return -TOOLTIP_GAP
    end
    return TOOLTIP_GAP + estHeight
end

-- ===== Equip queue (unchanged logic from the original addon) =====

local function equipBagItem(slot, equipmentSlot)
    api.Bag:EquipBagItem(slot, ALT_SLOTS[equipmentSlot] == true)
end

local function enqueueItemEquip(item, bagSlot, equipmentSlot, retryCount)
    if not item or not bagSlot then
        return
    end
    table.insert(enqueuedItems, {
        bagSlot = bagSlot,
        item = item,
        equipmentSlot = equipmentSlot,
        retryCount = retryCount or 0
    })
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

local function enqueueLoadoutEquipment(loadout)
    local maxBagSlots = 150
    for loadoutItemIndex = 1, #loadout.gear do
        local loadoutItem = loadout.gear[loadoutItemIndex]
        for bagSlot = 1, maxBagSlots do
            local bagItem = api.Bag:GetBagItemInfo(1, bagSlot)
            if bagItem and bagItem.name == loadoutItem.name and bagItem.itemGrade == loadoutItem.grade then
                enqueueItemEquip(bagItem, bagSlot, loadoutItem.slot, 0)
                break
            end
        end
    end

    if not isProcessingEquip then
        processNextEquip()
    end
end

function processNextEquip()
    if #enqueuedItems == 0 then
        isProcessingEquip = false
        enableAllGearSetButtons()
        return
    end

    isProcessingEquip = true
    local equipableItem = table.remove(enqueuedItems, 1)

    equipBagItem(equipableItem.bagSlot, equipableItem.equipmentSlot)

    api:DoIn(retryDelay, function()
        local equippedItem = api.Equipment:GetEquippedItemTooltipInfo(equipableItem.equipmentSlot)
        local wasEquipped = equippedItem
            and equippedItem.name == equipableItem.item.name
            and equippedItem.itemGrade == equipableItem.item.itemGrade

        if not wasEquipped and equipableItem.retryCount < maxRetries then
            equipableItem.retryCount = equipableItem.retryCount + 1
            table.insert(enqueuedItems, 1, equipableItem)
            api:DoIn(retryDelay, processNextEquip)
        else
            -- Move on immediately once the item is confirmed equipped (or
            -- retries are exhausted) -- no need for a second delay stacked
            -- on top of the retryDelay wait we already just did. The
            -- original Set Swap addon had a bug here (it called
            -- processNextEquip() immediately and passed its return value
            -- to api:DoIn(), rather than passing the function itself),
            -- which made every item equip roughly retryDelay (~50ms) apart
            -- in practice, not retryDelay+betweenItemDelay (~150ms). That
            -- accidental fast cadence is what people are used to from it;
            -- doing it correctly-but-slower here just made this feel
            -- sluggish by comparison. Replicate the fast, intended
            -- behavior on purpose instead of by accident.
            processNextEquip()
        end
    end)
end

-- Snapshot of the currently equipped gear, in the shape a preset expects.
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

-- ===== Small reusable "name" prompt popup (Save / Rename) =====
-- Built once with static IDs and reused forever; zero new windows allocated.

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

        -- X button: cancel without saving
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

-- ===== Ctrl+Click context menu (Replace / Rename / Delete) =====
-- Built once with static ID "eluQuickEquip_ctxMenu" and reused.

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
    local optionHeight = 24
    local menuWidth = 120
    local menuHeight = optionHeight * 3 + 8

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
            btn:SetExtent(menuWidth - 8, optionHeight - 2)
            btn:RemoveAllAnchors()
            btn:AddAnchor("TOP", menu, 0, 4 + (i - 1) * optionHeight)
            api.Interface:ApplyButtonSkin(btn, BUTTON_BASIC.DEFAULT)
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

    local mx, my = api.Input:GetMousePos()
    local okSize, screenW, screenH = pcall(function()
        return api.Interface:GetScreenWidth(), api.Interface:GetScreenHeight()
    end)
    if not okSize or not screenW or not screenH then
        screenW, screenH = 2560, 1080
    end

    local anchorX = mx or 0
    local anchorY = my or 0
    if my and (my + menuHeight) > screenH then
        anchorY = my - menuHeight
    end
    if mx and (mx + menuWidth) > screenW then
        anchorX = mx - menuWidth
    end

    contextMenu:RemoveAllAnchors()
    contextMenu:AddAnchor("TOPLEFT", "UIParent", anchorX, anchorY)
    contextMenu:Show(true)
    pcall(function() contextMenu:Raise() end)
end

-- ===== Shift + drag reorder helper =====

-- Returns the index of the preset whose button center is closest to mx.
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

-- Live "drop here" highlight shown while a shift+drag reorder is in
-- progress (driven by quick_equip_addon:OnUpdate, wired into main.lua's
-- central UPDATE dispatcher). It always uses the same findClosestButtonIndex
-- the actual drop (setBtn:OnDragStop) uses, so the highlighted slot always
-- matches where the preset will really land -- this is purely visual
-- feedback, it does not change the reorder logic itself.
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
    -- The dragged preset should land exactly on the slot it was dropped on
    -- (targetIndex, in the ORIGINAL numbering), with whatever was between
    -- fromIndex and targetIndex sliding over by one to make room. Because
    -- targetIndex is expressed in the original numbering and we already
    -- removed fromIndex above, no extra "-1" adjustment is needed here for
    -- forward moves (targetIndex > fromIndex): the list is one shorter now,
    -- so inserting at targetIndex already lands the moved item on the slot
    -- that used to be targetIndex.
    -- (A previous version subtracted 1 for forward moves, which meant
    -- "insert before the target" instead of "take the target's slot" -- for
    -- a 2-item list that made dragging item 1 onto item 2 a visible no-op,
    -- since "before the only remaining item" is that item's own position.)
    local insertAt = targetIndex
    if insertAt < 1 then insertAt = 1 end
    if insertAt > #settings.gear_sets + 1 then insertAt = #settings.gear_sets + 1 end
    table.insert(settings.gear_sets, insertAt, moved)
    SaveQuickEquipSettings()
    renderGearSetUI()
end

-- ===== Main bar UI =====

function renderGearSetUI()
    closeContextMenu()

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
    local buttonBaseWidth = 70
    local buttonGap = 5
    local leftPadding = 9
    local rightPadding = 9
    local addButtonExtraGap = 10

    local numGearSets = settings.gear_sets and #settings.gear_sets or 0
    mainCanvas:SetExtent(90, baseCanvasHeight)

    local dynamicButtonsWidth = 0

    for i, gear_set in ipairs(settings.gear_sets or {}) do
        local buttonX = leftPadding + dynamicButtonsWidth
        local setBtn = gearSetButtons[i]
        if not setBtn then
            setBtn = api.Interface:CreateWidget('button', "eluQuickEquip_btn_" .. i, mainCanvas)
            if setBtn.RegisterForDrag then pcall(function() setBtn:RegisterForDrag("LeftButton") end) end
            if setBtn.EnableDrag then pcall(function() setBtn:EnableDrag(true) end) end
            gearSetButtons[i] = setBtn
        end

        setBtn:RemoveAllAnchors()
        setBtn:AddAnchor("TOPLEFT", buttonX, 3)
        setBtn:SetText(gear_set.name)

        local skin = {}
        for k, v in pairs(BUTTON_BASIC.DEFAULT) do skin[k] = v end
        skin.width = buttonBaseWidth
        skin.height = 30
        api.Interface:ApplyButtonSkin(setBtn, skin)
        setBtn:Show(true)

        local actualButtonWidth = setBtn:GetWidth()
        buttonRects[i] = { x1 = canvas_x + buttonX, x2 = canvas_x + buttonX + actualButtonWidth }
        buttonLocalX[i] = { x1 = buttonX, x2 = buttonX + actualButtonWidth }
        dynamicButtonsWidth = dynamicButtonsWidth + actualButtonWidth + buttonGap

        local currentIdx = i
        local currentSet = gear_set
        setBtn.OnClick = function()
            local ctrlDown = api.Input:IsControlKeyDown()
            if ctrlDown then
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
        function setBtn:OnEnter()
            local PosX, PosY = self:GetOffset()
            local description = name
                .. "\nLeft-click: equip this gear set."
                .. "\nCtrl + click: replace / rename / delete."
                .. "\nShift + drag: reorder."
            api.Interface:SetTooltipOnPos(description, mainCanvas, PosX + 50, PosY + getTooltipOffsetY(PosY, 110))
        end
        function setBtn:OnLeave()
            local PosX, PosY = self:GetOffset()
            api.Interface:SetTooltipOnPos(nil, mainCanvas, PosX + 50, PosY + getTooltipOffsetY(PosY, 110))
        end
        setBtn:SetHandler("OnEnter", setBtn.OnEnter)
        setBtn:SetHandler("OnLeave", setBtn.OnLeave)
    end

    -- Hide any extra buttons that were previously created
    for j = numGearSets + 1, #gearSetButtons do
        if gearSetButtons[j] then
            gearSetButtons[j]:Show(false)
        end
    end

    local useExtraGap = numGearSets > 0 and addButtonExtraGap or 0
    local addButtonX = leftPadding + dynamicButtonsWidth + useExtraGap

    if not addSetButton then
        addSetButton = api.Interface:CreateWidget('button', "eluQuickEquip_addBtn", mainCanvas)
        local addSkin = {}
        for k, v in pairs(BUTTON_BASIC.DEFAULT) do addSkin[k] = v end
        addSkin.width = 60
        addSkin.height = 30
        api.Interface:ApplyButtonSkin(addSetButton, addSkin)
        addSetButton:SetText("+")

        function addSetButton:OnEnter()
            local PosX, PosY = self:GetOffset()
            api.Interface:SetTooltipOnPos("Quick Equip\nAdd Preset", mainCanvas, PosX + 15, PosY + getTooltipOffsetY(PosY, 60))
        end
        function addSetButton:OnLeave()
            local PosX, PosY = self:GetOffset()
            api.Interface:SetTooltipOnPos(nil, mainCanvas, PosX + 15, PosY + getTooltipOffsetY(PosY, 60))
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

            local loadout = { name = setName, gear = captureCurrentGear() }

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

    addSetButton:RemoveAllAnchors()
    addSetButton:AddAnchor("TOPLEFT", addButtonX, 3)
    addSetButton:Show(true)

    local addButtonWidth = addSetButton:GetWidth()
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

    if #enqueuedItems == 0 then
        enableAllGearSetButtons()
    end

    mainCanvas:Show(true)
    mainCanvas:EnableDrag(true)
end

-- ===== Enable / disable (Misc tab toggle) =====

-- Hides the bar (and any open popup/menu) without touching settings.
local function destroyBarUI()
    closeContextMenu()
    closePrompt()

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

-- ===== Misc tab section: just the enable/disable toggle =====

function quick_equip_addon.CreateUI(wndParent)
    LoadQuickEquipSettings()

    local container = wndParent:CreateChildWidget("emptywidget", "quickEquipMiscSection", 0, true)
    container:SetExtent(500, 30)

    local enableCheck = container:CreateChildWidget("checkbutton", "quickEquipEnableCheck", 0, true)
    enableCheck:SetExtent(18, 17)
    enableCheck:AddAnchor("TOPLEFT", container, 0, 5) -- temporary; recentered below once the label's width is known
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

    -- Center the checkbox+label pair as a whole inside the 500-wide
    -- section, based on the label's actual rendered width, instead of a
    -- fixed guessed offset -- keeps it lined up with the section titles
    -- above/below regardless of font metrics.
    local checkboxGap = 6
    local labelWidth = enableLbl:GetWidth() or 220
    local totalWidth = 18 + checkboxGap + labelWidth
    local containerWidth = container:GetWidth() or 500
    local startX = math.floor((containerWidth - totalWidth) / 2)
    enableCheck:RemoveAllAnchors()
    enableCheck:AddAnchor("TOPLEFT", container, startX, 5)

    enableCheck:SetChecked(settings.enabled, false)

    function enableCheck:OnCheckChanged()
        setEnabled(self:GetChecked())
    end
    enableCheck:SetHandler("OnCheckChanged", enableCheck.OnCheckChanged)

    -- ===== Reset position button =====
    -- Small native reset arrow button to the right of the label. Clicking it
    -- snaps the bar back to the default position (DEFAULT_X, DEFAULT_Y) and saves.
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
        -- If the bar is currently enabled (and therefore rendered), move it
        -- to the new position immediately without requiring a relog.
        if settings.enabled and mainCanvas then
            mainCanvas:RemoveAllAnchors()
            mainCanvas:AddAnchor("TOPLEFT", "UIParent", DEFAULT_X, DEFAULT_Y)
        elseif settings.enabled then
            -- Bar was enabled but mainCanvas is gone (rare edge case);
            -- re-render it from scratch so it appears at the default spot.
            renderGearSetUI()
        end
    end
    resetPosBtn:SetHandler("OnClick", resetPosBtn.OnClick)

    return container
end

-- ===== Lifecycle =====

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
    destroyBarUI()
end

-- Called every tick from main.lua's central UPDATE dispatcher (see the
-- module-level comment at the top of main.lua's own OnUpdate about why
-- every sub-module funnels through there instead of registering its own
-- api.On("UPDATE", ...)).
function quick_equip_addon:OnUpdate(dt)
    charCheckTimer = charCheckTimer + (type(dt) == "number" and dt or 0)
    if charCheckTimer >= 500 then
        charCheckTimer = 0
        SyncCharacterStateIfNeeded()
    end
    if dragState then updateDragIndicator() end
end

return quick_equip_addon
