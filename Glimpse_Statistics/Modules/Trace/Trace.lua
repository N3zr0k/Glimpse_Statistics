local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Event-Trace zur Fehlersuche: gibt Client-Events mit Zeit und Zielzustand im Chat aus, zählt nichts. Die Zeilen
-- stehen auch im Log des Core (/gli debug log, zum Kopieren). Soll später in den Core.
--
--   /gli stats trace             an/aus (Lärm stumm, nur Spieler, Ziel, Pet ...)
--   /gli stats trace all         ungefiltert
--   /gli stats trace full        RegisterAllEvents; kann gesperrte Events (Kampflog) treffen und eine
--                                Client-Sperrmeldung auslösen. Nur wenn TRACE_EVENTS etwas fehlt.
--   /gli stats trace mute X      X stumm, * am Ende = Präfix (z. B. UNIT_POWER*)
--   /gli stats trace unmute X    wieder anzeigen
--   /gli stats trace list        stumme Events
--   /gli stats trace reset       Stummschaltung zurücksetzen

local api = S.api
local Clean = S.Clean

-- Immer im Chat, auch ohne Debug-Modus, und im Log des Core. grey: Ereigniszeile
local function Say(text, grey)
    if Glimpse.AddLogLine then Glimpse:AddLogLine("[Glimpse:Statistics/trace] " .. text) end
    Glimpse:Print("|cff66ccff[Statistics]|r " .. (grey and ("|cff999999" .. text .. "|r") or text))
end

local frame = CreateFrame("Frame")
S.traceFrame = frame
S.tracing = false
S.traceAll = false
S.traceCounts = {}

-- Einzeln registriert, dem Client unbekannte Namen werden übersprungen.
local TRACE_EVENTS = {
    -- Kampf und Ziel
    "PLAYER_TARGET_CHANGED", "PLAYER_TARGET_DIED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTER_COMBAT",
    "PLAYER_LEAVE_COMBAT", "PLAYER_IN_COMBAT_CHANGED", "PLAYER_SWING", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PARTY_KILL", "UNIT_DIED", "UNIT_DESTROYED", "UNIT_TARGET", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FLAGS",
    "UNIT_DYNAMIC_FLAGS", "UNIT_COMBAT", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_PET",
    "PET_ATTACK_START", "PET_ATTACK_STOP", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT",
    "GROUP_ROSTER_UPDATE", "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    -- Zauber
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "CURRENT_SPELL_CAST_CHANGED", "SPELL_RANGE_CHECK_UPDATE", "ACTION_RANGE_CHECK_UPDATE", "ACTION_USABLE_CHANGED",
    "PLAYER_EQUIPED_SPELLS_CHANGED", "SPELLS_CHANGED",
    -- Beute und Gegenstände
    "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_BIND_CONFIRM",
    "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "ITEM_PUSH", "ITEM_COUNT_CHANGED", "ITEM_LOCKED", "ITEM_UNLOCKED",
    "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_SKILL", "CHAT_MSG_SYSTEM", "CHAT_MSG_OPENING", "CHAT_MSG_TRADESKILLS",
    "CHAT_MSG_PET_INFO", "CHAT_MSG_CURRENCY", "PLAYER_MONEY", "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE",
    -- Fertigkeiten, Erfahrung, Quests, Orte
    "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_CLOSE", "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP", "UPDATE_FACTION", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "NEW_WMO_CHUNK",
    -- Maus und Cursor
    "GLOBAL_REGION_MOUSE_DOWN", "GLOBAL_REGION_MOUSE_UP", "WORLD_CURSOR_TOOLTIP_UPDATE", "PLAYER_STARTED_LOOKING",
    "PLAYER_STOPPED_LOOKING",
}

-- Für Addons gesperrt: nie registriert (nach RegisterAllEvents abgemeldet), nie ausgegeben, auch nicht mit all/unmute.
-- * = Präfix.
local FORBIDDEN = { "COMBAT_LOG*", "CHAT_MSG_COMBAT_*", "CHAT_MSG_SPELL_*", "COMBAT_TEXT_*" }

local function IsForbidden(event)
    for _, pattern in ipairs(FORBIDDEN) do
        if pattern:sub(-1) == "*" then
            if event:sub(1, #pattern - 1) == pattern:sub(1, -2) then return true end
        elseif event == pattern then
            return true
        end
    end
    return false
end

-- Standardmäßig stumm, * = Präfix
local DEFAULT_MUTED = {
    "ACTIONBAR_*", "SPELL_UPDATE_*", "SPELL_ACTIVATION_*", "UNIT_AURA", "UNIT_POWER*", "UNIT_MAXPOWER", "COMBAT_LOG*",
    "UPDATE_*", "BAG_*", "CURSOR_*", "MODIFIER_STATE_CHANGED", "GET_ITEM_INFO_RECEIVED", "CHAT_MSG_CHANNEL*",
    "CHAT_MSG_ADDON*", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY*",
    "CHAT_MSG_RAID*", "CHAT_MSG_WHISPER*", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "PLAYER_STARTED_MOVING",
    "PLAYER_STOPPED_MOVING", "PLAYER_STARTED_TURNING", "PLAYER_STOPPED_TURNING", "NAME_PLATE_CREATED",
    "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_ATTACK*", "UNIT_DAMAGE", "UNIT_STATS", "UNIT_DEFENSE",
    "UNIT_RESISTANCES", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_NAME_UPDATE", "UNIT_INVENTORY_CHANGED",
    "UNIT_RANGED*", "UNIT_SPELL_HASTE", "UNIT_DISPLAYPOWER", "PLAYER_EQUIPMENT_CHANGED", "RAID_TARGET_UPDATE",
    "UI_*", "SOUND_*", "ADDON_*", "PET_BAR_*", "MINIMAP_*", "WORLD_MAP_*", "CRITERIA_*", "COMPANION_*",
    "TIME_PLAYED_MSG", "CVAR_UPDATE", "DISPLAY_SIZE_CHANGED", "GLOBAL_MOUSE_*", "PLAYER_ENTER_COMBAT_*",
}

local muted, mutedPrefix = {}, {}

local function SetMuted(pattern, on)
    if pattern:sub(-1) == "*" then
        mutedPrefix[pattern:sub(1, -2)] = on or nil
    else
        muted[pattern] = on or nil
    end
end

local function ResetMuted()
    wipe(muted)
    wipe(mutedPrefix)
    for _, pattern in ipairs(DEFAULT_MUTED) do SetMuted(pattern, true) end
end
ResetMuted()

local function IsMuted(event)
    if muted[event] then return true end
    for prefix in pairs(mutedPrefix) do
        if event:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- Unit-Events nur für diese Einheiten, sonst flutet Gruppe/Raid den Chat
local UNITS = { player = true, target = true, pet = true, pettarget = true, mouseover = true, focus = true,
    targettarget = true, softenemy = true, softfriend = true }

local function WantedUnit(unit)
    if type(unit) ~= "string" then return true end -- kein Unit-Event
    if unit:find("^%a+%-") then return true end -- GUID (z. B. UNIT_DIED)
    return UNITS[unit] or unit:find("^nameplate") ~= nil
end

local function Text(value)
    if value == nil then return "nil" end
    if Glimpse:IsSecret(value) then return "<secret>" end
    local text = tostring(value):gsub("|", "||")
    if #text > 100 then text = text:sub(1, 100) .. "..." end
    return text
end

local function TargetState()
    local name = Clean(api.UnitName("target"))
    if name == nil then return "target=none" end
    local ok, dead = pcall(api.UnitIsDead, "target")
    return format("target=%s dead=%s", Text(name), Text(ok and Clean(dead)))
end

function S:TraceEvent(event, ...)
    if IsForbidden(event) then return end
    self.traceCounts[event] = (self.traceCounts[event] or 0) + 1
    if not self.traceAll then
        if IsMuted(event) then return end
        if event:find("^UNIT_") and not WantedUnit((...)) then return end
    end

    local parts = {}
    for index = 1, math.min(select("#", ...), 10) do parts[#parts + 1] = Text((select(index, ...))) end
    Say(format("[%.2f] %s(%s) %s", api.GetTime(), event, table.concat(parts, ", "), TargetState()), true)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(S.TraceEvent, S, event, ...)
    if not ok then S.debug:Error("trace", "%s: %s", event, tostring(err)) end
end)

local function Stop()
    frame:UnregisterAllEvents()
    S.tracing = false

    -- häufigste Events
    local list = {}
    for event, n in pairs(S.traceCounts) do list[#list + 1] = { event, n } end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local parts = {}
    for index = 1, math.min(#list, 15) do parts[#parts + 1] = list[index][1] .. "=" .. list[index][2] end
    Say("trace off. Most frequent events: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
    wipe(S.traceCounts)
end

local function Start(all, full)
    wipe(S.traceCounts)
    S.traceAll = all and true or false

    if full and pcall(frame.RegisterAllEvents, frame) then
        for _, event in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "COMBAT_LOG_EVENT", "COMBAT_TEXT_UPDATE" }) do
            pcall(frame.UnregisterEvent, frame, event)
        end
        S.tracing = true
        Say("trace on for ALL events (full). If the client reports a blocked action, use /gli stats trace without full. " ..
            "Mute: /gli stats trace mute <EVENT>, stop: /gli stats trace")
        return
    end

    local known, unknown = 0, {}
    for _, event in ipairs(TRACE_EVENTS) do
        if not IsForbidden(event) then
            if pcall(frame.RegisterEvent, frame, event) then known = known + 1 else unknown[#unknown + 1] = event end
        end
    end
    S.tracing = true
    Say("trace on" .. (all and " (unfiltered)" or "") .. " for " .. known ..
        " events. Mute: /gli stats trace mute <EVENT>, list: /gli stats trace list, stop: /gli stats trace")
    if #unknown > 0 then Say("unknown to this client: " .. table.concat(unknown, ", ")) end
end

--- Gibt zurück, ob der Trace danach läuft.
function S:Trace(args)
    local word, rest = strmatch(strtrim(args or ""), "^(%S*)%s*(.-)$")
    word = word:lower()

    if word == "mute" or word == "unmute" then
        if rest == "" then Say("/gli stats trace " .. word .. " <EVENT>") return self.tracing end
        local pattern = rest:upper()
        SetMuted(pattern, word == "mute")
        Say(pattern .. (word == "mute" and " muted" or " shown"))
        return self.tracing
    end
    if word == "list" then
        local list = {}
        for event in pairs(muted) do list[#list + 1] = event end
        for prefix in pairs(mutedPrefix) do list[#list + 1] = prefix .. "*" end
        table.sort(list)
        Say("muted: " .. table.concat(list, ", "))
        return self.tracing
    end
    if word == "reset" then
        ResetMuted()
        Say("mute list reset")
        return self.tracing
    end

    if self.tracing then
        Stop()
        return false
    end
    Start(word == "all" or word == "full", word == "full")
    return true
end
