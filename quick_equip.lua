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
    y = 400,
    gear_sets = {}
}

local function SaveQuickEquipSettings()
    EluTrackerSettings.quickEquip = settings
    SaveEluTrackerSettings()
end

local function LoadQuickEquipSettings()
    local data = EluTrackerSettings.quickEquip
    if type(data) == "table" then
        if data.enabled ~= nil then settings.enabled = data.enabled end
        if data.x ~= nil then settings.x = data.x end
        if data.y ~= nil then settings.y = data.y end
        if type(data.gear_sets) == "table" then settings.gear_sets = data.gear_sets end
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

local function getUniqueWidgetId(prefix)
    widgetCounter = widgetCounter + 1
    return "eluQuickEquip_" .. prefix .. "_" .. widgetCounter .. "_" .. tostring(api.Time:GetUiMsec())
end

local function safeDestroyWidget(widget)
    if widget then
        widget:Show(false)
    end
    return nil
end

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
-- Closable with the X button or the Esc key, in addition to Confirm.

function closePrompt()
    if promptCanvas then
        promptCanvas:Show(false)
        pcall(function() api.Interface:Free(promptCanvas) end)
        promptCanvas = nil
    end
end

local function openNamePrompt(question, defaultText, onConfirm)
    closePrompt()

    local popup = api.Interface:CreateEmptyWindow(getUniqueWidgetId("prompt"), "UIParent")
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
    label:SetText(question or "Enter a name:")
    label.style:SetAlign(ALIGN.CENTER)
    label:SetExtent(260, 25)
    label:AddAnchor("TOP", popup, 0, 25)

    local textEdit = W_CTRL.CreateEdit(getUniqueWidgetId("promptInput"), popup)
    textEdit:SetExtent(240, 30)
    textEdit:AddAnchor("TOP", label, "BOTTOM", 0, 8)
    if defaultText and defaultText ~= "" then
        textEdit:SetText(defaultText)
    end

    local function doConfirm()
        local text = textEdit and textEdit:GetText() or ""
        closePrompt()
        if onConfirm then onConfirm(text) end
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

    popup:Show(true)
    promptCanvas = popup
    return popup
end

-- ===== Ctrl+Click context menu (Replace / Rename / Delete) =====

function closeContextMenu()
    if contextMenu then
        -- NOTE: only hides, does not Free() the menu. This close path is
        -- also reached from INSIDE the menu's own registered global
        -- MOUSE_DOWN handler (the click-outside-to-close feature) -- i.e.
        -- it can free the widget from within that same widget's own event
        -- dispatch. That broke Ctrl+Click again after the first open/close
        -- cycle (confirmed: the menu opened fine once, but never came back
        -- after being closed by an outside click). addonlibrary's own
        -- popup_menu.lua avoids this entirely by never freeing its popup at
        -- all -- it just Show(false)s and reuses the same widget across
        -- every open. Do the same here: leave the small, rarely-created
        -- menu window un-freed rather than repeat that failure mode.
        contextMenu:Show(false)
        contextMenu = nil
    end
end

local function openContextMenu(gearSetIndex)
    closeContextMenu()

    local gearSet = settings.gear_sets[gearSetIndex]
    if not gearSet then
        return
    end

    local optionHeight = 24
    local menuWidth = 120
    local options = {
        {
            text = "Replace",
            action = function()
                local target = settings.gear_sets[gearSetIndex]
                if target and target.name == gearSet.name then
                    target.gear = captureCurrentGear()
                    SaveQuickEquipSettings()
                    renderGearSetUI()
                end
            end
        },
        {
            text = "Rename",
            action = function()
                openNamePrompt("Rename gear set", gearSet.name, function(newName)
                    newName = (newName or ""):match("^%s*(.-)%s*$")
                    if newName == "" then return end
                    local target = settings.gear_sets[gearSetIndex]
                    if target and target.name == gearSet.name then
                        target.name = newName
                        SaveQuickEquipSettings()
                        renderGearSetUI()
                    end
                end)
            end
        },
        {
            text = "Delete",
            action = function()
                local target = settings.gear_sets[gearSetIndex]
                if target and target.name == gearSet.name then
                    table.remove(settings.gear_sets, gearSetIndex)
                    SaveQuickEquipSettings()
                    renderGearSetUI()
                end
            end
        }
    }

    -- The window itself is created OUTSIDE the pcall (and kept in this
    -- outer-scope local) specifically so a failed build can still clean it
    -- up below. It was created INSIDE the pcall before, and every single
    -- failed build (e.g. every Ctrl+Click while the UIParent bug was still
    -- present) left that half-built window behind forever, uncounted and
    -- unreachable, because the error aborted the function before it ever
    -- reached menu:Show(true). Confirmed directly in the game's own log
    -- from that session: Elu_Tracker's addon-window count climbed from 254
    -- to 373 in under an hour of testing, memory climbing from ~2860MB to
    -- 3190MB right up to the session's end -- a real, self-inflicted leak,
    -- and almost certainly what caused that crash (and the resulting
    -- Elu_Tracker settings reset, since a crash mid-save of the shared
    -- settings file can corrupt it).
    local menu = api.Interface:CreateEmptyWindow(getUniqueWidgetId("ctxMenu"), "UIParent")

    -- The rest of the menu build is wrapped in one pcall so that if
    -- anything in here errors, we log the REAL error message instead of it
    -- being silently swallowed by the engine (which is what made the
    -- original UIParent bug so hard to track down without being able to
    -- run the game directly).
    local buildOk, buildErr = pcall(function()
        local menuHeight = optionHeight * #options + 8
        menu:SetExtent(menuWidth, menuHeight)

        local mx, my = api.Input:GetMousePos()

        -- Stay on the one anchor POINT already proven to work everywhere
        -- else in this file (TOPLEFT against "UIParent") -- switching to
        -- BOTTOMLEFT/TOPRIGHT/BOTTOMRIGHT for the "open upward" case is
        -- what broke visibility entirely last time (untested anchor points
        -- against a plain string target). Instead, keep TOPLEFT and just
        -- shift the OFFSET numbers: if the menu would run past the bottom
        -- or right edge of the screen, subtract its own height/width from
        -- the anchor position so it opens upward/leftward from the cursor
        -- instead of downward/rightward -- same anchor mechanics, just a
        -- different starting corner.
        local okSize, screenW, screenH = pcall(function()
            return api.Interface:GetScreenWidth(), api.Interface:GetScreenHeight()
        end)
        if not okSize or not screenW or not screenH then
            screenW, screenH = 2560, 1080 -- conservative fallback if the call is ever unavailable
        end

        local anchorX = mx or 0
        local anchorY = my or 0
        if my and (my + menuHeight) > screenH then
            anchorY = my - menuHeight
        end
        if mx and (mx + menuWidth) > screenW then
            anchorX = mx - menuWidth
        end

        menu:RemoveAllAnchors()
        menu:AddAnchor("TOPLEFT", "UIParent", anchorX, anchorY)
        pcall(function() menu:SetCloseOnEscape(true) end)
        pcall(function()
            menu:SetHandler("OnCloseByEsc", function() closeContextMenu() end)
        end)

        -- Close the menu on any click outside of it (same technique
        -- addonlibrary's popup menu uses: watch MOUSE_DOWN and hide unless the
        -- clicked widget is part of this menu).
        pcall(function()
            menu:RegisterEvent("MOUSE_DOWN")
            menu:SetHandler("OnEvent", function(this, event, widgetId)
                if event == "MOUSE_DOWN" and contextMenu == menu and not menu:IsDescendantWidget(widgetId) then
                    closeContextMenu()
                end
            end)
        end)

        local background = menu:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        background:SetTextureInfo("bg_quest")
        background:SetColor(0, 0, 0, 0.92)
        background:AddAnchor("TOPLEFT", menu, 0, 0)
        background:AddAnchor("BOTTOMRIGHT", menu, 0, 0)

        for i, option in ipairs(options) do
            local btn = menu:CreateChildWidget("button", "ctxOption" .. i, 0, true)
            btn:SetText(option.text)
            btn:SetExtent(menuWidth - 8, optionHeight - 2)
            btn:RemoveAllAnchors()
            btn:AddAnchor("TOP", menu, 0, 4 + (i - 1) * optionHeight)
            api.Interface:ApplyButtonSkin(btn, BUTTON_BASIC.DEFAULT)
            if option.text == "Delete" then
                ApplyTextColor(btn, FONT_COLOR.RED)
            end
            btn.OnClick = function()
                closeContextMenu()
                option.action()
            end
            btn:SetHandler("OnClick", btn.OnClick)
        end

        menu:Show(true)
        contextMenu = menu
    end)

    if not buildOk then
        -- Clean up the half-built window instead of leaking it -- see the
        -- comment above `menu`'s creation for why this matters.
        pcall(function() menu:Show(false) end)
        pcall(function() api.Interface:Free(menu) end)
        if contextMenu == menu then
            contextMenu = nil
        end
    end
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

    for i, btn in ipairs(gearSetButtons) do
        gearSetButtons[i] = safeDestroyWidget(btn)
    end
    gearSetButtons = {}
    buttonRects = {}
    buttonLocalX = {}

    addSetButton = safeDestroyWidget(addSetButton)

    if mainCanvas then
        -- NOTE: this only hides the old canvas, it does not Free() it.
        -- An earlier attempt to Free() it here (this function can run
        -- from inside a click/drag callback on one of mainCanvas's own
        -- child buttons -- a preset's OnDragStop, or a context-menu
        -- option's OnClick -- reordering/renaming/deleting a preset all
        -- go through here) broke Ctrl+Click's context menu, and a follow
        -- up attempt to defer the Free() by one tick did not fix it
        -- either. Reverted to the safe, always-worked behavior rather
        -- than keep guessing at a live-game-only bug from static code.
        -- This does mean renderGearSetUI leaves the previous canvas
        -- window behind on every add/rename/delete/reorder -- see the
        -- audit report for that tradeoff.
        mainCanvas:Show(false)
        mainCanvas = nil
    end
    -- dragIndicator is a child of mainCanvas above, so it was just hidden
    -- along with it; drop the stale Lua-side reference too (it will be
    -- recreated below along with the rest of the bar).
    dragIndicator = nil

    local canvas_x = settings.x or 200
    local canvas_y = settings.y or 40
    local canvasId = getUniqueWidgetId("bar")

    mainCanvas = api.Interface:CreateEmptyWindow(canvasId, "UIParent")
    mainCanvas.background = mainCanvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    mainCanvas.background:SetTextureInfo("bg_quest")
    mainCanvas.background:SetColor(0, 0, 0, 0.6)
    mainCanvas.background:AddAnchor("TOPLEFT", mainCanvas, 0, 0)
    mainCanvas.background:AddAnchor("BOTTOMRIGHT", mainCanvas, 0, 0)
    mainCanvas:AddAnchor("TOPLEFT", "UIParent", canvas_x, canvas_y)

    -- Shift + drag on empty bar space moves the whole bar (unchanged from
    -- the original addon). Dragging directly on a preset button is handled
    -- by that button instead (see below), and reorders presets.
    function mainCanvas:OnDragStart()
        if api.Input:IsShiftKeyDown() then
            mainCanvas:StartMoving()
            api.Cursor:ClearCursor()
            api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
        end
    end
    mainCanvas:SetHandler("OnDragStart", mainCanvas.OnDragStart)

    function mainCanvas:OnDragStop()
        -- Use self (bound to this exact widget instance) rather than the
        -- outer mainCanvas variable for every call below: renderGearSetUI()
        -- at the end reassigns mainCanvas to a brand new widget, so a bare
        -- `mainCanvas:...` reference here would risk operating on the wrong
        -- (newly created, never-dragged) widget once that happens.
        local current_x, current_y = self:GetOffset()
        settings.x = current_x
        settings.y = current_y
        SaveQuickEquipSettings()
        self:StopMovingOrSizing()
        api.Cursor:ClearCursor()

        -- Re-render so buttonRects/buttonLocalX (both snapshotted from
        -- canvas_x/canvas_y at render time) get rebuilt against the bar's
        -- new position. Without this, findClosestButtonIndex kept comparing
        -- the live mouse position against stale pre-move coordinates on the
        -- very next preset drag-reorder -- wrong drop target, and the live
        -- "drop here" indicator pointing at the wrong slot too. Safe to call
        -- from here for the same reason it's already safe from a child
        -- button's own OnDragStop (see moveGearSet above): it never Free()s
        -- the old canvas, only hides it.
        renderGearSetUI()
    end
    mainCanvas:SetHandler("OnDragStop", mainCanvas.OnDragStop)

    local baseCanvasHeight = BAR_HEIGHT
    local buttonBaseWidth = 70
    local buttonGap = 5
    local leftPadding = 9
    local rightPadding = 9
    local addButtonExtraGap = 10

    local numGearSets = settings.gear_sets and #settings.gear_sets or 0
    mainCanvas:SetExtent(90, baseCanvasHeight)

    local dynamicButtonsWidth = 0

    for i, gear_set in ipairs(settings.gear_sets) do
        local buttonId = getUniqueWidgetId("btn")
        local buttonX = leftPadding + dynamicButtonsWidth

        local setBtn = api.Interface:CreateWidget('button', buttonId, mainCanvas)
        setBtn:AddAnchor("TOPLEFT", buttonX, 3)
        setBtn:SetText(gear_set.name)
        local skin = BUTTON_BASIC.DEFAULT
        skin.width = buttonBaseWidth
        skin.height = 30
        api.Interface:ApplyButtonSkin(setBtn, skin)
        setBtn:Show(true)

        local actualButtonWidth = setBtn:GetWidth()
        buttonRects[i] = { x1 = canvas_x + buttonX, x2 = canvas_x + buttonX + actualButtonWidth }
        buttonLocalX[i] = { x1 = buttonX, x2 = buttonX + actualButtonWidth }
        dynamicButtonsWidth = dynamicButtonsWidth + actualButtonWidth + buttonGap

        -- Left-click: equip. Ctrl + click: Replace / Rename / Delete menu.
        -- (The addon API has no working right-click event for this widget
        -- type, confirmed by live testing, so Ctrl+Click is used instead.
        -- Shift is reserved for drag-to-reorder, so a plain shift+click
        -- without movement just equips as usual.)
        setBtn.OnClick = function()
            local ctrlDown = api.Input:IsControlKeyDown()
            if ctrlDown then
                closeContextMenu()
                openContextMenu(i)
                return
            end
            closeContextMenu()
            disableAllGearSetButtons()
            enqueueLoadoutEquipment(gear_set)
        end
        setBtn:SetHandler("OnClick", setBtn.OnClick)

        -- Shift + drag: reorder this preset among the others.
        function setBtn:OnDragStart()
            if not api.Input:IsShiftKeyDown() then
                return
            end
            closeContextMenu()
            dragState = { index = i }
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
            if not dragging or dragging.index ~= i then
                return
            end
            local mx = api.Input:GetMousePos()
            local targetIndex = findClosestButtonIndex(mx)
            if targetIndex and targetIndex ~= i then
                moveGearSet(i, targetIndex)
            else
                -- Nothing to reorder (only one preset, or dropped back on its
                -- own slot) -- still re-render so the button snaps back into
                -- its place in the bar instead of staying wherever it was
                -- dragged to on screen.
                renderGearSetUI()
            end
        end
        setBtn:SetHandler("OnDragStop", setBtn.OnDragStop)

        if setBtn.RegisterForDrag then pcall(function() setBtn:RegisterForDrag("LeftButton") end) end
        if setBtn.EnableDrag then pcall(function() setBtn:EnableDrag(true) end) end

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

        table.insert(gearSetButtons, setBtn)
    end

    local addButtonId = getUniqueWidgetId("addBtn")
    local useExtraGap = numGearSets > 0 and addButtonExtraGap or 0
    local addButtonX = leftPadding + dynamicButtonsWidth + useExtraGap

    addSetButton = api.Interface:CreateWidget('button', addButtonId, mainCanvas)
    addSetButton:AddAnchor("TOPLEFT", addButtonX, 3)
    addSetButton:SetText("+")
    local addSkin = BUTTON_BASIC.DEFAULT
    addSkin.width = 60
    addSkin.height = 30
    api.Interface:ApplyButtonSkin(addSetButton, addSkin)
    addSetButton:Show(true)

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

    local addButtonWidth = addSetButton:GetWidth()
    local totalRequiredWidth = leftPadding + dynamicButtonsWidth + addButtonWidth + rightPadding + useExtraGap
    mainCanvas:SetExtent(totalRequiredWidth, baseCanvasHeight)

    -- Live "drop here" highlight for shift+drag reordering. Created hidden;
    -- quick_equip_addon:OnUpdate shows and repositions it (via
    -- updateDragIndicator) over whichever slot the dragged preset would
    -- land in, so reordering has visual feedback instead of being blind
    -- until release.
    local indicatorId = getUniqueWidgetId("dragIndicator")
    dragIndicator = mainCanvas:CreateChildWidget("emptywidget", indicatorId, 0, true)
    dragIndicator.bg = dragIndicator:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    dragIndicator.bg:SetTextureInfo("bg_quest")
    dragIndicator.bg:SetColor(1, 0.82, 0.15, 0.55)
    dragIndicator.bg:AddAnchor("TOPLEFT", dragIndicator, 0, 0)
    dragIndicator.bg:AddAnchor("BOTTOMRIGHT", dragIndicator, 0, 0)
    dragIndicator:SetExtent(buttonBaseWidth, baseCanvasHeight - 4)
    dragIndicator:Show(false)

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

    if #enqueuedItems == 0 then
        enableAllGearSetButtons()
    end

    mainCanvas:Show(true)
    mainCanvas:EnableDrag(true)
end

-- ===== Enable / disable (Misc tab toggle) =====

-- Tears down the bar (and any open popup/menu) without touching settings.
-- Shared by OnUnload and by turning the toggle off.
local function destroyBarUI()
    closeContextMenu()
    closePrompt()

    for i, btn in ipairs(gearSetButtons) do
        gearSetButtons[i] = safeDestroyWidget(btn)
    end
    gearSetButtons = {}

    addSetButton = safeDestroyWidget(addSetButton)

    if mainCanvas then
        mainCanvas:Show(false)
        pcall(function() api.Interface:Free(mainCanvas) end)
        mainCanvas = nil
    end
    -- dragIndicator is a child of mainCanvas, freed along with it above;
    -- drop the now-stale Lua-side reference and cancel any in-progress drag.
    dragIndicator = nil
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
    local container = wndParent:CreateChildWidget("emptywidget", "quickEquipMiscSection", 0, true)
    container:SetExtent(500, 30)

    local enableCheck = container:CreateChildWidget("checkbutton", "quickEquipEnableCheck", 0, true)
    enableCheck:SetExtent(18, 17)
    enableCheck:AddAnchor("TOPLEFT", container, 0, 5) -- temporary; recentered below once the label's width is known

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

    return container
end

-- ===== Lifecycle =====

function quick_equip_addon:OnLoad()
    LoadQuickEquipSettings()
    if settings.enabled then
        renderGearSetUI()
    end
end

function quick_equip_addon:OnUnload()
    destroyBarUI()
end

-- Called every tick from main.lua's central UPDATE dispatcher (see the
-- module-level comment at the top of main.lua's own OnUpdate about why
-- every sub-module funnels through there instead of registering its own
-- api.On("UPDATE", ...)). Only does anything while a shift+drag reorder is
-- in progress; see updateDragIndicator above.
function quick_equip_addon:OnUpdate(dt)
    updateDragIndicator()
end

return quick_equip_addon
