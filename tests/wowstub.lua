-- luacheck: ignore 111 113 122 143 432
-- Minimale Nachbildung der WoW-Umgebung, damit sich die reine Logik offline testen lässt.
-- Aufruf aus dem Hauptordner des Repos:  lua tests/run.lua
-- Glimpse: Database wird echt geladen, aus dem Repo Glimpse daneben oder aus GLIMPSE_DIR.
local stub = {}

local ROOT = ((arg and arg[0] or ""):match("^(.*)/[^/]*$") or ".") .. "/.."
local GLIMPSE_DIR = os.getenv("GLIMPSE_DIR") or (ROOT .. "/../Glimpse")

-- 2026-01-11 12:00 UTC, Mittag, damit "heute" in jeder Zeitzone derselbe Tag ist
stub.NOON = 1767225600 + 86400 * 10 + 12 * 3600

function stub.reset()
    _G.unpack = _G.unpack or table.unpack
    _G.time, _G.date = os.time, os.date
    _G.strsplit = function(sep, s) local out = {} for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end return unpack(out) end
    _G.CreateFrame = function() return stub.newFrame() end
    _G.ipairs = ipairs
    _G.tinsert = table.insert
    _G.tremove = table.remove
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.format = string.format
    _G.strmatch = string.match
    _G.strlower = string.lower
    _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    _G.tContains = function(t, value) for _, v in ipairs(t) do if v == value then return true end end return false end
    _G.GlimpseDB, _G.GlimpseStatisticsDB = nil, nil
    for _, name in ipairs({ "GlimpseDB_Meta", "GlimpseDB_Core", "GlimpseDB_Gathering", "GlimpseDB_Professions",
        "GlimpseDB_Reputation", "GlimpseDB_Misc", "GlimpseGatheringDB" }) do
        _G[name] = nil
    end
    stub.player = { guid = "Player-1-00000001", name = "Flovy", realm = "Forever", class = "MAGE" }
    stub.serverTime = stub.NOON
end

-- Das Addon-Objekt (Glimpse) mit Modulen, Befehlen, Optionen, Debuggern und Probes
function stub.newGlimpse()
    local L = setmetatable({ DATE_FORMAT = "%Y-%m-%d" }, { __index = function(_, key) return key end })
    local Glimpse = { L = L, modules = {}, commands = {},
        printed = {}, logged = {}, probes = {}, errors = {}, dataSources = {} }
    function Glimpse:GetModule(name) return self.modules[name] end
    function Glimpse:IsSecret() return false end
    function Glimpse:IsDebug() return false end
    function Glimpse:NewModule(name)
        local module = {
            name = name, messages = {},
            SendMessage = function(self, message, ...) self.messages[#self.messages + 1] = { message, ... } end,
        }
        self.modules[name] = module
        return module
    end
    function Glimpse:RegisterCommand(name, desc, func) self.commands[name] = { desc = desc, func = func } end
    function Glimpse:Print(text) self.printed[#self.printed + 1] = text end
    function Glimpse:AddLogLine(text) self.logged[#self.logged + 1] = text end
    function Glimpse:RegisterAddonOptions(_, options) self.options = options end
    function Glimpse:RegisterProbe(group, name, func) self.probes[group .. " " .. name] = func end
    function Glimpse:RegisterDataSource(addon, func) self.dataSources[addon] = func end
    function Glimpse:ShowTextWindow(title, text) self.textWindow = { title = title, text = text } end
    function Glimpse:NewDebugger(name)
        local glimpse = self
        return {
            name = name,
            Log = function() end, Warn = function() end,
            Error = function(_, category, text, ...) glimpse.errors[#glimpse.errors + 1] = category .. ": " .. format(text, ...) end,
            IsOn = function() return false end,
        }
    end
    -- Einstellungen wie AceDB: Namespace mit Kopien der Standardwerte
    local function Copy(t)
        local out = {}
        for k, v in pairs(t or {}) do out[k] = type(v) == "table" and Copy(v) or v end
        return out
    end
    Glimpse.db = { RegisterNamespace = function(_, _, defaults) return { profile = Copy(defaults.profile), char = Copy(defaults.char) } end }

    _G.LibStub = function(name)
        if name == "AceLocale-3.0" then return { GetLocale = function() return Glimpse.L end } end
        return { GetAddon = function() return Glimpse end }
    end
    return Glimpse
end

-- Ein Frame, der seine Skripte und Ereignisse nur festhält
function stub.newFrame()
    local frame = { scripts = {}, events = {} }
    function frame:SetScript(name, func) self.scripts[name] = func end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:UnregisterAllEvents() self.events = {} end
    return frame
end

-- Lädt eine Addon-Datei, ADDON_NAME wird wie vom Client als erstes Argument übergeben
function stub.load(path, addonName)
    local chunk, err = loadfile(ROOT .. "/Glimpse_Statistics/" .. path) -- Pfade relativ zum Addon-Ordner
    assert(chunk, err)
    return chunk(addonName or "Test")
end

-- Dateien einer XML in Ladereihenfolge (Script und Include, rekursiv)
local function XmlFiles(path, list)
    local base = path:match("^(.*)/[^/]*$")
    local handle = assert(io.open(path), "fehlt: " .. path)
    local text = handle:read("*a"):gsub("<!%-%-.-%-%->", "")
    handle:close()
    for tag, file in text:gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
        file = base .. "/" .. file:gsub("\\", "/")
        if tag == "Include" then XmlFiles(file, list) else list[#list + 1] = file end
    end
    return list
end

--- Lädt die echte Glimpse: Database wie der Client (Dateien, SavedVariables, ADDON_LOADED, PLAYER_LOGIN).
-- saved: SavedVariables (z. B. GlimpseStatisticsDB für die Übernahme). Gibt GlimpseDB und die private Tabelle zurück.
function stub.loadDatabase(saved)
    local addonDir = GLIMPSE_DIR .. "/Glimpse_Database"
    local toc = assert(io.open(addonDir .. "/Glimpse_Database.toc"), "Glimpse_Database fehlt, GLIMPSE_DIR setzen"):read("*a")
    local version = toc:match("## Version: (%S+)")

    local fake = _G.LibStub
    _G.LibStub = nil
    _G.GetServerTime = function() return stub.serverTime end
    _G.UnitGUID = function(unit) return unit == "player" and stub.player.guid or nil end
    _G.UnitName = function(unit) return unit == "player" and stub.player.name or nil end
    _G.UnitClass = function() return stub.player.class, stub.player.class end
    _G.GetRealmName = function() return stub.player.realm end
    _G.geterrorhandler = function() return function(err) error(err, 0) end end
    _G.debugprofilestop = function() return os.clock() * 1000 end
    _G.securecallfunction = function(func, ...) return func(...) end
    _G.gsub = string.gsub
    local loaded = {}
    _G.C_AddOns = {
        IsAddOnLoaded = function(name) return loaded[name] == true end,
        LoadAddOn = function(name) loaded[name] = true return true end,
        GetAddOnMetadata = function(addon, field) if field == "Version" and addon == "Glimpse_Database" then return version end end,
    }
    local frames = {}
    _G.CreateFrame = function()
        local frame = stub.newFrame()
        frames[#frames + 1] = frame
        return frame
    end

    local private = {}
    for _, file in ipairs(XmlFiles(addonDir .. "/Glimpse_Database.xml", {})) do
        assert(loadfile(file))("Glimpse_Database", private)
    end
    for name, value in pairs(saved or {}) do _G[name] = value end
    for _, event in ipairs({ { "ADDON_LOADED", "Glimpse_Database" }, { "PLAYER_LOGIN" } }) do
        for _, frame in ipairs(frames) do
            if frame.events[event[1]] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event[1], event[2]) end
        end
    end

    _G.LibStub = fake
    _G.CreateFrame = function() return stub.newFrame() end
    return _G.GlimpseDB, private
end

--- Glimpse, Database und Statistics wie im Spiel geladen und eingeschaltet. saved wie bei loadDatabase.
-- Gibt S, Glimpse, GlimpseDB und die private Tabelle von Database zurück.
function stub.setup(saved)
    local Glimpse = stub.newGlimpse()
    local DB, P = stub.loadDatabase(saved)
    -- Texte nicht: L gibt im Test den englischen Schlüssel zurück
    for _, file in ipairs(XmlFiles(ROOT .. "/Glimpse_Statistics/Glimpse_Statistics.xml", {})) do
        if not file:find("/Locales/", 1, true) then assert(loadfile(file))("Glimpse_Statistics") end
    end
    local S = Glimpse:GetModule("Statistics")
    S:OnInitialize()
    S:OnEnable()
    return S, Glimpse, DB, P
end

return stub
