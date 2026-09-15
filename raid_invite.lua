local DEBUG = true
local function DebugLog(msg)

end

local settingsManager = require('Elu_Tracker/settings_manager')
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local api = require("api")

local raid_invite = {}

-- Same fix, same root cause, as guild_check.lua's and range_meter.lua's
-- stepper buttons: BUTTON_BASIC.DEFAULT's native skin has a fixed minimum
-- render size well beyond a 30x25 box, so these small "<"/">" pagination
-- buttons render visually oversized regardless of :SetExtent(). Not caused
-- by any addon edit -- it's how the client has always rendered
-- BUTTON_BASIC.DEFAULT at small sizes. Swapped in the addon's own smaller
-- nine-slice skin (copied verbatim from stopwatch.lua's proven-working
-- BSCBTN, same texture/coords) instead, only for these pagination arrows --
-- every other button in this file keeps BUTTON_BASIC.DEFAULT unchanged
-- since it isn't small enough to trigger this.
local RAID_SMALL_BTN_SKIN = {
    path = "ui/common/default.dds",
    fontColor = {
        normal = { 0.407843, 0.266667, 0.0705882, 1 },
        pushed = { 0.407843, 0.266667, 0.0705882, 1 },
        highlight = { 0.603922, 0.376471, 0.0627451, 1 },
        disabled = { 0.360784, 0.360784, 0.360784, 1 },
    },
    coords = {
        normal = { 727, 247, 60, 25 },
        disable = { 788, 273, 60, 25 },
        over = { 727, 273, 60, 25 },
        click = { 788, 247, 60, 25 },
    },
    fontInset = { top = 0, right = 11, left = 11, bottom = 0 },
    width = 30,
    height = 24,
    autoResize = true,
    drawableType = "ninePart",
    coordsKey = "btn",
}

local RAID_TINY_BTN_SKIN = {}
for k, v in pairs(RAID_SMALL_BTN_SKIN) do RAID_TINY_BTN_SKIN[k] = v end
RAID_TINY_BTN_SKIN.fontInset = { top = 0, right = 0, left = 0, bottom = 0 }
RAID_TINY_BTN_SKIN.width = 20
RAID_TINY_BTN_SKIN.height = 20

-- State
local state = {
    keyword = "",
    inviteMode = 0, -- 0: OFF, 1: ON, 2: WHITELIST
    giveleadMode = false,
    floatingIconPos = {0, 100},
    showFloatingIcon = false,
    floatingIconScale = 100,
    floatingIconAlpha = 100,
    whitelist = {},
    blacklist = {},
    canvas_width = 0,
    isSidePanelOpen = false,
    giveleadWhitelistOnly = false,
    doNotDisableAutoInvite = false,
    whitelistBypassPrivate = true,
    -- 2026-09-15: which private channels the master whitelistBypassPrivate
    -- checkbox above actually applies to (gear icon next to it, see
    -- BuildSidePanel). All 3 default ON so behavior is unchanged from
    -- before this existed -- whitelistBypassPrivate alone used to bypass
    -- all three unconditionally.
    whitelistBypassGuild = true,
    whitelistBypassFamily = true,
    whitelistBypassWhisper = true,
        clearedKeywordV2 = false,
    enhancedIsActive = false,
    enhancedKeyword = "",
    eluFilterMode = 2,
    enhancedFilterMode = 2, fastBlacklist = {},
    qaiCanvasPos = nil
}

local widgets = {}

-- AddTooltip() (below) creates each tooltip as its own top-level widget
-- parented to "UIParent" (not to the button it's anchored under), so
-- freeing that button's/panel's window does NOT free these along with it.
-- Tracked here so OnUnload can free them explicitly instead of leaking a
-- handful of orphaned UIParent-level widgets on every addon reload.
local tooltipWidgets = {}

local MSG_PREFIX = "[Elu Auto Invite] "

local function LogInfo(msg) api.Log:Info(MSG_PREFIX .. msg) end
local function LogErr(msg) api.Log:Err(MSG_PREFIX .. msg) end

-- Anti-double-invite cooldown. Both invite paths below (Quick Auto Invite
-- and normal Elu Auto Invite) only ever checked "is this person already a
-- raid MEMBER" before calling InviteToTeam -- neither checked "does this
-- person already have one of OUR invites pending". If the same trigger
-- chat line ever reaches OnChatMessage more than once (a duplicate/second
-- delivery of the same message -- e.g. from a chat relay/broadcast quirk),
-- both passes see "not a member yet" and both call InviteToTeam, and the
-- second one fails with the game's own "Can't invite a player considering
-- other invitations" -- which is exactly the symptom reported. This is a
-- simple, root-cause-agnostic guard: remember who we invited and skip
-- re-inviting the same name again within a short window, regardless of
-- why the trigger fired twice.
local INVITE_COOLDOWN_MS = 8000
local recentInvites = {}

local function RecentlyInvited(name)
    local key = string.lower(name or "")
    if key == "" then return false end
    local last = recentInvites[key]
    if not last then return false end
    return (api.Time:GetUiMsec() - last) < INVITE_COOLDOWN_MS
end

local function MarkInvited(name)
    local key = string.lower(name or "")
    if key == "" then return end
    local now = api.Time:GetUiMsec()
    recentInvites[key] = now

    -- recentInvites otherwise only ever grows: entries are never removed,
    -- just left behind once they age out of the cooldown window, so a long
    -- play session (or several, since this module-level table also
    -- survives an OnUnload+OnLoad reload cycle) inviting many different
    -- names over time would slowly accumulate one stale entry per unique
    -- name forever. Piggyback the prune on every new invite (cheap: this
    -- only runs on an actual invite, not every chat message) and clear out
    -- anything well past the cooldown -- a wide 10x margin so this can
    -- never race RecentlyInvited's own check above.
    for k, t in pairs(recentInvites) do
        if now - t > INVITE_COOLDOWN_MS * 10 then
            recentInvites[k] = nil
        end
    end
end

-- Forward-declared so LoadSettings (below) can call it: SaveSettings is
-- defined further down this file, and without this forward declaration
-- the `SaveSettings()` call inside LoadSettings' one-time keyword-migration
-- block resolved to a nonexistent GLOBAL (Lua only makes a `local`
-- visible to code written after its own declaration), which errored and
-- was silently swallowed by the pcall around it -- so that migration flag
-- flip never actually got written to disk on its own.
local SaveSettings

local function LoadSettings()
    local data = EluTrackerSettings.raidInvite
    if type(data) == "table" then
        if data.keyword ~= nil then state.keyword = data.keyword end
        if data.inviteMode ~= nil then 
            state.inviteMode = data.inviteMode 
        elseif data.isActive ~= nil then
            if data.isActive then
                state.inviteMode = 1
            else
                state.inviteMode = 0
            end
        end
        if data.giveleadMode ~= nil then state.giveleadMode = data.giveleadMode end
        if data.giveleadWhitelistOnly ~= nil then state.giveleadWhitelistOnly = data.giveleadWhitelistOnly end
        if data.doNotDisableAutoInvite ~= nil then state.doNotDisableAutoInvite = data.doNotDisableAutoInvite end
        if data.whitelistBypassPrivate ~= nil then state.whitelistBypassPrivate = data.whitelistBypassPrivate end
        if data.whitelistBypassGuild ~= nil then state.whitelistBypassGuild = data.whitelistBypassGuild end
        if data.whitelistBypassFamily ~= nil then state.whitelistBypassFamily = data.whitelistBypassFamily end
        if data.whitelistBypassWhisper ~= nil then state.whitelistBypassWhisper = data.whitelistBypassWhisper end
                if data.whitelist ~= nil then state.whitelist = data.whitelist end
        if data.blacklist ~= nil then state.blacklist = data.blacklist end
        if data.floatingIconPos ~= nil then state.floatingIconPos = data.floatingIconPos end
        if data.showFloatingIcon ~= nil then state.showFloatingIcon = data.showFloatingIcon end
        if data.floatingIconScale ~= nil then state.floatingIconScale = data.floatingIconScale end
        if data.floatingIconAlpha ~= nil then state.floatingIconAlpha = data.floatingIconAlpha end
        if data.clearedKeywordV2 ~= nil then state.clearedKeywordV2 = data.clearedKeywordV2 end
        if data.eluFilterMode ~= nil then state.eluFilterMode = data.eluFilterMode end
        if data.enhancedFilterMode ~= nil then state.enhancedFilterMode = data.enhancedFilterMode end; if data.fastBlacklist ~= nil then state.fastBlacklist = data.fastBlacklist end
        if data.qaiCanvasPos ~= nil then state.qaiCanvasPos = data.qaiCanvasPos end
    end
    
    local function SanitizeList(t)
        local clean = {}
        if type(t) == "table" then
            for i=1, #t do
                if type(t[i]) == "string" and t[i] ~= "" then table.insert(clean, t[i]) end
            end
        end
        return clean
    end
    state.whitelist = SanitizeList(state.whitelist)
    state.blacklist = SanitizeList(state.blacklist)
    state.fastBlacklist = SanitizeList(state.fastBlacklist)

    if not state.clearedKeywordV2 then
        state.keyword = ""
        state.clearedKeywordV2 = true
        local ok = pcall(function() SaveSettings() end)
    end
    
    
end

function SaveSettings()
    local data = {
        keyword = state.keyword,
        inviteMode = state.inviteMode,
        giveleadMode = state.giveleadMode,
        giveleadWhitelistOnly = state.giveleadWhitelistOnly,
        doNotDisableAutoInvite = state.doNotDisableAutoInvite,
        whitelistBypassPrivate = state.whitelistBypassPrivate,
        whitelistBypassGuild = state.whitelistBypassGuild,
        whitelistBypassFamily = state.whitelistBypassFamily,
        whitelistBypassWhisper = state.whitelistBypassWhisper,
                whitelist = state.whitelist,
        blacklist = state.blacklist,
        floatingIconPos = state.floatingIconPos,
        showFloatingIcon = state.showFloatingIcon,
        floatingIconScale = state.floatingIconScale,
        floatingIconAlpha = state.floatingIconAlpha,
        clearedKeywordV2 = state.clearedKeywordV2,
        eluFilterMode = state.eluFilterMode,
        enhancedFilterMode = state.enhancedFilterMode, fastBlacklist = state.fastBlacklist,
        qaiCanvasPos = state.qaiCanvasPos
    }
    EluTrackerSettings.raidInvite = data
    SaveEluTrackerSettings()
end

-- Chat Handling
local function IsBlacklisted(name)
    local lName = string.lower(name)
    for _, v in ipairs(state.blacklist) do
        if string.lower(v) == lName then return true end
    end
    return false
end

local function IsWhitelisted(name)
    local lName = string.lower(name)
    for _, v in ipairs(state.whitelist) do
        if string.lower(v) == lName then return true end
    end
    return false
end

local function FormatName(name)
    if type(name) ~= "string" then return "" end
    local text = tostring(name or ""):gsub("^%s*(.-)%s*$", "%1")
    if text == "" then return "" end
    return string.upper(string.sub(text, 1, 1)) .. string.lower(string.sub(text, 2))
end

local function OnChatMessage(channelId, speakerId, _, speakerName, message)
    if not speakerName or speakerName == "" then return end
    
    local myName = ""
    pcall(function() myName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player")) end)
    if speakerName == myName then return end
    
    local msgLower = string.lower(message)
    local keywordLower = string.lower(state.keyword)
    
    -- Check x givelead
    local giveMode = state.giveleadMode
    if type(giveMode) == "boolean" then
        if giveMode then giveMode = (state.giveleadWhitelistOnly and 3 or 2) else giveMode = 1 end
    end
    
    if giveMode > 1 and (channelId == 5 or channelId == -3 or channelId == 7) and (msgLower == "x givelead" or (keywordLower ~= "" and msgLower == keywordLower .. " givelead")) then
        local formattedSpeaker = FormatName(speakerName)
        if giveMode == 2 or (giveMode == 3 and IsWhitelisted(formattedSpeaker)) then
            LogInfo("Giving leadership to " .. formattedSpeaker)
            local raidNum = nil
            pcall(function()
                raidNum = api.Team:GetMemberIndexByName(formattedSpeaker)
            end)
            if raidNum ~= nil then
                pcall(function() api.Team:MakeTeamOwner("team" .. tostring(raidNum)) end)
            end
            return
        end
    end
    
    if state.enhancedIsActive and state.enhancedKeyword ~= "" then
        local match = false
        if state.enhancedFilterMode == 1 then
            match = (msgLower == string.lower(state.enhancedKeyword))
        else
            match = (string.find(msgLower, string.lower(state.enhancedKeyword), 1, true) ~= nil)
        end
        
        if match then
            if not IsBlacklisted(speakerName) then
                local existingMemberIndex = api.Team:GetMemberIndexByName(speakerName)
                if not existingMemberIndex and not RecentlyInvited(speakerName) then
                    LogInfo("Inviting " .. speakerName .. " (Enhanced)")
                    api.Team:InviteToTeam(speakerName, false)
                    MarkInvited(speakerName)
                end
            end
        end
    end
    
    if state.inviteMode == 0 then return end
    if keywordLower == "" then return end
    
    local eluMatch = false
    if state.eluFilterMode == 1 then
        eluMatch = (msgLower == keywordLower)
    else
        eluMatch = (string.find(msgLower, keywordLower, 1, true) ~= nil)
    end
    
    if not eluMatch then return end
    if IsBlacklisted(speakerName) then return end
    
    -- Channel check
    local isGuild = (channelId == 7 or channelId == CHAT_CHANNEL_GUILD)
    local isFamily = (channelId == 9 or channelId == CHAT_CHANNEL_FAMILY)
    local isWhisper = (channelId == -3 or channelId == CHAT_CHANNEL_WHISPER)
    local isPublic = not isGuild and not isFamily and not isWhisper
    
    local allowed = false
    if isWhisper then allowed = true end
    if isGuild then allowed = true end
    if isFamily then allowed = true end
    if isPublic then allowed = true end
    
    if not allowed then return end
    
    if state.inviteMode == 1 then
        -- 2026-09-15: bypass is now per-channel-type (gear next to "Disable
        -- whitelist in private chat" -- Family/Guild/Whisper each have their
        -- own on/off, all defaulting to ON so this behaves exactly like
        -- before for anyone who never opens the gear). The master
        -- whitelistBypassPrivate checkbox still gates all of it: when it's
        -- off, nobody bypasses the whitelist, same as always.
        local bypass = false
        if state.whitelistBypassPrivate and not isPublic then
            if isGuild then bypass = state.whitelistBypassGuild end
            if isFamily then bypass = state.whitelistBypassFamily end
            if isWhisper then bypass = state.whitelistBypassWhisper end
        end
        if not bypass and not IsWhitelisted(speakerName) then
            return -- Only whitelisted can be invited if whitelist mode is ON, unless bypassing this private channel
        end
    end
    
    -- Check if already in raid
    local existingMemberIndex = api.Team:GetMemberIndexByName(speakerName)
    if not existingMemberIndex and not RecentlyInvited(speakerName) then
        LogInfo("Inviting " .. speakerName)
        DebugLog("Inviting player: " .. tostring(speakerName))
        api.Team:InviteToTeam(speakerName, false)
        MarkInvited(speakerName)
    end
end

-- UI
local function UpdateFloatingIcon()
    if widgets.floatingIcon then
        widgets.floatingIcon:Show(state.showFloatingIcon)
        widgets.floatingIcon:SetExtent(55, 40)
        
        if widgets.fBgOn and widgets.fBgOff then
            widgets.fBgOn:SetExtent(55, 40)
            widgets.fBgOff:SetExtent(55, 40)
            widgets.fBgOn:SetVisible(state.inviteMode == 1)
            widgets.fBgOff:SetVisible(state.inviteMode == 0)
        end
        
        if widgets.fKeywordLbl then
            if state.inviteMode > 0 and state.keyword ~= "" then
                widgets.fKeywordLbl:SetText(state.keyword)
                widgets.fKeywordLbl:Show(true)
            else
                widgets.fKeywordLbl:Show(false)
            end
        end
    end
end

function raid_invite.StopEnhancedRecruiting()
    state.enhancedIsActive = false
    state.enhancedKeyword = ""
    
    if widgets.enhancedRecruitBtn then
        widgets.enhancedRecruitBtn:SetText("Start Recruiting")
    end
    if widgets.enhancedTextfield then
        widgets.enhancedTextfield:Enable(true)
    end
    if widgets.enhancedCanvas then
        widgets.enhancedCanvas:Show(false)
    end

    -- "Do NOT disable auto-invite automatically" (doNotDisableAutoInvite)
    -- already means, everywhere else in this file (OnLoad above, and the
    -- leave-raid check in OnUpdate below), "don't let anything automatic
    -- turn my normal Elu Auto Invite off". StartEnhancedRecruiting()
    -- unconditionally forces Elu Auto Invite OFF while Quick Auto Invite is
    -- running -- checkbox or not, always -- because both invite paths
    -- firing at once would double-invite the same person; that part is by
    -- design and unchanged. But once Quick Auto Invite STOPS (this
    -- function -- every stop path in the file funnels through here: the
    -- recruit button's own toggle-to-stop and the canvas's "Stop" button),
    -- that reason for Elu Auto Invite being off is gone. So with the
    -- checkbox on, turn Elu Auto Invite back ON right here, automatically
    -- -- otherwise the checkbox's own promise ("don't leave my auto-invite
    -- disabled because of something automatic") would quietly not hold for
    -- the one automatic disable this file does unconditionally.
    --
    -- Guarded on state.inviteMode == 0 so this is a no-op (and logs
    -- nothing) whenever Elu Auto Invite is already on -- in particular,
    -- ToggleActive() above already flips state.inviteMode to 1 BEFORE it
    -- calls this function (turning Elu Auto Invite on manually is what
    -- stops Quick Auto Invite in that path), so this block correctly does
    -- nothing there instead of redundantly re-triggering.
    --
    -- NOTE: intentionally hardcodes "Turn OFF" below instead of calling
    -- GetModeString() -- GetModeString is declared with `local function`
    -- further down this same file, AFTER this function, so it is not yet
    -- an in-scope local here and would resolve to a nonexistent global
    -- instead (the exact same class of forward-reference bug the
    -- SaveSettings comment near the top of this file already documents).
    -- "Turn OFF" is exactly what GetModeString() returns for inviteMode==1
    -- anyway, so this stays in sync with it by construction.
    if state.doNotDisableAutoInvite and state.inviteMode == 0 then
        state.inviteMode = 1
        SaveSettings()
        UpdateFloatingIcon()
        if widgets.toggleBtn then widgets.toggleBtn:SetText("Turn OFF") end
        if widgets.statusLbl then
            widgets.statusLbl:SetText("[ON]")
            ApplyTextColor(widgets.statusLbl, {0, 1, 0, 1})
        end
        LogInfo("Quick Auto Invite stopped -- Elu Auto Invite turned back ON automatically (\"Do NOT disable auto-invite automatically\" is checked).")
    end
end

local function GetModeString()
    if state.inviteMode == 1 then return "Turn OFF"
    else return "Turn ON" end
end

local function ToggleActive()
    if state.inviteMode == 0 then state.inviteMode = 1 else state.inviteMode = 0 end
    
    if state.inviteMode > 0 and state.enhancedIsActive then
        raid_invite.StopEnhancedRecruiting()
        
    end
    
    SaveSettings()
    UpdateFloatingIcon()
    
    if widgets.toggleBtn then
        widgets.toggleBtn:SetText(GetModeString())
    end
    
    if widgets.statusLbl then
        if state.inviteMode == 1 then
            widgets.statusLbl:SetText("[ON]")
            ApplyTextColor(widgets.statusLbl, {0, 1, 0, 1})
        else
            widgets.statusLbl:SetText("[OFF]")
            ApplyTextColor(widgets.statusLbl, {1, 0, 0, 1})
        end
    end
    
    if widgets.toggleSideBtn then
        widgets.toggleSideBtn:SetText("Elu Auto Invite")
    end
    
    LogInfo("Auto Invite Mode is now: " .. tostring(state.inviteMode))
end


local function AddCurrentRaidToWhitelist()
    local myName = ""
    pcall(function() myName = FormatName(api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))) end)

    local didAdd = false
    local seen = {}
    local function addName(rawName)
        if type(rawName) ~= "string" then return end
        local formatted = FormatName(rawName)
        if formatted == "" or formatted == myName then return end

        local key = string.lower(formatted)
        if seen[key] then return end
        seen[key] = true

        local found = false
        for _, v in ipairs(state.whitelist) do
            if string.lower(v) == key then found = true break end
        end
        if not found and #state.whitelist < 100 then
            table.insert(state.whitelist, formatted)
            didAdd = true
        end
    end

    -- 1. Try X2Team (Native Engine)
    pcall(function()
        if X2Team and X2Team.GetTeamMembers then
            local members = X2Team:GetTeamMembers()
            if type(members) == "table" then
                for _, m in pairs(members) do
                    if m.name then addName(m.name) end
                end
            end
        end
    end)

    -- 2. Try tokens party1-party5 and team1-team50
    local tokens = {}
    for i=1, 50 do table.insert(tokens, "team"..i) end
    for i=1, 5 do table.insert(tokens, "party"..i) end

    if api.Unit ~= nil then
        for _, token in ipairs(tokens) do
            if api.Unit.UnitInfo then
                local info = nil
                pcall(function() info = api.Unit:UnitInfo(token) end)
                if type(info) == "table" then addName(info.name or info.unitName or "") end
            end
            
            if api.Unit.GetUnitId then
                local unitId = nil
                pcall(function() unitId = api.Unit:GetUnitId(token) end)
                if unitId ~= nil then
                    if api.Unit.GetUnitInfoById then
                        local infoById = nil
                        pcall(function() infoById = api.Unit:GetUnitInfoById(unitId) end)
                        if type(infoById) == "table" then addName(infoById.name or infoById.unitName or "") end
                    end
                    if api.Unit.GetUnitNameById then
                        local nameById = nil
                        pcall(function() nameById = api.Unit:GetUnitNameById(unitId) end)
                        addName(nameById or "")
                    end
                end
            end

            if api.Unit.UnitName then
                local uName = nil
                pcall(function() uName = api.Unit:UnitName(token) end)
                addName(uName or "")
            end
        end
    end

    if didAdd then
        SaveSettings()
        if widgets.listWindow and widgets.listWindow:IsVisible() and widgets.listWindow.isWhite then
            widgets.listWindow.RefreshList()
        end
        if api.Log and api.Log.Info then api.Log:Info("[Elu Tracker] Raid members added to Whitelist!") end
    else
        if api.Log and api.Log.Info then api.Log:Info("[Elu Tracker] No new members to add.") end
    end
end

        local tooltipIdCounter = 0
    local function AddTooltip(widget, text)
        tooltipIdCounter = tooltipIdCounter + 1
        local tooltip = api.Interface:CreateWidget("emptywidget", "eluTooltip_" .. tostring(math.random(10000, 99999)) .. "_" .. tostring(tooltipIdCounter), "UIParent")
        table.insert(tooltipWidgets, tooltip)
        tooltip:SetExtent(280, 110)
        tooltip:AddAnchor("BOTTOM", widget, "TOP", 0, -5)
        tooltip:Show(false)
        
        local bg = tooltip:CreateNinePartDrawable("ui/common_new/default.dds", "background")
        bg:SetTextureInfo("tooltip")
        bg:AddAnchor("TOPLEFT", tooltip, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", tooltip, 0, 0)
        bg:SetColor(1, 1, 1, 0.95)
        
        local lbl = tooltip:CreateChildWidget("textbox", "lbl", 0, true)
        lbl:AddAnchor("TOPLEFT", tooltip, 10, 10)
        lbl:AddAnchor("BOTTOMRIGHT", tooltip, -10, -10)
        lbl.style:SetAlign(ALIGN.CENTER)
        lbl.style:SetFontSize(14)
        lbl:SetAutoWordwrap(true)
        lbl:SetText(text)
        ApplyTextColor(lbl, {1, 1, 1, 1}) -- White text for tooltip
        
        widget:SetHandler("OnEnter", function()
            tooltip:Show(true)
            tooltip:Raise()
        end)
        widget:SetHandler("OnLeave", function()
            tooltip:Show(false)
        end)
    end

local function BuildSidePanel(parent)
    local panel = parent:CreateChildWidget("emptywidget", "eluRaidSidePanel", 0, true)
    panel:SetExtent(300, 405)
    panel:AddAnchor("TOPLEFT", parent, "TOPRIGHT", 5, 0)
    panel:Show(false)
    widgets.sidePanel = panel
    
    local bg = panel:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.9)
    bg:AddAnchor("TOPLEFT", panel, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", panel, 0, 0)
    
    -- Checkboxes function
    local function CreateCheckbox(id, text, yOffset, stateKey, xOffset)
        local cb = panel:CreateChildWidget("checkbutton", id, 0, true)
        cb:SetExtent(18, 17)
        cb:AddAnchor("TOPLEFT", panel, xOffset or 20, yOffset)
        
        local bg1 = cb:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg1:SetExtent(18, 17)
        bg1:AddAnchor("CENTER", cb, 0, 0)
        bg1:SetCoords(0, 0, 18, 17)
        cb:SetNormalBackground(bg1)
        
        local bg2 = cb:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg2:SetExtent(18, 17)
        bg2:AddAnchor("CENTER", cb, 0, 0)
        bg2:SetCoords(18, 0, 18, 17)
        cb:SetCheckedBackground(bg2)
        
        local lbl = panel:CreateChildWidget("label", id.."Lbl", 0, true)
        lbl:SetAutoResize(true)
        lbl:SetHeight(20)
        lbl:SetText(text)
        lbl:AddAnchor("LEFT", cb, "RIGHT", 5, 0)
        lbl.style:SetAlign(ALIGN.CENTER)
        ApplyTextColor(lbl, {1,1,1,1})
        
        cb:SetChecked(state[stateKey], false)
        cb:SetHandler("OnCheckChanged", function()
            state[stateKey] = cb:GetChecked()
            SaveSettings()
            if id == "cbIcon" then UpdateFloatingIcon() end
            if id == "cbWhiteBypass" then
                -- The gear (Family/Guild/Whisper picker) only makes sense
                -- while the master checkbox is on -- hide it, and close the
                -- popup if it happened to be open, the moment it's turned off.
                if widgets.privateBypassGearBtn then
                    widgets.privateBypassGearBtn:Show(state.whitelistBypassPrivate)
                end
                if not state.whitelistBypassPrivate and widgets.privateBypassPopup then
                    widgets.privateBypassPopup:Show(false)
                    if widgets.privateBypassOverlay then widgets.privateBypassOverlay:Show(false) end
                end
            end

        end)

        return cb
    end
    
    widgets.cbIcon = CreateCheckbox("cbIcon", "Show Floating Icon", 15, "showFloatingIcon", 90)
    
    local title = panel:CreateChildWidget("label", "title", 0, true)
    title:SetText("Elu Auto Invite (WHITELIST ONLY)")
    title:SetExtent(240, 20)
    title:AddAnchor("TOP", panel, 0, 40)
    ApplyTextColor(title, {1, 0.8, 0.2, 1})
    
    local statusLbl = panel:CreateChildWidget("label", "statusLbl", 0, true)
    statusLbl:SetExtent(200, 20)
    statusLbl:AddAnchor("TOP", title, "BOTTOM", 0, 5)
    if state.inviteMode == 1 then
        statusLbl:SetText("[ON]")
        ApplyTextColor(statusLbl, {0, 1, 0, 1})
    else
        statusLbl:SetText("[OFF]")
        ApplyTextColor(statusLbl, {1, 0, 0, 1})
    end
    widgets.statusLbl = statusLbl
    
    widgets.toggleBtn = panel:CreateChildWidget("button", "toggleBtn", 0, true)
    widgets.toggleBtn:SetExtent(160, 32)
    widgets.toggleBtn:AddAnchor("TOP", statusLbl, "BOTTOM", 0, 5)
    widgets.toggleBtn:SetText(GetModeString())
    api.Interface:ApplyButtonSkin(widgets.toggleBtn, BUTTON_BASIC.DEFAULT)
    widgets.toggleBtn:SetHandler("OnClick", ToggleActive)
    
    local cbDoNotDisable = CreateCheckbox("cbDoNotDisable", "Do NOT disable auto-invite automatically", 135, "doNotDisableAutoInvite", 16)
    
    local q1 = W_ICON.CreateGuideIconWidget(panel)
    q1:AddAnchor("LEFT", panel.cbDoNotDisableLbl, "RIGHT", 5, 0)
    AddTooltip(q1, "If checked, Auto-Invite stays ON after\nleaving raids, reloading, or relogging.")
    
    local kwLabel = panel:CreateChildWidget("label", "kwLabel", 0, true)
    kwLabel:SetText("Keyword:")
    kwLabel:SetExtent(65, 20)
    kwLabel:AddAnchor("TOPLEFT", panel, 25, 175)
    ApplyTextColor(kwLabel, {1,1,1,1})
    kwLabel.style:SetAlign(ALIGN.LEFT)
    
    local kwInput = W_CTRL.CreateEdit("kwInput", panel)
    kwInput:SetExtent(100, 25)
    kwInput:SetMaxTextLength(100)
    kwInput:AddAnchor("LEFT", kwLabel, "RIGHT", 5, 0)
    kwInput:SetText(state.keyword)
    kwInput:SetHandler("OnTextChanged", function() 
        state.keyword = kwInput:GetText()
        SaveSettings()
        UpdateFloatingIcon()
    end)
    widgets.kwInput = kwInput
    
    
    
    local eluFilterCombo = api.Interface:CreateComboBox(panel)
    eluFilterCombo:SetExtent(75, 25)
    eluFilterCombo:AddAnchor("LEFT", kwInput, "RIGHT", 5, 0)
    eluFilterCombo.dropdownItem = {"Equals", "Contains"}
    eluFilterCombo:Select(state.eluFilterMode or 2)
    eluFilterCombo:Show(true)

    -- NOTE: this widget's selection callback is :SelectedProc(index), not
    -- SetHandler("OnSelect", ...) -- that event name never fires on this
    -- ComboBox type (confirmed against range_meter.lua's/loss_porn_ui.lua's
    -- working combo boxes, and against the saved settings file showing this
    -- value stuck at its default). Using the wrong handler meant a chosen
    -- Equals/Contains filter was never written to state, so it silently
    -- reverted to the default every reload/relog.
    function eluFilterCombo:SelectedProc(index)
        state.eluFilterMode = index
        SaveSettings()
    end
    widgets.eluFilterCombo = eluFilterCombo
    
    local giveleadLabel = panel:CreateChildWidget("label", "giveleadLabel", 0, true)
    giveleadLabel:SetText("'x givelead':")
    giveleadLabel:SetExtent(75, 20)
    giveleadLabel:AddAnchor("TOPLEFT", panel, 57, 210)
    ApplyTextColor(giveleadLabel, {1,1,1,1})
    giveleadLabel.style:SetAlign(ALIGN.LEFT)
    
    local giveleadCombo = api.Interface:CreateComboBox(panel)
    giveleadCombo:SetExtent(105, 25)
    giveleadCombo:AddAnchor("LEFT", giveleadLabel, "RIGHT", 5, 0)
    giveleadCombo.dropdownItem = {"Off", "On", "Whitelist Only"}
    
    local giveIdx = 1
    if state.giveleadMode == true then
        if state.giveleadWhitelistOnly then giveIdx = 3 else giveIdx = 2 end
    elseif type(state.giveleadMode) == "number" then
        giveIdx = state.giveleadMode
    end
    giveleadCombo:Select(giveIdx)
    giveleadCombo:Show(true)

    -- See the note above eluFilterCombo -- same bug: SetHandler("OnSelect",
    -- ...) never fires on this widget, so the chosen Off/On/Whitelist Only
    -- option was never actually saved (confirmed by the saved settings
    -- file still holding the boolean default `false`, not a picked index).
    function giveleadCombo:SelectedProc(index)
        state.giveleadMode = index
        SaveSettings()
    end
    widgets.giveleadCombo = giveleadCombo

    CreateCheckbox("cbWhiteBypass", "Disable whitelist in private chat", 250, "whitelistBypassPrivate", 36)

    local q2 = W_ICON.CreateGuideIconWidget(panel)
    q2:AddAnchor("LEFT", panel.cbWhiteBypassLbl, "RIGHT", 5, 0)
    AddTooltip(q2, "Guild, Family & Whisper\n\nIf checked, players typing the keyword in these chats will be invited instantly, even if they are NOT in your Whitelist.")

    -- Gear: pick WHICH of Guild/Family/Whisper actually bypass the
    -- whitelist (whitelistBypassGuild/Family/Whisper in state, all default
    -- ON). Only shown while the master checkbox above is checked -- see the
    -- "cbWhiteBypass" branch in CreateCheckbox's OnCheckChanged, which
    -- shows/hides this button and closes the popup below when the master
    -- gets unchecked.
    local function CreateBypassPopup()
        if widgets.privateBypassPopup then return widgets.privateBypassPopup end

        local overlay = api.Interface:CreateWidget("button", "eluBypassOverlay", "UIParent")
        overlay:Show(false)
        widgets.privateBypassOverlay = overlay

        local popup = api.Interface:CreateEmptyWindow("eluRaidPrivateBypassPopup", "UIParent")
        popup:SetExtent(190, 150)
        popup:Show(false)
        widgets.privateBypassPopup = popup

        local pBg = popup:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        pBg:SetTextureInfo("bg_quest")
        pBg:SetColor(0, 0, 0, 0.95)
        pBg:AddAnchor("TOPLEFT", popup, 0, 0)
        pBg:AddAnchor("BOTTOMRIGHT", popup, 0, 0)

        local pTitle = popup:CreateChildWidget("label", "pTitle", 0, true)
        pTitle:SetExtent(170, 20)
        pTitle:AddAnchor("TOP", popup, 0, 10)
        pTitle.style:SetAlign(ALIGN.CENTER)
        pTitle:SetText("Bypass whitelist in:")
        ApplyTextColor(pTitle, {1, 0.8, 0.2, 1})

        local pCloseBtn = popup:CreateChildWidget("button", "pCloseBtn", 0, true)
        pCloseBtn:SetExtent(16, 16)
        pCloseBtn:AddAnchor("TOPRIGHT", popup, -5, 5)
        pCloseBtn:SetText("X")
        pCloseBtn.style:SetAlign(ALIGN.CENTER)
        ApplyTextColor(pCloseBtn, FONT_COLOR.RED)
        pCloseBtn:SetHandler("OnClick", function() 
            popup:Show(false)
            if widgets.privateBypassOverlay then widgets.privateBypassOverlay:Show(false) end
        end)

        overlay:SetHandler("OnClick", function()
            popup:Show(false)
            overlay:Show(false)
        end)

        local function CreatePopupCheckbox(id, text, yOffset, stateKey)
            local cb = popup:CreateChildWidget("checkbutton", id, 0, true)
            cb:SetExtent(18, 17)
            cb:AddAnchor("TOPLEFT", popup, 20, yOffset)

            local bg1 = cb:CreateImageDrawable("ui/button/check_button.dds", "background")
            bg1:SetExtent(18, 17)
            bg1:AddAnchor("CENTER", cb, 0, 0)
            bg1:SetCoords(0, 0, 18, 17)
            cb:SetNormalBackground(bg1)

            local bg2 = cb:CreateImageDrawable("ui/button/check_button.dds", "background")
            bg2:SetExtent(18, 17)
            bg2:AddAnchor("CENTER", cb, 0, 0)
            bg2:SetCoords(18, 0, 18, 17)
            cb:SetCheckedBackground(bg2)

            local lbl = popup:CreateChildWidget("label", id .. "Lbl", 0, true)
            lbl:SetAutoResize(true)
            lbl:SetHeight(20)
            lbl:SetText(text)
            lbl:AddAnchor("LEFT", cb, "RIGHT", 5, 0)
            lbl.style:SetAlign(ALIGN.CENTER)
            ApplyTextColor(lbl, {1, 1, 1, 1})

            cb:SetChecked(state[stateKey], false)
            cb:SetHandler("OnCheckChanged", function()
                state[stateKey] = cb:GetChecked()
                SaveSettings()
            end)
        end

        CreatePopupCheckbox("cbBypassFamily", "Family", 45, "whitelistBypassFamily")
        CreatePopupCheckbox("cbBypassGuild", "Guild", 75, "whitelistBypassGuild")
        CreatePopupCheckbox("cbBypassWhisper", "Whispers", 105, "whitelistBypassWhisper")

        return popup
    end

    local gearBtn = panel:CreateChildWidget("button", "privateBypassGearBtn", 0, true)
    gearBtn:SetExtent(24, 16)
    gearBtn:AddAnchor("LEFT", q2, "RIGHT", 6, 0)
    
    local gearLbl = gearBtn:CreateChildWidget("label", "gearLbl", 0, true)
    gearLbl:SetExtent(24, 16)
    gearLbl:AddAnchor("CENTER", gearBtn, 0, 0)
    gearLbl:SetText("[ + ]")
    gearLbl.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(gearLbl, {1, 0.8, 0.2, 1})
    
    gearBtn:Show(state.whitelistBypassPrivate)
    widgets.privateBypassGearBtn = gearBtn

    gearBtn:SetHandler("OnClick", function()
        local popup = CreateBypassPopup()
        local overlay = widgets.privateBypassOverlay
        if not popup:IsVisible() then
            if overlay then
                overlay:SetExtent(api.Interface:GetScreenWidth(), api.Interface:GetScreenHeight())
                overlay:AddAnchor("TOPLEFT", "UIParent", 0, 0)
                overlay:Show(true)
                overlay:Raise()
            end
            popup:RemoveAllAnchors()
            popup:AddAnchor("TOPLEFT", gearBtn, "BOTTOMLEFT", -20, 5)
            popup:Show(true)
            popup:Raise()
        else
            popup:Show(false)
            if overlay then overlay:Show(false) end
        end
    end)

    AddTooltip(gearBtn, "Choose which private channels bypass the Whitelist.\nAll 3 are ON by default.")

    local blBtn = panel:CreateChildWidget("button", "blBtn", 0, true)
    blBtn:SetExtent(120, 30)
    blBtn:AddAnchor("TOPLEFT", panel, 20, 290)
    blBtn:SetText("Blacklist")
    api.Interface:ApplyButtonSkin(blBtn, BUTTON_BASIC.DEFAULT)
    
    local wlBtn = panel:CreateChildWidget("button", "wlBtn", 0, true)
    wlBtn:SetExtent(120, 30)
    wlBtn:AddAnchor("TOPRIGHT", panel, -20, 290)
    wlBtn:SetText("Whitelist")
    api.Interface:ApplyButtonSkin(wlBtn, BUTTON_BASIC.DEFAULT)
    
    local addRaidLbl = panel:CreateChildWidget("label", "addRaidLbl", 0, true)
    addRaidLbl:SetExtent(260, 20)
    addRaidLbl:AddAnchor("TOP", panel, 0, 340)
    addRaidLbl.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(addRaidLbl, FONT_COLOR.DEFAULT)
    addRaidLbl:SetText("Add current raid members to your whitelist")
    
    local addRaidBtn = panel:CreateChildWidget("button", "addRaidBtn", 0, true)
    addRaidBtn:SetExtent(120, 30)
    addRaidBtn:AddAnchor("TOP", addRaidLbl, "BOTTOM", 0, 5)
    addRaidBtn:SetText("Add Raid")
    api.Interface:ApplyButtonSkin(addRaidBtn, BUTTON_BASIC.DEFAULT)
    addRaidBtn:SetHandler("OnClick", AddCurrentRaidToWhitelist)

    
    
    -- Fast Auto Invite UI (below lists management)
    
    
    local function ToggleListWindow(listType)
        local wnd = widgets.listWindow
        if not wnd then
            wnd = api.Interface:CreateWindow("eluRList_" .. tostring(math.random(10000, 99999)), "Manage List", 0, 0)
            wnd:SetExtent(300, 500)
            wnd:AddAnchor("CENTER", "UIParent", 0, 0)

    if wnd.titleBar and wnd.titleBar.bg then
        wnd.titleBar.bg:SetColor(ConvertColor(40), ConvertColor(44), ConvertColor(52), 1.0)
    end
    if wnd.bg then
        wnd.bg:SetColor(ConvertColor(24), ConvertColor(26), ConvertColor(31), 0.95)
    end
                
    
            
            wnd.listType = listType; wnd.isWhite = (listType == 1)
            wnd.page = 1
            widgets.listWindow = wnd
            
            local instructions = wnd:CreateChildWidget("label", "instructions", 0, true)
            instructions:SetExtent(280, 20)
            instructions:AddAnchor("TOP", wnd, 0, 50)
            instructions.style:SetAlign(ALIGN.CENTER)
            ApplyTextColor(instructions, FONT_COLOR.MIDDLE_TITLE)
            wnd.instructions = instructions
            
            local player_label = wnd:CreateChildWidget("label", "player_label", 0, true)
            player_label:SetText("Player Name:")
            player_label:SetExtent(100, 20)
            player_label:AddAnchor("TOP", wnd, 0, 80)
            player_label.style:SetAlign(ALIGN.CENTER)
            ApplyTextColor(player_label, FONT_COLOR.MIDDLE_TITLE)
            wnd.player_label = player_label
            
            local input = W_CTRL.CreateEdit("listInput", wnd)
            input:SetExtent(160, 30)
            input:AddAnchor("TOP", wnd, -45, 110)
            wnd.input = input
            
            local addBtn = wnd:CreateChildWidget("button", "addBtn", 0, true)
            addBtn:SetExtent(80, 30)
            addBtn:AddAnchor("LEFT", input, "RIGHT", 10, 0)
            addBtn:SetText("Add Player")
            api.Interface:ApplyButtonSkin(addBtn, BUTTON_BASIC.DEFAULT)
            
            local list_label = wnd:CreateChildWidget("label", "list_label", 0, true)
            list_label:SetExtent(300, 20)
            list_label:AddAnchor("TOP", wnd, 0, 160)
            list_label.style:SetAlign(ALIGN.CENTER)
            ApplyTextColor(list_label, FONT_COLOR.MIDDLE_TITLE)
            wnd.list_label = list_label
            
            wnd.rowWidgets = {}
            for i = 1, 5 do
                local row = wnd:CreateChildWidget("emptywidget", "row"..i, 0, true)
                row:SetExtent(280, 25)
                row:AddAnchor("TOP", wnd, 0, 190 + (i-1)*35)
                
                local lbl = row:CreateChildWidget("label", "lbl", 0, true)
                lbl:SetExtent(180, 25)
                lbl:AddAnchor("LEFT", row, 0, 0)
                lbl.style:SetAlign(ALIGN.CENTER)
                row.lbl = lbl
                
                local removeBtn = row:CreateChildWidget("button", "removeBtn", 0, true)
                removeBtn:SetExtent(70, 25)
                removeBtn:AddAnchor("RIGHT", row, 0, 0)
                removeBtn:SetText("Remove")
                api.Interface:ApplyButtonSkin(removeBtn, BUTTON_BASIC.DEFAULT)
                
                removeBtn:SetHandler("OnClick", function()
                    local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                    if row.dataIndex and t[row.dataIndex] then
                        table.remove(t, row.dataIndex)
                        SaveSettings()
                        wnd.RefreshList()
                    end
                end)
                
                wnd.rowWidgets[i] = row
            end
            
            local pageLbl = wnd:CreateChildWidget("label", "pageLbl", 0, true)
            pageLbl:SetExtent(80, 25)
            pageLbl:AddAnchor("TOP", wnd, 0, 375)
            pageLbl.style:SetAlign(ALIGN.CENTER)
            ApplyTextColor(pageLbl, FONT_COLOR.MIDDLE_TITLE)
            wnd.pageLbl = pageLbl

            local prevBtn = wnd:CreateChildWidget("button", "prevBtn", 0, true)
            prevBtn:AddAnchor("RIGHT", pageLbl, "LEFT", -10, 0)
            prevBtn:SetText("<")
            api.Interface:ApplyButtonSkin(prevBtn, RAID_SMALL_BTN_SKIN)
            prevBtn:SetHandler("OnClick", function()
                if wnd.page > 1 then
                    wnd.page = wnd.page - 1
                    wnd.RefreshList()
                end
            end)

            local nextBtn = wnd:CreateChildWidget("button", "nextBtn", 0, true)
            nextBtn:AddAnchor("LEFT", pageLbl, "RIGHT", 10, 0)
            nextBtn:SetText(">")
            api.Interface:ApplyButtonSkin(nextBtn, RAID_SMALL_BTN_SKIN)
            nextBtn:SetHandler("OnClick", function()
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                local maxPage = math.ceil(#t / 5)
                if wnd.page < maxPage then
                    wnd.page = wnd.page + 1
                    wnd.RefreshList()
                end
            end)
            
            local exportBtn = wnd:CreateChildWidget("button", "exportBtn", 0, true)
            exportBtn:SetExtent(80, 30)
            exportBtn:SetText("Export")
            api.Interface:ApplyButtonSkin(exportBtn, BUTTON_BASIC.DEFAULT)
            AddTooltip(exportBtn, "Share or backup your list.\n\nYou can copy the text code, or export directly to a native '.lua' file in your ArcheAge Addon folder.")
            
            local importBtn = wnd:CreateChildWidget("button", "importBtn", 0, true)
            importBtn:SetExtent(80, 30)
            importBtn:SetText("Import")
            api.Interface:ApplyButtonSkin(importBtn, BUTTON_BASIC.DEFAULT)
            AddTooltip(importBtn, "Load a list from a friend or backup.\n\nYou can paste a text code, or import directly from a '.lua' file in your ArcheAge Addon folder.\n(Importing only ADDS names, it never deletes yours!)")
            
            local inviteAllBtn = wnd:CreateChildWidget("button", "inviteAllBtn", 0, true)
            inviteAllBtn:SetExtent(120, 30)
            inviteAllBtn:SetText("Invite All")
            api.Interface:ApplyButtonSkin(inviteAllBtn, BUTTON_BASIC.DEFAULT)
            AddTooltip(inviteAllBtn, "Automatically invite everyone in your Whitelist to the raid.")
            inviteAllBtn:SetHandler("OnClick", function()
                if not state.whitelist then return end
                for _, name in ipairs(state.whitelist) do
                    if not RecentlyInvited(name) then
                        api.Team:InviteToTeam(name, false)
                        MarkInvited(name)
                    end
                end
                api.Log:Info("[Elu Auto Invite] Invited everyone from your whitelist!")
            end)
            
            local exportWnd = nil
            local exportWidgets = nil

            local function ShowExportWindow()
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                local prefix = wnd.isWhite and "WL:" or "BL:"

                local clean_t = {}
                for i = 1, #t do
                    if t[i] ~= nil and tostring(t[i]) ~= "" then
                        table.insert(clean_t, tostring(t[i]))
                    end
                end

                local namesPerPage = 30
                local maxPage = math.max(1, math.ceil(#clean_t / namesPerPage))

                -- Build the window and its widgets once; reuse them on every
                -- subsequent Export click instead of leaking a new top-level
                -- window each time.
                if not exportWnd then
                    exportWnd = api.Interface:CreateWindow("eluRExportWnd", "Export Code", 0, 0)
                    exportWnd:SetExtent(300, 400)
                    exportWnd:AddAnchor("CENTER", "UIParent", 0, 0)

                    local inst = exportWnd:CreateChildWidget("textbox", "inst", 0, true)
                    inst:SetExtent(260, 40)
                    inst:AddAnchor("TOP", exportWnd, 0, 50)
                    inst.style:SetAlign(ALIGN.CENTER)
                    ApplyTextColor(inst, FONT_COLOR.DEFAULT)
                    inst:SetText("To share: Copy (Ctrl+A -> Ctrl+C) and send to a friend.\nUse < > to copy other pages if the list is large.")

                    local input = W_CTRL.CreateMultiLineEdit("exportInput", exportWnd)
                    input:SetExtent(260, 200)
                    input:AddAnchor("TOP", inst, "BOTTOM", 0, 10)
                    input:SetMaxTextLength(65535)

                    local pageLbl = exportWnd:CreateChildWidget("label", "pageLbl", 0, true)
                    pageLbl:SetExtent(100, 25)
                    pageLbl:AddAnchor("TOP", input, "BOTTOM", 0, 10)
                    pageLbl.style:SetAlign(ALIGN.CENTER)
                    ApplyTextColor(pageLbl, FONT_COLOR.DEFAULT)

                    local prevBtn = exportWnd:CreateChildWidget("button", "prevBtn", 0, true)
                    prevBtn:AddAnchor("RIGHT", pageLbl, "LEFT", -10, 0)
                    prevBtn:SetText("<")
                    api.Interface:ApplyButtonSkin(prevBtn, RAID_SMALL_BTN_SKIN)

                    local nextBtn = exportWnd:CreateChildWidget("button", "nextBtn", 0, true)
                    nextBtn:AddAnchor("LEFT", pageLbl, "RIGHT", 10, 0)
                    nextBtn:SetText(">")
                    api.Interface:ApplyButtonSkin(nextBtn, RAID_SMALL_BTN_SKIN)

                    local closeBtn = exportWnd:CreateChildWidget("button", "closeBtn", 0, true)
                    closeBtn:SetExtent(80, 30)
                    closeBtn:AddAnchor("BOTTOMLEFT", exportWnd, "BOTTOM", 5, -20)
                    closeBtn:SetText("Close")
                    api.Interface:ApplyButtonSkin(closeBtn, BUTTON_BASIC.DEFAULT)
                    closeBtn:SetHandler("OnClick", function() exportWnd:Show(false) end)

                    local exportFileBtn = exportWnd:CreateChildWidget("button", "exportFileBtn", 0, true)
                    exportFileBtn:SetExtent(120, 30)
                    exportFileBtn:AddAnchor("BOTTOMRIGHT", exportWnd, "BOTTOM", -5, -20)
                    exportFileBtn:SetText("Export to File")
                    api.Interface:ApplyButtonSkin(exportFileBtn, BUTTON_BASIC.DEFAULT)

                    exportWnd.titleBar.closeButton:SetHandler("OnClick", function() exportWnd:Show(false) end)

                    exportWidgets = { input = input, pageLbl = pageLbl, prevBtn = prevBtn, nextBtn = nextBtn, exportFileBtn = exportFileBtn }
                    widgets.exportWnd = exportWnd
                end

                exportWnd.page = 1

                local function UpdatePage()
                    exportWidgets.pageLbl:SetText("Page " .. exportWnd.page .. " / " .. maxPage)

                    local startIdx = (exportWnd.page - 1) * namesPerPage + 1
                    local endIdx = math.min(startIdx + namesPerPage - 1, #clean_t)

                    local chunk = {}
                    for i = startIdx, endIdx do
                        table.insert(chunk, clean_t[i])
                    end

                    if #chunk > 0 then
                        local export_str = prefix .. table.concat(chunk, ",")
                        exportWidgets.input:SetText(export_str)
                    else
                        exportWidgets.input:SetText(prefix)
                    end
                end

                exportWidgets.prevBtn:SetHandler("OnClick", function()
                    if exportWnd.page > 1 then
                        exportWnd.page = exportWnd.page - 1
                        UpdatePage()
                    end
                end)

                exportWidgets.nextBtn:SetHandler("OnClick", function()
                    if exportWnd.page < maxPage then
                        exportWnd.page = exportWnd.page + 1
                        UpdatePage()
                    end
                end)

                exportWidgets.exportFileBtn:SetHandler("OnClick", function()
                    local fileT = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                    local fileName = wnd.isWhite and "elu_tracker_whitelist.lua" or "elu_tracker_blacklist.lua"
                    local fileClean = {}
                    for _, v in pairs(fileT) do if type(v) == "string" and v ~= "" then table.insert(fileClean, v) end end
                    local exportData = { type = wnd.isWhite and "whitelist" or "blacklist", list = fileClean }
                    local ok = pcall(function() api.File:Write(fileName, exportData) end)
                    if ok then LogInfo("List exported successfully to " .. fileName) else LogInfo("Failed to export List") end
                end)

                UpdatePage()
                exportWnd:Show(true)
            end

            local importWnd = nil
            local importWidgets = nil

            local function ProcessImportString(content)
                if type(content) == "string" and content ~= "" then
                    if wnd.isWhite and string.sub(content, 1, 3) == "BL:" then
                        api.Log:Err("[Elu Auto Invite] Error: You are trying to import a Blacklist into the Whitelist!")
                        return
                    elseif not wnd.isWhite and string.sub(content, 1, 3) == "WL:" then
                        api.Log:Err("[Elu Auto Invite] Error: You are trying to import a Whitelist into the Blacklist!")
                        return
                    end

                    if string.sub(content, 1, 3) == "WL:" or string.sub(content, 1, 3) == "BL:" then
                        content = string.sub(content, 4)
                    end

                    local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                    local count = 0
                    for name in string.gmatch(content, '([^,]+)') do
                        local n = name:gsub("^%s*(.-)%s*$", "%1")
                        if n ~= "" then
                            local found = false
                            for _, v in ipairs(t) do
                                if string.lower(v) == string.lower(n) then found = true break end
                            end
                            if not found and #t < 100 then
                                table.insert(t, n)
                                count = count + 1
                            end
                        end
                    end
                    SaveSettings()
                    if wnd and wnd.RefreshList then wnd.RefreshList() end
                    LogInfo("Imported " .. tostring(count) .. " new names.")
                    if importWnd then importWnd:Show(false) end
                end
            end

            local function ShowImportWindow()
                -- Build once; reuse on every subsequent Import click instead
                -- of leaking a new top-level window each time.
                if not importWnd then
                    importWnd = api.Interface:CreateWindow("eluRImportWnd", "Import Code", 0, 0)
                    importWnd:SetExtent(300, 420)
                    importWnd:AddAnchor("CENTER", "UIParent", 0, 0)

                    local inst = importWnd:CreateChildWidget("textbox", "inst", 0, true)
                    inst:SetExtent(260, 40)
                    inst:AddAnchor("TOP", importWnd, 0, 50)
                    inst.style:SetAlign(ALIGN.CENTER)
                    ApplyTextColor(inst, FONT_COLOR.DEFAULT)
                    inst:SetText("Paste (Ctrl+V) the code you received from your friend in the box below:")

                    local input = W_CTRL.CreateMultiLineEdit("importInput", importWnd)
                    input:SetExtent(260, 200)
                    input:AddAnchor("TOP", inst, "BOTTOM", 0, 10)
                    input:SetMaxTextLength(65535)

                    local importTxtBtn = importWnd:CreateChildWidget("button", "importTxtBtn", 0, true)
                    importTxtBtn:SetExtent(120, 30)
                    importTxtBtn:AddAnchor("TOP", input, "BOTTOM", 0, 10)
                    importTxtBtn:SetText("Import Text")
                    api.Interface:ApplyButtonSkin(importTxtBtn, BUTTON_BASIC.DEFAULT)
                    importTxtBtn:SetHandler("OnClick", function()
                        ProcessImportString(input:GetText())
                    end)

                    local orLbl = importWnd:CreateChildWidget("label", "orLbl", 0, true)
                    orLbl:SetExtent(100, 20)
                    orLbl:AddAnchor("TOP", importTxtBtn, "BOTTOM", 0, 5)
                    orLbl.style:SetAlign(ALIGN.CENTER)
                    ApplyTextColor(orLbl, FONT_COLOR.DEFAULT)
                    orLbl:SetText("- OR -")

                    local importFileBtn = importWnd:CreateChildWidget("button", "importFileBtn", 0, true)
                    importFileBtn:SetExtent(150, 30)
                    importFileBtn:AddAnchor("TOP", orLbl, "BOTTOM", 0, 5)
                    importFileBtn:SetText("Import from File")
                    api.Interface:ApplyButtonSkin(importFileBtn, BUTTON_BASIC.DEFAULT)
                    importFileBtn:SetHandler("OnClick", function()
                        local fileName = wnd.isWhite and "elu_tracker_whitelist.lua" or "elu_tracker_blacklist.lua"
                        local readOk, content = pcall(function() return api.File:Read(fileName) end)
                        if readOk and content ~= nil then
                            ProcessImportString(content)
                        else
                            LogInfo("Could not read " .. fileName)
                        end
                    end)

                    importWnd.titleBar.closeButton:SetHandler("OnClick", function() importWnd:Show(false) end)

                    importWidgets = { input = input }
                    widgets.importWnd = importWnd
                end

                importWidgets.input:SetText("")
                importWnd:Show(true)
            end

            exportBtn:SetHandler("OnClick", function()
                ShowExportWindow()
            end)
            
            importBtn:SetHandler("OnClick", function()
                ShowImportWindow()
            end)
            
            wnd.exportBtn = exportBtn
            wnd.importBtn = importBtn
            wnd.inviteAllBtn = inviteAllBtn
            
            local function RefreshList()
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                local maxPage = math.ceil(#t / 5)
                if maxPage < 1 then maxPage = 1 end
                if wnd.page > maxPage then wnd.page = maxPage end
                
                wnd.pageLbl:SetText(tostring(wnd.page) .. " / " .. tostring(maxPage))
                
                local labelColor = wnd.isWhite and {0, 0.8, 0.2, 1} or {1, 0.2, 0.2, 1}
                for i = 1, 5 do
                    local dataIndex = (wnd.page - 1) * 5 + i
                    if t[dataIndex] then
                        wnd.rowWidgets[i]:Show(true)
                        wnd.rowWidgets[i].lbl:SetText(t[dataIndex])
                        ApplyTextColor(wnd.rowWidgets[i].lbl, labelColor)
                        wnd.rowWidgets[i].dataIndex = dataIndex
                    else
                        wnd.rowWidgets[i]:Show(false)
                        wnd.rowWidgets[i].dataIndex = nil
                    end
                end
                
                if wnd.listType == 3 then
                    wnd.exportBtn:Show(false)
                    wnd.importBtn:Show(false)
                    if wnd.inviteAllBtn then wnd.inviteAllBtn:Show(false) end
                else
                    wnd.importBtn:RemoveAllAnchors()
                    wnd.importBtn:AddAnchor("BOTTOMLEFT", wnd, "BOTTOM", 5, -20)
                    wnd.exportBtn:RemoveAllAnchors()
                    wnd.exportBtn:AddAnchor("BOTTOMRIGHT", wnd, "BOTTOM", -5, -20)
                    wnd.exportBtn:Show(true)
                    wnd.importBtn:Show(true)
                    
                    if wnd.listType == 1 and wnd.inviteAllBtn then
                        wnd.inviteAllBtn:RemoveAllAnchors()
                        wnd.inviteAllBtn:AddAnchor("BOTTOM", wnd, "BOTTOM", 0, -55)
                        wnd.inviteAllBtn:Show(true)
                    elseif wnd.inviteAllBtn then
                        wnd.inviteAllBtn:Show(false)
                    end
                end
            end
            wnd.RefreshList = RefreshList
            
            addBtn:SetHandler("OnClick", function()
                local n = input:GetText()
                if not n or n == "" then return end
                local t = (wnd.listType == 1 and state.whitelist or (wnd.listType == 2 and state.blacklist or state.fastBlacklist))
                if #t >= 100 then return end -- Max 100 items
                for _, v in ipairs(t) do
                    if string.lower(v) == string.lower(n) then return end
                end
                table.insert(t, n)
                SaveSettings()
                RefreshList()
                input:SetText("")
            end)
            
            local function OnClose()
                wnd:Show(false)
            end
            wnd.titleBar.closeButton:SetHandler("OnClick", OnClose)
        end
        wnd.listType = listType; wnd.isWhite = (listType == 1)
        wnd.page = 1
        wnd:SetTitle(listType == 1 and "Whitelist Manager" or (listType == 2 and "Blacklist Manager" or "Quick Auto Invite Blacklist"))
        wnd.instructions:SetText(listType == 1 and "Add players to automatically invite them" or (listType == 2 and "Add players to prevent raid invites" or "Prevent Fast Auto invites (Separate from Elu)"))
        wnd.list_label:SetText(listType == 1 and "Current Whitelist:" or (listType == 2 and "Current Blacklist:" or "Fast Blacklist:"))
        
        local labelColor = listType == 1 and {0, 0.8, 0.2, 1} or {1, 0.2, 0.2, 1}
        ApplyTextColor(wnd.instructions, labelColor)
        ApplyTextColor(wnd.player_label, labelColor)
        ApplyTextColor(wnd.list_label, labelColor)
        ApplyTextColor(wnd.pageLbl, labelColor)
        
        wnd.RefreshList()
        wnd:Show(true)
        wnd:Raise()
    end
    
    blBtn:SetHandler("OnClick", function() local ok, err = pcall(function() ToggleListWindow(2) end) if not ok then api.Log:Err(err) end end)
    wlBtn:SetHandler("OnClick", function() local ok, err = pcall(function() ToggleListWindow(1) end) if not ok then api.Log:Err(err) end end)
    widgets.ToggleListWindow = ToggleListWindow
end

function raid_invite.OnLoad()
    LoadSettings()
    if not state.doNotDisableAutoInvite and state.inviteMode ~= 0 then
        state.inviteMode = 0
        SaveSettings()
    end
    
    local raid_manager = ADDON:GetContent(UIC.RAID_MANAGER)
    if not raid_manager then return end
    state.canvas_width = raid_manager:GetWidth(); raid_manager:SetExtent(state.canvas_width, 460)
    widgets.raid_manager = raid_manager
    
    local toggleSideBtn = raid_manager:CreateChildWidget("button", "eluRaidSideBtn", 0, true)
    toggleSideBtn:SetExtent(130, 30)
    toggleSideBtn:AddAnchor("BOTTOMRIGHT", raid_manager, "TOPRIGHT", -15, -5)
    toggleSideBtn:SetText("Elu Auto Invite")
    api.Interface:ApplyButtonSkin(toggleSideBtn, BUTTON_BASIC.DEFAULT)
    
    toggleSideBtn:SetHandler("OnClick", function()
        state.isSidePanelOpen = not state.isSidePanelOpen
        if not widgets.sidePanel then
            BuildSidePanel(raid_manager)
        end
        widgets.sidePanel:Show(state.isSidePanelOpen)
    end)
    widgets.toggleSideBtn = toggleSideBtn
    
    local fIcon = api.Interface:CreateEmptyWindow("eluRaidFloatingIcon", "UIParent")
    fIcon:SetExtent(55, 40)
    fIcon:AddAnchor("TOPLEFT", "UIParent", state.floatingIconPos[1], state.floatingIconPos[2])
    fIcon:Show(state.showFloatingIcon)
    
    local fBgOn = fIcon:CreateImageDrawable("Addon/Elu_Tracker/auto_on.png", "background")
    fBgOn:SetExtent(55, 40)
    fBgOn:AddAnchor("CENTER", fIcon, 0, 0)
    fBgOn:SetColor(1, 1, 1, 0.7)
    fBgOn:SetVisible(state.inviteMode == 1)
    
    local fBgOff = fIcon:CreateImageDrawable("Addon/Elu_Tracker/auto_off.png", "background")
    fBgOff:SetExtent(55, 40)
    fBgOff:AddAnchor("CENTER", fIcon, 0, 0)
    fBgOff:SetColor(1, 1, 1, 0.7)
    fBgOff:SetVisible(state.inviteMode == 0)

    widgets.fBgOn = fBgOn
    widgets.fBgOff = fBgOff
    
    fIcon:EnableDrag(true)
    fIcon:SetHandler("OnDragStart", function() 
        if api.Input:IsShiftKeyDown() then fIcon:StartMoving() end 
    end)
    fIcon:SetHandler("OnDragStop", function() 
        fIcon:StopMovingOrSizing() 
        local x, y = fIcon:GetOffset()
        state.floatingIconPos = {x, y}
        SaveSettings()
    end)
    
    local clickOverlay = fIcon:CreateChildWidget("button", "clickOverlay", 0, true)
    clickOverlay:AddAnchor("TOPLEFT", fIcon, 0, 0)
    clickOverlay:AddAnchor("BOTTOMRIGHT", fIcon, 0, 0)
    clickOverlay.style:SetColor(0,0,0,0)
    clickOverlay:SetHandler("OnClick", ToggleActive)
    
    clickOverlay:EnableDrag(true)
    clickOverlay:SetHandler("OnDragStart", function() 
        if api.Input:IsShiftKeyDown() then fIcon:StartMoving() end 
    end)
    clickOverlay:SetHandler("OnDragStop", function() 
        fIcon:StopMovingOrSizing() 
        local x, y = fIcon:GetOffset()
        state.floatingIconPos = {x, y}
        SaveSettings()
    end)
    
    widgets.floatingIcon = fIcon
    
    local fKeywordLbl = fIcon:CreateChildWidget("label", "fKeywordLbl", 0, true)
    fKeywordLbl:SetExtent(100, 20)
    fKeywordLbl:AddAnchor("TOP", fIcon, "BOTTOM", 0, 0)
    fKeywordLbl.style:SetAlign(ALIGN.CENTER)
    fKeywordLbl.style:SetShadow(true)
    ApplyTextColor(fKeywordLbl, {1, 1, 1, 1})
    widgets.fKeywordLbl = fKeywordLbl
    
    UpdateFloatingIcon()
    
    -- Fast Auto Invite UI
    local qai_label = raid_manager:CreateChildWidget("label", "qai_label", 0, true)
    qai_label:SetExtent(200, 20)
    qai_label:AddAnchor("BOTTOMLEFT", raid_manager, 20, -105)
    qai_label:SetText("Quick Auto Invite")
    qai_label.style:SetFontSize(14)
    qai_label.style:SetShadow(false)
    ApplyTextColor(qai_label, FONT_COLOR.MIDDLE_TITLE)
    widgets.qai_label = qai_label

    local recruit_button = raid_manager:CreateChildWidget("button", "enhanced_raid_setup_button", 0, true)
    recruit_button:SetExtent(105, 30)
    recruit_button:AddAnchor("BOTTOMLEFT", raid_manager, 20, -65)
    recruit_button:SetText("Start Recruiting")
    api.Interface:ApplyButtonSkin(recruit_button, BUTTON_BASIC.DEFAULT)
    widgets.enhancedRecruitBtn = recruit_button

    local textfield = W_CTRL.CreateEdit("enhanced_recruit_message", raid_manager)
    textfield:AddAnchor("BOTTOMLEFT", raid_manager, 135, -65)
    textfield:SetExtent(110, 30)
    textfield:SetMaxTextLength(64)
    textfield:CreateGuideText("X CR")
    textfield:Show(true)
    widgets.enhancedTextfield = textfield
    
    local enhancedFilterCombo = api.Interface:CreateComboBox(raid_manager)
    enhancedFilterCombo:SetExtent(90, 30)
    enhancedFilterCombo:AddAnchor("BOTTOMLEFT", raid_manager, 255, -65)
    enhancedFilterCombo.dropdownItem = {"Equals", "Contains"}
    enhancedFilterCombo:Select(state.enhancedFilterMode or 2)
    enhancedFilterCombo:Show(true)

    -- Same combo box bug as eluFilterCombo/giveleadCombo above.
    function enhancedFilterCombo:SelectedProc(index)
        state.enhancedFilterMode = index
        SaveSettings()
    end
    widgets.enhancedFilterCombo = enhancedFilterCombo

    local fast_blacklist_button = raid_manager:CreateChildWidget("button", "fast_blacklist_button", 0, true)
    fast_blacklist_button:SetExtent(80, 30)
    fast_blacklist_button:AddAnchor("BOTTOMLEFT", raid_manager, 355, -65)
    fast_blacklist_button:SetText("Blacklist")
    api.Interface:ApplyButtonSkin(fast_blacklist_button, BUTTON_BASIC.DEFAULT)
    fast_blacklist_button:SetHandler("OnClick", function()
        if not widgets.sidePanel then
            BuildSidePanel(raid_manager)
        end
        if widgets.ToggleListWindow then
            widgets.ToggleListWindow(3)
        end
    end)
    widgets.fast_blacklist_button = fast_blacklist_button
    
    local canvas = api.Interface:CreateEmptyWindow("enhancedRecruitWindow", "UIParent")
    if state.qaiCanvasPos then
        canvas:AddAnchor("TOPLEFT", "UIParent", state.qaiCanvasPos[1], state.qaiCanvasPos[2])
    else
        canvas:AddAnchor("CENTER", "UIParent", 0, 50)
    end
    canvas:SetExtent(160, 70)
    canvas:Show(false)
    widgets.enhancedCanvas = canvas
    
    canvas:EnableDrag(true)
    canvas:SetHandler("OnDragStart", function()
        if api.Input:IsShiftKeyDown() then canvas:StartMoving() end
    end)
    canvas:SetHandler("OnDragStop", function()
        canvas:StopMovingOrSizing()
        local x, y = canvas:GetOffset()

        -- Prevent going off-screen. Was reading canvas:GetParent():GetExtent()
        -- for the screen size -- unreliable on this widget (GetParent() on a
        -- window created against the "UIParent" string doesn't reliably hand
        -- back a widget whose GetExtent() reports real screen dimensions),
        -- which made this clamp collapse to a near-fixed small screenW/screenH
        -- every time, snapping the box to the same corner on every drag no
        -- matter where it was dropped. api.Interface:GetScreenWidth/Height()
        -- is the proven-reliable way to get real screen dimensions elsewhere
        -- in this addon (see quick_equip.lua's tooltip flip logic).
        local screenW = api.Interface:GetScreenWidth()
        local screenH = api.Interface:GetScreenHeight()
        if x < 0 then x = 0 end
        if y < 0 then y = 0 end
        if x > screenW - 160 then x = screenW - 160 end
        if y > screenH - 70 then y = screenH - 70 end
        
        canvas:RemoveAllAnchors()
        canvas:AddAnchor("TOPLEFT", "UIParent", x, y)
        
        state.qaiCanvasPos = {x, y}
        SaveSettings()
    end)

    local bg = canvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.7)
    bg:AddAnchor("TOPLEFT", canvas, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", canvas, 0, 0)

    local canvas_lbl = canvas:CreateChildWidget("label", "canvas_lbl", 0, true)
    canvas_lbl:SetExtent(140, 20)
    canvas_lbl:AddAnchor("TOP", canvas, 0, 10)
    canvas_lbl.style:SetAlign(ALIGN.CENTER)
    canvas_lbl.style:SetShadow(true)
    ApplyTextColor(canvas_lbl, {1, 1, 1, 1})
    widgets.enhancedCanvasLbl = canvas_lbl

    local cancel_button = canvas:CreateChildWidget("button", "cancel_x", 0, true)
    cancel_button:SetText("Stop")
    cancel_button:SetExtent(80, 25)
    cancel_button:AddAnchor("BOTTOM", canvas, 0, -10)
    api.Interface:ApplyButtonSkin(cancel_button, BUTTON_BASIC.DEFAULT)
    
    local function StartEnhancedRecruiting()
        local msg = textfield:GetText()
        if not msg or msg == "" then
            LogErr("Please enter a recruit message.")
            return
        end
        state.enhancedIsActive = true
        state.enhancedKeyword = msg
        recruit_button:SetText("Stop")
        textfield:Enable(false)
        canvas_lbl:SetText("Keyword: " .. msg)
        canvas:Show(true)
        LogInfo("Now recruiting for: " .. msg)
        
        if state.inviteMode > 0 then
            state.inviteMode = 0
            SaveSettings()
            UpdateFloatingIcon()
            if widgets.toggleBtn then widgets.toggleBtn:SetText(GetModeString()) end
            if widgets.statusLbl then
                widgets.statusLbl:SetText("[OFF]")
                ApplyTextColor(widgets.statusLbl, {1, 0, 0, 1})
            end
            
        end
    end
    
    local function ToggleEnhancedRecruiting()
        if state.enhancedIsActive then
            raid_invite.StopEnhancedRecruiting()
            LogInfo("Stopped recruiting.")
        else
            StartEnhancedRecruiting()
        end
    end
    recruit_button:SetHandler("OnClick", ToggleEnhancedRecruiting)
    cancel_button:SetHandler("OnClick", function()
        raid_invite.StopEnhancedRecruiting()
        LogInfo("Stopped recruiting.")
    end)

    -- (Drag handlers for `canvas` are registered once, above, right after
    -- it's created -- a second SetHandler("OnDragStart"/"OnDragStop", ...)
    -- registration used to sit here and silently replace those, which
    -- dropped the position save and the off-screen clamp on every drag.)

    if not raid_invite.isLoaded then
        raid_invite.isLoaded = true
    end
end

function raid_invite.OnUpdate(dt)
    -- Leaving raid logic
    local inRaid = false
    if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
        if api.Unit:GetUnitId("team1") ~= nil or api.Unit:GetUnitId("party1") ~= nil then
            inRaid = true
        end
    end
    
    if raid_invite.wasInRaid and not inRaid then
        if not state.doNotDisableAutoInvite and state.inviteMode ~= 0 then
            state.inviteMode = 0
            SaveSettings()
            UpdateFloatingIcon()
            if widgets.toggleBtn then widgets.toggleBtn:SetText(GetModeString()) end
            if widgets.statusLbl then
                widgets.statusLbl:SetText("[OFF]")
                ApplyTextColor(widgets.statusLbl, {1, 0, 0, 1})
            end
            
        end
    end
    raid_invite.wasInRaid = inRaid
    
    
end

function raid_invite.OnUnload()
    if widgets.raid_manager and state.canvas_width and state.canvas_width > 0 then
        widgets.raid_manager:SetExtent(state.canvas_width, 395)
    end
    -- These are all injected as children of the native Raid Manager window,
    -- which this addon does not own and must never Free(). But our own
    -- children need to be freed and un-referenced here, or a later OnLoad
    -- (addon reload without a full client restart) will either try to
    -- create duplicate widgets with the same name on that native window,
    -- or reuse a dangling reference to a widget we already freed elsewhere.
    if widgets.qai_label then pcall(function() api.Interface:Free(widgets.qai_label) end) end
    if widgets.enhancedRecruitBtn then pcall(function() api.Interface:Free(widgets.enhancedRecruitBtn) end) end
    if widgets.enhancedTextfield then pcall(function() api.Interface:Free(widgets.enhancedTextfield) end) end
    if widgets.enhancedFilterCombo then pcall(function() api.Interface:Free(widgets.enhancedFilterCombo) end) end
    if widgets.fast_blacklist_button then pcall(function() api.Interface:Free(widgets.fast_blacklist_button) end) end
    if widgets.toggleSideBtn then pcall(function() api.Interface:Free(widgets.toggleSideBtn) end) end
    if widgets.sidePanel then pcall(function() api.Interface:Free(widgets.sidePanel) end) end

    -- These are our own top-level windows, so hide + free them.
    if widgets.enhancedCanvas then
        widgets.enhancedCanvas:Show(false)
        pcall(function() api.Interface:Free(widgets.enhancedCanvas) end)
    end
    if widgets.listWindow then
        widgets.listWindow:Show(false)
        pcall(function() api.Interface:Free(widgets.listWindow) end)
    end
    if widgets.exportWnd then
        widgets.exportWnd:Show(false)
        pcall(function() api.Interface:Free(widgets.exportWnd) end)
    end
    if widgets.importWnd then
        widgets.importWnd:Show(false)
        pcall(function() api.Interface:Free(widgets.importWnd) end)
    end
    if widgets.privateBypassPopup then
        widgets.privateBypassPopup:Show(false)
        pcall(function() api.Interface:Free(widgets.privateBypassPopup) end)
    end
    if widgets.floatingIcon then
        widgets.floatingIcon:Show(false)
        pcall(function() api.Interface:Free(widgets.floatingIcon) end)
    end

    -- Tooltips created by AddTooltip() are their own top-level widgets (see
    -- the comment on tooltipWidgets above), never freed by any of the
    -- parent Free() calls above -- free them explicitly here.
    for _, tooltip in ipairs(tooltipWidgets) do
        pcall(function() api.Interface:Free(tooltip) end)
    end
    tooltipWidgets = {}

    state.inviteMode = 0

    widgets.qai_label = nil
    widgets.enhancedRecruitBtn = nil
    widgets.enhancedTextfield = nil
    widgets.enhancedFilterCombo = nil
    widgets.fast_blacklist_button = nil
    widgets.toggleSideBtn = nil
    widgets.sidePanel = nil
    widgets.enhancedCanvas = nil
    widgets.listWindow = nil
    widgets.exportWnd = nil
    widgets.importWnd = nil
    widgets.privateBypassPopup = nil
    widgets.privateBypassGearBtn = nil
    widgets.floatingIcon = nil
    widgets.fKeywordLbl = nil
    widgets.ToggleListWindow = nil
    widgets.raid_manager = nil

    -- These were never nil'd out even though their parent window/panel was
    -- just freed above (widgets.sidePanel / widgets.floatingIcon /
    -- widgets.enhancedCanvas) -- so ToggleActive() and OnUpdate (both of
    -- which do "if widgets.toggleBtn then ... :SetText(...)") could still
    -- find a truthy-but-already-freed reference and error out on a stale
    -- widget after a reload cycle, instead of the guard correctly skipping
    -- it like it's meant to.
    widgets.fBgOn = nil
    widgets.fBgOff = nil
    widgets.toggleBtn = nil
    widgets.statusLbl = nil
    widgets.cbIcon = nil
    widgets.kwInput = nil
    widgets.eluFilterCombo = nil
    widgets.giveleadCombo = nil
    widgets.enhancedCanvasLbl = nil
end

raid_invite.OnChatMessage = OnChatMessage

return raid_invite







