-- luacheck: ignore 111 113 122 143 432
-- Minimale Nachbildung der WoW-Umgebung, damit sich die reine Logik offline testen lässt.
-- Aufruf aus dem Hauptordner des Repos:  lua tests/run.lua
local stub = {}

local ROOT = ((arg and arg[0] or ""):match("^(.*)/[^/]*$") or ".") .. "/.."

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
end

-- Das Addon-Objekt (Glimpse) mit Modulen, Befehlen und Optionen
function stub.newGlimpse()
    local Glimpse = { L = setmetatable({}, { __index = function(_, key) return key end }), modules = {}, commands = {}, printed = {} }
    function Glimpse:GetModule(name) return self.modules[name] end
    function Glimpse:IsSecret() return false end
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
    function Glimpse:RegisterAddonOptions(_, options) self.options = options end

    _G.LibStub = function(name, silent)
        if name == "LibDeflate" then if silent then return nil end error("LibDeflate fehlt") end
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

return stub
