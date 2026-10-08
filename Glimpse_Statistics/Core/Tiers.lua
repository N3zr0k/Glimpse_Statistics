local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Berufszähler zusätzlich je Stufe, z. B. für die Fangquote je Stufe. Stufe = Skill-Maximum (75, 150 ...),
-- Name = Rang-Text des Stufenzaubers (Lehrling ...), sonst "Fertigkeit bis 75".
-- Gespeichert als "<key>.tier" mit Stufe als subKey. Werte ohne Stufe zählen zur niedrigsten (GetTierCounts).

local api = S.api

-- Skill-Linie und Stufenzauber je Beruf; n-ter Zauber = Maximum n * 75
S.TIER_PROFESSIONS = {
    fishing = { line = 356, spells = { 7620, 7731, 7732, 18248, 33095, 51294 } },
    herbalism = { line = 182, spells = { 2366, 2368, 3570, 11993, 28695, 50300 } },
    mining = { line = 186, spells = { 2575, 2576, 3564, 10248, 29354, 50310 } },
    skinning = { line = 393, spells = { 8613, 8617, 8618, 10768, 32678, 50305 } },
}

-- Zähler -> Beruf
S.TIERED = {
    ["fishing.casts"] = "fishing", ["fishing.catches"] = "fishing", ["fishing.items"] = "fishing",
    ["gathering.herb"] = "herbalism", ["gathering.ore"] = "mining", skinning = "skinning",
}

local LOWEST = 75

-- Name und Skill-Maximum, nil wenn nicht gelernt oder nicht lesbar
local function FindProfession(profession)
    local info = S.TIER_PROFESSIONS[profession]
    if not (info and api.GetProfessions and api.GetProfessionInfo) then return nil end

    local ok, name, maximum = pcall(function()
        local indexes = { api.GetProfessions() }
        for position = 1, 6 do
            local index = indexes[position]
            if index then
                local found, _, _, max, _, _, line = api.GetProfessionInfo(index)
                if line == info.line then return found, tonumber(max) end
            end
        end
    end)
    if ok then return name, maximum end
end

--- 75, 150 ... oder nil
function S:ProfessionMax(profession)
    local _, maximum = FindProfession(profession)
    if maximum and maximum > 0 then return maximum end
end

--- Lokalisiert vom Client, nil wenn nicht gelernt.
function S:ProfessionClientName(profession)
    local name = FindProfession(profession)
    if type(name) == "string" and name ~= "" and not Glimpse:IsSecret(name) then return name end
end

--- Rang-Text des Stufenzaubers, sonst "Fertigkeit bis 75".
function S:TierName(profession, maximum)
    local info = S.TIER_PROFESSIONS[profession]
    local spell = info and info.spells[maximum / LOWEST]
    if spell then
        local text
        if api.GetSpellSubtext then
            local ok, value = pcall(api.GetSpellSubtext, spell)
            if ok then text = value end
        end
        if not text and api.GetSpellInfo then
            local ok, _, value = pcall(api.GetSpellInfo, spell) -- Classic: Rang-Text als zweite Rückgabe
            if ok then text = value end
        end
        if type(text) == "string" and text ~= "" and not Glimpse:IsSecret(text) then return text end
    end
    return format(L["Skill up to %d"], maximum)
end

--- Nur für S.TIERED und bekannte Stufe.
function S:AddTier(key, amount)
    local profession = S.TIERED[key]
    if not profession then return end

    local maximum = self:ProfessionMax(profession)
    if maximum then self:Add(key .. ".tier", amount, maximum, self:TierName(profession, maximum)) end
end

--- Liste { max, name, count } aufsteigend. Werte ohne Stufe zählen zur niedrigsten; leer ohne Stufenwerte.
function S:GetTierCounts(key, scope)
    local profession = S.TIERED[key]
    if not profession then return {} end

    local list, sum, byMax = {}, 0, {}
    for _, entry in ipairs(self:GetBreakdown(key .. ".tier", scope, 100)) do
        local maximum = tonumber(entry.key)
        if maximum and entry.count > 0 then
            local item = { max = maximum, name = entry.name, count = entry.count }
            list[#list + 1] = item
            byMax[maximum] = item
            sum = sum + entry.count
        end
    end
    if #list == 0 then return list end

    -- Blizzard-Startwert gehört zu keiner Stufe
    local legacy = self:GetCounted(key, scope) - sum
    if legacy > 0 then
        if not byMax[LOWEST] then
            byMax[LOWEST] = { max = LOWEST, name = self:TierName(profession, LOWEST), count = 0 }
            list[#list + 1] = byMax[LOWEST]
        end
        byMax[LOWEST].count = byMax[LOWEST].count + legacy
    end
    table.sort(list, function(a, b) return a.max < b.max end)
    return list
end
