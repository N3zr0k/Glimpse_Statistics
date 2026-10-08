local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Eigene Textform der Exportdaten (Transfer.lua). Wird nur geparst, nie als Code ausgeführt.
--   n123.5;   Zahl                 s5:hallo   Text mit Längenangabe
--   T  /  F   Wahrheitswert        {k v k v}  Tabelle, abwechselnd Schlüssel und Wert

-- Limits gegen kaputte oder manipulierte Texte
local MAX_DEPTH = 8         -- Tabellentiefe
local MAX_STRING = 500      -- Länge eines Strings in den Daten
local MAX_VALUES = 3000000  -- Werte insgesamt

local function WriteValue(out, value, depth)
    local kind = type(value)

    if kind == "number" then
        out[#out + 1] = "n" .. format("%.14g", value) .. ";"
    elseif kind == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif kind == "boolean" then
        out[#out + 1] = value and "T" or "F"
    elseif kind == "table" then
        if depth > MAX_DEPTH then error("table too deep") end

        local keys = {}
        for key in pairs(value) do
            local keyType = type(key)
            if keyType == "number" or keyType == "string" then keys[#keys + 1] = key end
        end
        -- sortiert: gleicher Inhalt ergibt gleichen Text
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            return a < b
        end)

        out[#out + 1] = "{"
        for _, key in ipairs(keys) do
            WriteValue(out, key, depth + 1)
            WriteValue(out, value[key], depth + 1)
        end
        out[#out + 1] = "}"
    else
        error("unsupported value type " .. kind)
    end
end

function S.Serialize(value)
    local out = {}
    WriteValue(out, value, 0)
    return table.concat(out)
end

-- Gibt Wert und neue Position zurück; wirft bei Fehlern (Deserialize fängt per pcall).
local function ReadValue(text, pos, depth, state)
    state.values = state.values + 1
    if state.values > MAX_VALUES then error("too many values") end

    local tag = text:sub(pos, pos)

    if tag == "n" then
        local stop = text:find(";", pos, true)
        local number = stop and tonumber(text:sub(pos + 1, stop - 1))
        -- NaN und inf ablehnen
        if not number or number ~= number or number >= 1e15 or number <= -1e15 then error("bad number") end
        return number, stop + 1

    elseif tag == "s" then
        local colon = text:find(":", pos, true)
        local length = colon and tonumber(text:sub(pos + 1, colon - 1))
        if not length or length < 0 or length > MAX_STRING or length ~= math.floor(length) then
            error("bad string length")
        end
        local value = text:sub(colon + 1, colon + length)
        if #value ~= length then error("truncated string") end
        return value, colon + length + 1

    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1

    elseif tag == "{" then
        if depth >= MAX_DEPTH then error("table too deep") end

        local result = {}
        pos = pos + 1
        while text:sub(pos, pos) ~= "}" do
            if pos > #text then error("unterminated table") end

            local key, value
            key, pos = ReadValue(text, pos, depth + 1, state)
            if type(key) ~= "number" and type(key) ~= "string" then error("bad key") end
            value, pos = ReadValue(text, pos, depth + 1, state)
            result[key] = value
        end
        return result, pos + 1
    end

    error("unexpected character at " .. pos)
end

--- Bei Fehlern nil, Meldung.
function S.Deserialize(text)
    local ok, value, pos = pcall(ReadValue, text, 1, 0, { values = 0 })
    if not ok then return nil, value end
    if pos ~= #text + 1 then return nil, "unexpected data at the end" end
    if type(value) ~= "table" then return nil, "not a table" end
    return value
end
