local M = {}

local SETTINGS_FILE = "elu_functions_tools_position.lua"
local DEFAULT_X = 20
local DEFAULT_Y = 80

local settings = { x = DEFAULT_X, y = DEFAULT_Y, visible = false }

local containerWindow
local portalsBtn
local skinBtn

local PORTAL_SAFE = "safe"
local PORTAL_UNSAFE_TEMP = "unsafe_temp"
local PORTAL_UNSAFE_OFF = "unsafe_off"

local portalMode = PORTAL_SAFE
local portalClockTimer = 0
local PORTAL_CLOCK_RESET_TIME = 10000

local unsafeCausedByAddon = false

local buttonGap = 4
local portalsW = 58
local skinW = 84
local buttonH = 28
local FRAME_PADDING = 4

local _onLoadStarted = false

local function setPortalRestriction(isSafe)
	local target = isSafe and 1 or 0
	local ok, err = pcall(function() api.Option:SetOnlyUseMyPortalSetting(target) end)
	if not ok then
		return
	end
end

local function isDefaultAppearanceOn()
	local ok, value = pcall(function() return api.Option:GetCustomCloneModeSetting() end)
	if not ok or value == nil then return false end
	return value ~= 0
end

local function updateSkinButtonVisual()
	if skinBtn == nil then return end
	if isDefaultAppearanceOn() then
		skinBtn:SetText("Skin: OFF")
		pcall(function() ApplyTextColor(skinBtn, {1, 0.35, 0.35, 1}) end)
	else
		skinBtn:SetText("Skin: ON")
		pcall(function() ApplyButtonSkin(skinBtn, BUTTON_BASIC.DEFAULT) end)
	end
	skinBtn:SetExtent(skinW, buttonH)
end

local function updatePortalsButtonVisual()
	if portalsBtn == nil then return end
	if portalMode == PORTAL_SAFE then
		portalsBtn:SetText("Portals")
		pcall(function() ApplyButtonSkin(portalsBtn, BUTTON_BASIC.DEFAULT) end)
	elseif portalMode == PORTAL_UNSAFE_TEMP then
		portalsBtn:SetText("UNSAFE")
		pcall(function() ApplyTextColor(portalsBtn, {1, 0.3, 0.3, 1}) end)
	else
		portalsBtn:SetText("OFF")
		pcall(function() ApplyTextColor(portalsBtn, {1, 0.3, 0.3, 1}) end)
	end
	portalsBtn:SetExtent(portalsW, buttonH)
end

local function toggleDefaultSkin()
	local newValue = isDefaultAppearanceOn() and 0 or 1
	local ok = pcall(function() api.Option:SetCustomCloneModeSetting(newValue) end)
	if ok then
		api.Log:Info("[Elu Functions Tools] Default Player Appearances is now " .. (newValue == 1 and "ON" or "OFF") .. ".")
	else
		api.Log:Info("[Elu Functions Tools] Could not change Default Player Appearances -- this client build may not support it.")
	end
	updateSkinButtonVisual()
end

local function saveSettings()
	pcall(function() api.File:Write(SETTINGS_FILE, settings) end)
end

local SANE_COORD_LIMIT = 10000

local function loadSettings()
	local ok, data = pcall(function() return api.File:Read(SETTINGS_FILE) end)
	if ok and type(data) == "table" then
		if type(data.x) == "number" and math.abs(data.x) <= SANE_COORD_LIMIT then
			settings.x = data.x
		end
		if type(data.y) == "number" and math.abs(data.y) <= SANE_COORD_LIMIT then
			settings.y = data.y
		end
		if data.visible ~= nil then settings.visible = data.visible end
	end
end

local function savePosition()
	if containerWindow == nil then return end
	local x, y = containerWindow:GetOffset()
	if x and y then
		settings.x = x
		settings.y = y
		saveSettings()
	end
end

local function startMovingButtons()
	if containerWindow == nil then return end
	if not api.Input:IsShiftKeyDown() then return end
	containerWindow:StartMoving()
	api.Cursor:ClearCursor()
	api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
end

local function stopMovingButtons()
	if containerWindow == nil then return end
	containerWindow:StopMovingOrSizing()
	api.Cursor:ClearCursor()
	savePosition()
end

local function OnUpdate(dt)
	if portalMode == PORTAL_UNSAFE_TEMP then
		portalClockTimer = portalClockTimer + dt
		if portalClockTimer > PORTAL_CLOCK_RESET_TIME then
			portalMode = PORTAL_SAFE
			portalClockTimer = 0
			unsafeCausedByAddon = false
			setPortalRestriction(true)
			api.Log:Info("[Elu Functions Tools] Other players' portals are disabled again (safe).")
			updatePortalsButtonVisual()
		end
	end
end

local function IsVisible()
	if containerWindow == nil then
		return false
	end
	return containerWindow:IsVisible()
end

local function SetVisible(v)
	if containerWindow == nil then return end
	local shouldShow = v and true or false

	if not shouldShow and portalMode ~= PORTAL_SAFE and unsafeCausedByAddon then
		portalMode = PORTAL_SAFE
		portalClockTimer = 0
		unsafeCausedByAddon = false
		setPortalRestriction(true)
		api.Log:Info("[Elu Functions Tools] Tool Functions turned off -- other players' portals are disabled again (safe).")
		updatePortalsButtonVisual()
	end

	containerWindow:Show(shouldShow)
	if shouldShow then
		containerWindow:Raise()
		updatePortalsButtonVisual()
		updateSkinButtonVisual()
	end
	settings.visible = shouldShow
	saveSettings()
end

local function OnLoad()
	if containerWindow then
		loadSettings()
		containerWindow:Show(settings.visible == true)
		return
	end
	if _onLoadStarted then return end
	_onLoadStarted = true

	loadSettings()

	local ogValue = api.Option:GetOnlyUseMyPortalSetting()
	if settings.visible then
		api.Log:Info("[Elu Functions Tools] Original 'Only Use My Portal' setting value: " .. tostring(ogValue))
		if ogValue == 0 then
			setPortalRestriction(true)
		end
		portalMode = PORTAL_SAFE
		portalClockTimer = 0
		unsafeCausedByAddon = false
	else
		portalMode = (ogValue == 0) and PORTAL_UNSAFE_OFF or PORTAL_SAFE
	end

	containerWindow = api.Interface:CreateEmptyWindow("eluFunctionsToolsWindow", "UIParent")
	containerWindow:SetExtent(portalsW + buttonGap + skinW + FRAME_PADDING * 2, buttonH + FRAME_PADDING * 2)
	containerWindow:AddAnchor("TOPLEFT", "UIParent", settings.x, settings.y)
	containerWindow:EnableDrag(true)
	function containerWindow:OnDragStart() startMovingButtons() end
	containerWindow:SetHandler("OnDragStart", containerWindow.OnDragStart)
	function containerWindow:OnDragStop() stopMovingButtons() end
	containerWindow:SetHandler("OnDragStop", containerWindow.OnDragStop)

	local frameBg = containerWindow:CreateColorDrawable(0, 0, 0, 0.35, "background")
	frameBg:AddAnchor("TOPLEFT", containerWindow, 0, 0)
	frameBg:AddAnchor("BOTTOMRIGHT", containerWindow, 0, 0)

	portalsBtn = containerWindow:CreateChildWidget("button", "eluPortalsBtn", 0, true)
	ApplyButtonSkin(portalsBtn, BUTTON_BASIC.DEFAULT)
	portalsBtn:SetText("Portals")
	portalsBtn:SetExtent(portalsW, buttonH)
	portalsBtn:AddAnchor("TOPLEFT", containerWindow, FRAME_PADDING, FRAME_PADDING)
	portalsBtn:EnableDrag(true)
	function portalsBtn:OnClick()
		if api.Input:IsShiftKeyDown() then return end
		if portalMode == PORTAL_SAFE then
			portalMode = PORTAL_UNSAFE_TEMP
			portalClockTimer = 0
			unsafeCausedByAddon = true
			setPortalRestriction(false)
			api.Log:Info("[Elu Functions Tools] You can use other players' portals for 10 seconds.")
		elseif portalMode == PORTAL_UNSAFE_TEMP then
			portalMode = PORTAL_UNSAFE_OFF
			api.Log:Info("[Elu Functions Tools] Portal restriction left OFF -- click Portals again to turn it back on.")
		else
			portalMode = PORTAL_SAFE
			unsafeCausedByAddon = false
			setPortalRestriction(true)
			api.Log:Info("[Elu Functions Tools] Other players' portals are disabled again (safe).")
		end
		updatePortalsButtonVisual()
	end
	portalsBtn:SetHandler("OnClick", portalsBtn.OnClick)
	function portalsBtn:OnDragStart() startMovingButtons() end
	portalsBtn:SetHandler("OnDragStart", portalsBtn.OnDragStart)
	function portalsBtn:OnDragStop() stopMovingButtons() end
	portalsBtn:SetHandler("OnDragStop", portalsBtn.OnDragStop)
	function portalsBtn:OnEnter() updatePortalsButtonVisual() end
	portalsBtn:SetHandler("OnEnter", portalsBtn.OnEnter)
	function portalsBtn:OnLeave() updatePortalsButtonVisual() end
	portalsBtn:SetHandler("OnLeave", portalsBtn.OnLeave)

	skinBtn = containerWindow:CreateChildWidget("button", "eluSkinBtn", 0, true)
	ApplyButtonSkin(skinBtn, BUTTON_BASIC.DEFAULT)
	skinBtn:SetExtent(skinW, buttonH)
	skinBtn:AddAnchor("TOPLEFT", containerWindow, FRAME_PADDING + portalsW + buttonGap, FRAME_PADDING)
	skinBtn:EnableDrag(true)
	function skinBtn:OnClick()
		if api.Input:IsShiftKeyDown() then return end
		toggleDefaultSkin()
	end
	skinBtn:SetHandler("OnClick", skinBtn.OnClick)
	function skinBtn:OnDragStart() startMovingButtons() end
	skinBtn:SetHandler("OnDragStart", skinBtn.OnDragStart)
	function skinBtn:OnDragStop() stopMovingButtons() end
	skinBtn:SetHandler("OnDragStop", skinBtn.OnDragStop)
	function skinBtn:OnEnter() updateSkinButtonVisual() end
	skinBtn:SetHandler("OnEnter", skinBtn.OnEnter)
	function skinBtn:OnLeave() updateSkinButtonVisual() end
	skinBtn:SetHandler("OnLeave", skinBtn.OnLeave)

	updateSkinButtonVisual()
	updatePortalsButtonVisual()

	containerWindow:Show(settings.visible == true)
	if settings.visible == true then
		containerWindow:Raise()
	end
end

local function OnUnload()
	_onLoadStarted = false

	saveSettings()

	if containerWindow ~= nil then
		containerWindow:Show(false)
	end
end

M.OnLoad = OnLoad
M.OnUnload = OnUnload
M.OnUpdate = OnUpdate
M.IsVisible = IsVisible
M.SetVisible = SetVisible

return M
