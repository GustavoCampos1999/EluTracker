-- ===== Elu Functions Tools =====
-- Formerly a separate addon ("Unsafe Portals", Addon/unsafe_portals/), now
-- merged directly into Elu_Tracker as a required module, per an explicit
-- request: running this as two addons meant Elu_Tracker's "Toggle Func"
-- button had to reach across addon sandboxes through a hand-rolled
-- api.UnsafePortalsBridge global (bare globals are NOT shared between
-- addons here -- each addon script gets its own isolated global
-- environment; the one table every addon genuinely shares is the one
-- require("api") always returns). That bridge was a real, repeated source
-- of fragility: if unsafe_portals loaded after Elu_Tracker, failed to load,
-- or got disabled, every click logged exactly the error the user saw twice
-- in a screenshot -- "[Elu Tracker] Unsafe Portals addon not found -- is it
-- enabled?" -- with Toggle Func otherwise looking broken. As a module
-- required directly by Elu_Tracker's own main.lua (same require()
-- mechanism already used for guild_check.lua, range_meter.lua, etc.), that
-- whole failure class is gone: there is no other addon to fail to find,
-- because there is no other addon.
--
-- Everything below is otherwise unchanged from the addon version: the
-- TOPLEFT-anchor position fix (AddAnchor's y and GetOffset()'s y turned out
-- NOT to be the same coordinate space -- see SANE_COORD_LIMIT below), the
-- small transparent backdrop frame, the :SetExtent() re-assertion on every
-- visual update (ApplyButtonSkin silently regrows a widget back toward its
-- skin's own natural size), and the OnEnter/OnLeave re-color (ApplyTextColor
-- is a one-shot override the engine doesn't reliably restore on mouse
-- leave). All of that was hard-won from reading this file's own debug log,
-- not guessed, so none of it changed in this merge -- only the cross-addon
-- bridge is gone, replaced with plain module functions Elu_Tracker/main.lua
-- calls directly.

local M = {}

-- Fresh settings file: the old unsafe_portals addon's saved position/
-- visibility has no bearing on this module (different folder, different
-- File:Write/Read namespace only in the sense that the OLD file lived under
-- a name tied to that addon) -- starting clean avoids any chance of ever
-- reloading a stale/corrupted position saved before the coordinate-space
-- fix above existed.
local SETTINGS_FILE = "elu_functions_tools_position.lua"
local DEFAULT_X = 20
local DEFAULT_Y = 80

-- visible starts false on purpose: a brand new install, or an update from a
-- version that never had this field, should come up with the buttons
-- HIDDEN until the player explicitly turns them on from Elu Tracker's Misc.
-- tab. Only an explicit `visible = true` saved in SETTINGS_FILE by a
-- previous session overrides this.
local settings = { x = DEFAULT_X, y = DEFAULT_Y, visible = false }

-- ===== Debug logging =====
-- File-based (not chat-log) so it can be inspected after the fact without
-- catching a message live: writes a bounded, numbered trace to
-- Addon/elu_functions_tools_debug.lua. Every call is pcall-wrapped so a
-- logging failure can never break the addon itself.
local DEBUG_FILE = "elu_functions_tools_debug.lua"
local DEBUG_MAX_LINES = 200
local debugLog = {}
local _dbgSeq = 0
local function Dbg(msg)
	_dbgSeq = _dbgSeq + 1
	table.insert(debugLog, "#" .. _dbgSeq .. " " .. tostring(msg))
	while #debugLog > DEBUG_MAX_LINES do
		table.remove(debugLog, 1)
	end
	pcall(function() api.File:Write(DEBUG_FILE, debugLog) end)
end

local containerWindow
local portalsBtn
local skinBtn

-- Portal button state machine -- three states, not a plain on/off:
--   PORTAL_SAFE        -- default/normal. "Only Use My Portal" is ON.
--                         Button shows "Portals". Click -> PORTAL_UNSAFE_TEMP.
--   PORTAL_UNSAFE_TEMP -- exactly the original button behavior: "Only Use
--                         My Portal" is OFF and a 10s timer is running that
--                         will silently put it back to PORTAL_SAFE on its
--                         own if the button isn't touched again. Button
--                         shows "UNSAFE". Click again (before the timer
--                         fires) -> PORTAL_UNSAFE_OFF.
--   PORTAL_UNSAFE_OFF  -- still unsafe, but the 10s timer is cancelled: it
--                         now stays this way until clicked again, instead
--                         of reverting on its own. Button shows "OFF"
--                         (i.e. "the block on entering other players'
--                         portals is OFF"). Click -> PORTAL_SAFE.
local PORTAL_SAFE = "safe"
local PORTAL_UNSAFE_TEMP = "unsafe_temp"
local PORTAL_UNSAFE_OFF = "unsafe_off"

local portalMode = PORTAL_SAFE
local portalClockTimer = 0
local PORTAL_CLOCK_RESET_TIME = 10000

-- True only while the CURRENT unsafe/off state was actually caused by this
-- module (a click that moved PORTAL_SAFE -> PORTAL_UNSAFE_TEMP, or that ->
-- PORTAL_UNSAFE_OFF). False whenever portalMode is just MIRRORING an
-- already-unsafe real setting found on load without this module ever
-- touching it (see the OnLoad "else" branch below). That distinction is
-- what SetVisible needs, below: turning Tool Functions off must clean up
-- after what THIS module made unsafe (no button is left visible to fix it
-- once the window hides), but must never silently overwrite a setting the
-- player configured on their own, entirely outside this addon, that this
-- module was only ever mirroring.
local unsafeCausedByAddon = false

-- Hoisted so the *ButtonVisual functions below can reach them -- needed to
-- re-assert the button size on every state update, see the comment on that
-- below.
local buttonGap = 4
local portalsW = 58
local skinW = 84
local buttonH = 28
-- Thin margin between the two buttons and the backdrop frame drawn around
-- them (see OnLoad below) -- just enough that the frame reads as "these two
-- move together as one unit" without drawing attention to itself.
local FRAME_PADDING = 4

-- Guards against a duplicate OnLoad call, same reasoning and same pattern as
-- Elu_Tracker/main.lua's own top-level _onLoadStarted guard: this client's
-- addon loader occasionally re-fires load hooks without unloading first.
local _onLoadStarted = false

-- ===== Portals button =====
-- Sets the real "Only Use My Portal" client setting directly (not a
-- read-then-flip toggle -- see the OnLoad comment below for why a
-- read-and-flip approach caused real bugs). This is the only place in the
-- whole module that writes this setting, and it (like the rest of the
-- state machine above) is only ever reached while Tool Functions is
-- enabled -- see the guard in OnLoad below: with Tool Functions off (its
-- default), this module never touches the real setting at all.
local function setPortalRestriction(isSafe)
	local target = isSafe and 1 or 0
	local ok, err = pcall(function() api.Option:SetOnlyUseMyPortalSetting(target) end)
	if not ok then
		-- This used to fail completely silently (bare pcall, result
		-- discarded) -- if the setter ever throws (wrong signature, option
		-- system not ready yet, etc.) every single call site here would
		-- quietly do NOTHING and there would be no way to tell from in-game
		-- behavior alone. Logged now so a failure is provable instead of
		-- guessed at.
		Dbg("setPortalRestriction(" .. tostring(isSafe) .. "): SetOnlyUseMyPortalSetting(" .. tostring(target) .. ") THREW: " .. tostring(err))
		return
	end
	-- Read the real setting straight back so the debug log has hard proof
	-- the write actually stuck, instead of just hoping it did. If a future
	-- report says "the checkbox in Game Settings still doesn't match", this
	-- readBack line is what tells the difference between two very different
	-- problems: (a) readBack doesn't match target -> the setter call itself
	-- isn't taking, a real bug here; (b) readBack DOES match target but the
	-- on-screen checkbox still looks stale -> the native Options panel
	-- simply isn't re-reading the value live while it's already open (a
	-- client panel-refresh quirk, fixed by closing and reopening that
	-- panel) -- nothing this module can do about that from over here, since
	-- it never touches that panel's own widgets.
	local readOk, readBack = pcall(function() return api.Option:GetOnlyUseMyPortalSetting() end)
	Dbg("setPortalRestriction(" .. tostring(isSafe) .. "): wrote " .. tostring(target) .. ", readBack=" .. tostring(readOk and readBack or ("ERROR:" .. tostring(readBack))))
end

-- ===== Skin button: on/off toggle for real costumes vs. the client's
-- generic "Default Player Appearances" (Options > Game Settings >
-- Functionality). =====
-- true when the client is currently showing everyone's DEFAULT/generic
-- appearance instead of their real gear/costume.
local function isDefaultAppearanceOn()
	-- pcall'd defensively: GetCustomCloneModeSetting isn't part of the
	-- addon API's documented surface, only confirmed by how other addons
	-- (e.g. DefaultAppearances) use it. If a future client update ever
	-- renames/removes it, this fails safe (treated as "off") instead of
	-- erroring out the whole addon.
	local ok, value = pcall(function() return api.Option:GetCustomCloneModeSetting() end)
	if not ok or value == nil then return false end
	return value ~= 0
end

-- Both *ButtonVisual functions below re-assert :SetExtent() every time they
-- run, not just at creation. ApplyButtonSkin (portalsBtn's "safe" branch)
-- resets the widget back toward the skin's own natural size, so without
-- this, portalsBtn and skinBtn could silently drift to different heights
-- over time even though both start out at the same buttonH.
--
-- Both also get called again from OnEnter/OnLeave (wired in OnLoad below),
-- not just on click: ApplyTextColor sets a one-shot style override that the
-- engine's own hover-highlight rendering doesn't reliably restore on mouse
-- leave -- forcing our own color back on every hover transition, not only
-- on state changes, makes that path self-correcting.
local function updateSkinButtonVisual()
	if skinBtn == nil then return end
	if isDefaultAppearanceOn() then
		-- Default/generic appearance is active -> real skins are NOT showing.
		-- Colored (not neutral) on purpose, same as Portals' "UNSAFE" state:
		-- this is the one worth a glance, since it means everyone's gear is
		-- hidden right now.
		skinBtn:SetText("Skin: OFF")
		pcall(function() ApplyTextColor(skinBtn, {1, 0.35, 0.35, 1}) end)
	else
		-- Real skins/costumes are showing normally -- the everyday state, so
		-- it gets the button's own neutral default look instead of a
		-- constant tint, mirroring exactly how Portals stays neutral in its
		-- own normal ("Portals") state and only colors up for the state
		-- actually worth noticing.
		skinBtn:SetText("Skin: ON")
		pcall(function() ApplyButtonSkin(skinBtn, BUTTON_BASIC.DEFAULT) end)
	end
	skinBtn:SetExtent(skinW, buttonH)
end

local function updatePortalsButtonVisual()
	if portalsBtn == nil then return end
	if portalMode == PORTAL_SAFE then
		portalsBtn:SetText("Portals")
		-- Re-apply the button's own default skin instead of forcing a raw
		-- color -- this restores the exact look it had before it was ever
		-- recolored, instead of a slightly-off forced white.
		pcall(function() ApplyButtonSkin(portalsBtn, BUTTON_BASIC.DEFAULT) end)
	elseif portalMode == PORTAL_UNSAFE_TEMP then
		portalsBtn:SetText("UNSAFE")
		pcall(function() ApplyTextColor(portalsBtn, {1, 0.3, 0.3, 1}) end)
	else -- PORTAL_UNSAFE_OFF
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

-- ===== Shared position + visibility persistence =====
local function saveSettings()
	pcall(function() api.File:Write(SETTINGS_FILE, settings) end)
end

-- BUG FOUND (this is why the button reset to the default spot after every
-- reload): this used to be 500, sized around the OLD BOTTOMLEFT-anchor
-- AddAnchor/GetOffset mismatch, where a corrupted saved value came back
-- roughly doubled. That anchor type isn't used anywhere in this file
-- anymore (TOPLEFT only, see OnLoad below), so that specific corruption
-- can't happen here -- but 500 is well within normal screen coordinates: a
-- position anywhere in the bottom half of a 1080p screen (y > 540) or past
-- roughly the left third of a 1920-wide screen (x > 500-600) was being
-- silently rejected on every load and replaced with the default, and then
-- OnUnload's own unconditional saveSettings() immediately overwrote the
-- good dragged position on disk with that same default -- so the very act
-- of testing a drag-then-reload was permanently clobbering the saved spot.
-- Raised to a value no real monitor resolution will ever legitimately hit,
-- while still catching truly corrupted data (NaN, or a value in the tens of
-- thousands) if some other bug ever produces one.
local SANE_COORD_LIMIT = 10000

local function loadSettings()
	local ok, data = pcall(function() return api.File:Read(SETTINGS_FILE) end)
	if ok and type(data) == "table" then
		Dbg("loadSettings: raw file contents x=" .. tostring(data.x) .. " y=" .. tostring(data.y) .. " visible=" .. tostring(data.visible))
		if type(data.x) == "number" and math.abs(data.x) <= SANE_COORD_LIMIT then
			settings.x = data.x
		elseif data.x ~= nil then
			Dbg("loadSettings: ignoring out-of-range saved x=" .. tostring(data.x) .. ", keeping default " .. tostring(DEFAULT_X))
		end
		if type(data.y) == "number" and math.abs(data.y) <= SANE_COORD_LIMIT then
			settings.y = data.y
		elseif data.y ~= nil then
			Dbg("loadSettings: ignoring out-of-range saved y=" .. tostring(data.y) .. ", keeping default " .. tostring(DEFAULT_Y))
		end
		-- Deliberately NOT "settings.visible = data.visible or false" -- the
		-- explicit nil-check is what guarantees a file saved before this
		-- field existed comes up hidden, per spec, rather than accidentally
		-- true.
		if data.visible ~= nil then settings.visible = data.visible end
	end
end

local function savePosition()
	if containerWindow == nil then return end
	local x, y = containerWindow:GetOffset()
	Dbg("savePosition: GetOffset() after drag = x=" .. tostring(x) .. " y=" .. tostring(y))
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

-- Exposed as M.OnUpdate below and driven by Elu_Tracker/main.lua's own
-- top-level OnUpdate(dt), NOT by calling api.On("UPDATE", ...) directly in
-- here (api.On would replace whatever UPDATE handler main.lua already
-- registered -- see main.lua's own OnChatMessage comment for the same
-- class of bug with CHAT_MESSAGE). This only ever does anything in
-- PORTAL_UNSAFE_TEMP -- the original 10s-then-auto-safe behavior -- and is
-- a no-op in PORTAL_SAFE and PORTAL_UNSAFE_OFF (the persistent-unsafe state
-- has no timer by design: it only leaves on a click, see OnClick below).
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
	if containerWindow == nil then
		Dbg("SetVisible(" .. tostring(v) .. ") called but containerWindow is nil")
		return
	end
	local shouldShow = v and true or false

	-- BUG FOUND: this function used to only Show/Hide the window -- it never
	-- touched portalMode or the real setting at all. That meant turning
	-- Tool Functions OFF while the Portals button was sitting in
	-- PORTAL_UNSAFE_TEMP or PORTAL_UNSAFE_OFF hid the only control for that
	-- setting and left the player unsafe indefinitely, with no way to fix
	-- it short of turning Tool Functions back on and clicking Portals
	-- again. Fixed by forcing safe here, right before hiding -- but ONLY
	-- when unsafeCausedByAddon is true, i.e. only when THIS module is what
	-- made it unsafe in the first place. If portalMode is unsafe purely
	-- because OnLoad mirrored an already-unsafe real setting the player set
	-- on their own (Tool Functions was off at load time, see OnLoad's
	-- "else" branch above), unsafeCausedByAddon is false and this leaves
	-- that setting alone, exactly as it should.
	if not shouldShow and portalMode ~= PORTAL_SAFE and unsafeCausedByAddon then
		Dbg("SetVisible(false): portalMode was " .. tostring(portalMode) .. " (addon-caused), forcing back to safe before hiding")
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
		-- Re-assert both buttons' current state the moment they become
		-- visible again, in case anything about the underlying settings
		-- changed while this window was hidden.
		updatePortalsButtonVisual()
		updateSkinButtonVisual()
	end
	settings.visible = shouldShow
	saveSettings()
	Dbg("SetVisible(" .. tostring(v) .. ") -> Show(" .. tostring(shouldShow) .. ") done; IsVisible() after=" .. tostring(containerWindow:IsVisible()))
end

local function OnLoad()
	Dbg("OnLoad called (containerWindow=" .. tostring(containerWindow) .. " _onLoadStarted=" .. tostring(_onLoadStarted) .. ")")
	if containerWindow or _onLoadStarted then
		Dbg("OnLoad aborted early (duplicate call guard)")
		return
	end
	_onLoadStarted = true

	loadSettings()
	Dbg("settings after loadSettings(): x=" .. tostring(settings.x) .. " y=" .. tostring(settings.y) .. " visible=" .. tostring(settings.visible))

	-- BUG FOUND (this is almost certainly why players saw portals go unsafe
	-- on an update even with Tool Functions off, its default): this safety
	-- net used to run unconditionally on every load, AND it read the real
	-- setting once into ogValue but then called toggleUnsafePortalsOption(),
	-- which re-reads the setting a SECOND time and just flips whatever it
	-- finds. If that second read landed on a different value than the
	-- first -- this client's option system isn't always finished
	-- initializing this early in OnLoad, the same class of load-order quirk
	-- documented elsewhere in this addon (GetScreenWidth/Height vs
	-- GetParent():GetExtent(), the combo box OnSelect-never-fires bug,
	-- etc.) -- an already-safe setting (1) could get toggled straight to
	-- UNSAFE (0) with zero clicks, purely from loading/updating the addon.
	--
	-- Fixed two ways: (1) this whole block now only runs when Tool
	-- Functions is enabled (settings.visible, loaded just above) -- with it
	-- off, the real setting is never touched, matching what it should
	-- always have done; (2) when it IS enabled and needs to force safe, it
	-- calls setPortalRestriction() directly with the ONE value already read
	-- into ogValue, instead of a read-then-flip helper that re-reads and
	-- decides on its own.
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
		-- Tool Functions is off: don't touch the real setting at all --
		-- just mirror whatever it currently is, so the button (built below,
		-- but hidden) already shows the right state if the player enables
		-- Tool Functions later without a reload in between. There's no
		-- timer running to explain an unsafe value found here, so it maps
		-- to the persistent PORTAL_UNSAFE_OFF state rather than the
		-- temporary one.
		portalMode = (ogValue == 0) and PORTAL_UNSAFE_OFF or PORTAL_SAFE
		-- unsafeCausedByAddon stays false here on purpose (see its own
		-- comment near the top of the file): this is purely mirroring a
		-- real setting the player configured on their own -- this module
		-- hasn't caused anything -- so SetVisible(false) must never later
		-- "clean up" and overwrite it.
	end

	containerWindow = api.Interface:CreateEmptyWindow("eluFunctionsToolsWindow", "UIParent")
	containerWindow:SetExtent(portalsW + buttonGap + skinW + FRAME_PADDING * 2, buttonH + FRAME_PADDING * 2)
	containerWindow:AddAnchor("TOPLEFT", "UIParent", settings.x, settings.y)
	containerWindow:EnableDrag(true)
	function containerWindow:OnDragStart() startMovingButtons() end
	containerWindow:SetHandler("OnDragStart", containerWindow.OnDragStart)
	function containerWindow:OnDragStop() stopMovingButtons() end
	containerWindow:SetHandler("OnDragStop", containerWindow.OnDragStop)

	-- Small, very transparent black backdrop spanning both buttons plus a
	-- thin margin -- reads as "these two buttons are one movable unit"
	-- without drawing attention to itself.
	local frameBg = containerWindow:CreateColorDrawable(0, 0, 0, 0.35, "background")
	frameBg:AddAnchor("TOPLEFT", containerWindow, 0, 0)
	frameBg:AddAnchor("BOTTOMRIGHT", containerWindow, 0, 0)

	portalsBtn = containerWindow:CreateChildWidget("button", "eluPortalsBtn", 0, true)
	ApplyButtonSkin(portalsBtn, BUTTON_BASIC.DEFAULT)
	portalsBtn:SetText("Portals")
	portalsBtn:SetExtent(portalsW, buttonH)
	portalsBtn:AddAnchor("TOPLEFT", containerWindow, FRAME_PADDING, FRAME_PADDING)
	-- Buttons sit on top of the container and catch clicks first, so drag
	-- has to be wired on each button too (not just the container) or
	-- Shift+drag would only work on the sliver of container not covered by
	-- a button.
	portalsBtn:EnableDrag(true)
	function portalsBtn:OnClick()
		if api.Input:IsShiftKeyDown() then return end
		-- Three-way cycle -- see the PORTAL_* state comment near the top of
		-- this file. Portals(safe) -> click -> UNSAFE(10s timer) -> click
		-- again (before it fires) -> OFF(persistent, no timer) -> click ->
		-- back to Portals(safe). Left alone, UNSAFE reverts to Portals on
		-- its own after 10s exactly like the button always did (see
		-- OnUpdate above) -- clicking again while UNSAFE is what's new: it
		-- cancels that timer and leaves the restriction OFF indefinitely
		-- instead of auto-reverting.
		if portalMode == PORTAL_SAFE then
			portalMode = PORTAL_UNSAFE_TEMP
			portalClockTimer = 0
			unsafeCausedByAddon = true
			setPortalRestriction(false)
			api.Log:Info("[Elu Functions Tools] You can use other players' portals for 10 seconds.")
		elseif portalMode == PORTAL_UNSAFE_TEMP then
			portalMode = PORTAL_UNSAFE_OFF
			-- unsafeCausedByAddon stays true -- still the same addon-caused
			-- unsafe state, just with the auto-revert timer cancelled.
			api.Log:Info("[Elu Functions Tools] Portal restriction left OFF -- click Portals again to turn it back on.")
		else -- PORTAL_UNSAFE_OFF
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
	-- Re-assert the correct color/size on every hover transition, not just
	-- on click -- see the comment above updatePortalsButtonVisual().
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
	Dbg("OnLoad Show(" .. tostring(settings.visible == true) .. ") done; IsVisible() now=" .. tostring(containerWindow:IsVisible()))
end

local function OnUnload()
	Dbg("OnUnload called")
	_onLoadStarted = false

	-- Always persist here, unconditionally, even though SetVisible already
	-- tries to save too -- guarantees the toggle state survives a
	-- reload/relog even if some earlier save attempt silently failed.
	saveSettings()

	if containerWindow ~= nil then
		containerWindow:Show(false)
		-- LEAK FOUND during a full audit: every other window-creating module
		-- in this addon (main.lua's eluDisplayWindow/tripOverlay/eluBtn,
		-- stopwatch.lua's swOverlay, crash_alert.lua, zeal_alert.lua,
		-- spot_tracker.lua, etc. -- confirmed by grepping the whole addon
		-- for api.Interface:Free) calls Free() on its top-level window in
		-- OnUnload before dropping the Lua reference. This file never did --
		-- Show(false) plus `containerWindow = nil` only drops the LOCAL
		-- reference; it doesn't release the underlying widget. Since the
		-- auto-rebuild-once-after-3s in Elu_Tracker/main.lua's own OnLoad
		-- runs OnUnload+OnLoad on every single session (not just on a manual
		-- reload), this leaked one containerWindow plus its 2 buttons and 1
		-- background drawable EVERY session, guaranteed, on top of leaking
		-- again on every manual /reloadui. Matches the same "window count
		-- climbing" failure class main.lua's own duplicate-OnLoad comment
		-- already documents elsewhere in this addon.
		pcall(function() api.Interface:Free(containerWindow) end)
		containerWindow = nil
		portalsBtn = nil
		skinBtn = nil
	end
end

M.OnLoad = OnLoad
M.OnUnload = OnUnload
M.OnUpdate = OnUpdate
M.IsVisible = IsVisible
M.SetVisible = SetVisible

return M
