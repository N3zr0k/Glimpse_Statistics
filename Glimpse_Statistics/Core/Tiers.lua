local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Berufe und ihre Stufen. Stufe = Skill-Maximum (75, 150 ...), Name = Rang-Text des Stufenzaubers (Lehrling ...),
-- sonst "Fertigkeit bis 75". Die Werte je Stufe schreibt Glimpse: Professions (casttier, catchtier).

local api = S.api

-- Skill-Linie und Stufenzauber je Beruf; n-ter Zauber = Maximum n * 75
S.TIER_PROFESSIONS = {
    fishing = { line = 356, spells = { 7620, 7731, 7732, 18248, 33095, 51294 } },
    herbalism = { line = 182, spells = { 2366, 2368, 3570, 11993, 28695, 50300 } },
    mining = { line = 186, spells = { 2575, 2576, 3564, 10248, 29354, 50310 } },
    skinning = { line = 393, spells = { 8613, 8617, 8618, 10768, 32678, 50305 } },
}

local LOWEST = 75

-- Lokalisierter Name, nil wenn nicht gelernt oder nicht lesbar
local function FindProfession(profession)
    local info = S.TIER_PROFESSIONS[profession]
    if not (info and api.GetProfessions and api.GetProfessionInfo) then return nil end

    local ok, name = pcall(function()
        local indexes = { api.GetProfessions() }
        for position = 1, 6 do
            local index = indexes[position]
            if index then
                local found, _, _, _, _, _, line = api.GetProfessionInfo(index)
                if line == info.line then return found end
            end
        end
    end)
    if ok then return name end
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
