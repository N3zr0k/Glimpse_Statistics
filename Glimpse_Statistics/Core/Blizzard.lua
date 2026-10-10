local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Liest die Blizzard-Statistiken (WoW: Forever) für /gli stats blizzard, speichert nichts. Soll später in den Core,
-- zusammen mit dem Lesen der Startwerte (Herkunft baseline in Database).
-- API:GetStatisticsCategoryList, GetCategoryInfo, GetCategoryNumAchievements, GetAchievementInfo, GetStatistic.

local Clean = S.Clean

local NAMES = { list = "GetStatisticsCategoryList", info = "GetCategoryInfo", num = "GetCategoryNumAchievements",
    ach = "GetAchievementInfo", stat = "GetStatistic" }

--- Funktionen (nil wenn fehlend) und ob alle vorhanden sind.
function S:BlizzardApi()
    local api, complete = {}, true
    for key, name in pairs(NAMES) do
        local fn = _G[name]
        if type(fn) == "function" then api[key] = fn else complete = false end
    end
    return api, complete
end

-- pcall, Secrets -> nil
local function Call(fn, ...)
    local result = { pcall(fn, ...) }
    if not table.remove(result, 1) then return nil end
    for index = 1, #result do result[index] = Clean(result[index]) end
    return unpack(result)
end

--- Liste { id, name, parent, stats = { { id, name, value } } }, nil ohne API.
function S:ReadBlizzardStats()
    local api, complete = self:BlizzardApi()
    if not complete then return nil end

    local ids = Call(api.list)
    if type(ids) ~= "table" then return {} end

    local categories = {}
    for _, id in ipairs(ids) do
        local name, parent = Call(api.info, id)
        local category = { id = id, name = tostring(name or id), parent = parent, stats = {} }
        local count = tonumber((Call(api.num, id))) or 0
        for index = 1, count do
            local statID, statName = Call(api.ach, id, index)
            if statID then
                local value = Call(api.stat, statID)
                category.stats[#category.stats + 1] = { id = statID, name = tostring(statName or statID), value = value }
            end
        end
        categories[#categories + 1] = category
    end
    return categories
end

--- Globale und C_-Funktionen mit "statistic" im Namen, max. 40. Zum Finden einer abweichenden API.
function S:BlizzardFunctionNames()
    local found = {}
    local function Add(name) if #found < 40 then found[#found + 1] = name end end

    for name, value in pairs(_G) do
        if type(name) == "string" then
            if type(value) == "function" and name:lower():find("statistic", 1, true) then
                Add(name)
            elseif type(value) == "table" and name:sub(1, 2) == "C_" then
                for key, inner in pairs(value) do
                    if type(key) == "string" and type(inner) == "function" and key:lower():find("statistic", 1, true) then
                        Add(name .. "." .. key)
                    end
                end
            end
        end
    end
    table.sort(found)
    return found
end

--- filter: Teilstring im Namen. categories optional, aus ReadBlizzardStats.
function S:BlizzardLines(filter, categories)
    local lines = {}
    local api, complete = self:BlizzardApi()

    local have = {}
    for key, name in pairs(NAMES) do have[#have + 1] = name .. "=" .. (api[key] and "yes" or "NO") end
    table.sort(have)
    lines[#lines + 1] = "Statistics API: " .. table.concat(have, " ")

    local others = self:BlizzardFunctionNames()
    if #others > 0 then lines[#lines + 1] = "Functions with \"statistic\": " .. table.concat(others, ", ") end
    if not complete then
        lines[#lines + 1] = "The classic statistics API is not complete in this client."
        return lines
    end

    categories = categories or self:ReadBlizzardStats() or {}
    local total = 0
    for _, category in ipairs(categories) do total = total + #category.stats end
    lines[#lines + 1] = format("%d categories, %d statistics", #categories, total)

    local needle = filter and filter ~= "" and filter:lower() or nil
    local shown = 0
    for _, category in ipairs(categories) do
        for _, stat in ipairs(category.stats) do
            if needle and stat.name:lower():find(needle, 1, true) then
                shown = shown + 1
                if shown <= 40 then
                    lines[#lines + 1] = format("[%s] %s (%s) = %s", category.name, stat.name, tostring(stat.id), tostring(stat.value))
                end
            end
        end
    end
    if needle then
        lines[#lines + 1] = format("%d matches for \"%s\"%s", shown, filter, shown > 40 and " (first 40 shown, narrow the search)" or "")
    else
        lines[#lines + 1] = "More: /gli stats blizzard all (all values in a window to copy), /gli stats blizzard <text> (search by name)"
    end
    return lines
end

function S:BlizzardDumpText()
    local _, complete = self:BlizzardApi()
    local categories = complete and self:ReadBlizzardStats() or {}
    local out = {}
    for _, line in ipairs(self:BlizzardLines(nil, categories)) do out[#out + 1] = line end
    if not complete then return table.concat(out, "\n") end

    out[#out + 1] = ""
    for _, category in ipairs(categories) do
        out[#out + 1] = format("== %s (category %s, parent %s)", category.name, tostring(category.id), tostring(category.parent))
        for _, stat in ipairs(category.stats) do
            out[#out + 1] = format("%s | %s | %s", tostring(stat.id), stat.name, tostring(stat.value))
        end
    end
    return table.concat(out, "\n")
end
