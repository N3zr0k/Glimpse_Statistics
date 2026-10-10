local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Zahlen je Einheit eines Zählers (unit in Counters.lua): Anzahl, Zeit, Strecke.
-- Strecke in km oder Meilen je Sprache (L["DISTANCE_UNIT"]), gespeichert sind Yards.

local YARDS_PER = { km = 1093.6133, mi = 1760 }

--- Tausendertrennung: 12345 -> 12 345
function S.FormatNumber(value)
    local text = tostring(math.floor(value))
    while true do
        local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
        text = replaced
        if count == 0 then break end
    end
    return text
end

--- Sekunden -> "45 s", "12 min", "3 h 12 min"
function S.FormatDuration(seconds)
    seconds = math.floor(seconds or 0)
    if seconds < 60 then return format("%d s", seconds) end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return format("%d min", minutes) end
    return format("%s h %d min", S.FormatNumber(minutes / 60), minutes % 60)
end

--- Yards -> "12,3 km" bzw. "7.6 mi", eine Nachkommastelle
function S.FormatDistance(yards)
    local unit = YARDS_PER[L["DISTANCE_UNIT"]] and L["DISTANCE_UNIT"] or "km"
    local tenths = math.floor((yards or 0) / YARDS_PER[unit] * 10 + 0.5)
    local separator = L["DECIMAL_SEPARATOR"]
    if #separator ~= 1 then separator = "." end
    return format("%s%s%d %s", S.FormatNumber(tenths / 10), separator, tenths % 10, unit)
end

--- Wert eines Zählers als Text in seiner Einheit.
function S:FormatValue(key, value)
    local counter = self.counterByKey[key]
    local unit = counter and counter.unit
    if unit == "time" then return S.FormatDuration(value) end
    if unit == "distance" then return S.FormatDistance(value) end
    return S.FormatNumber(value or 0)
end
