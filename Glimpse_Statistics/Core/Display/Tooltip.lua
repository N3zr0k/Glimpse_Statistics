local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Kills/Tode je Kreatur im Unit-Tooltip: "[Kill] 3(7) · [Friedhof] 1(3)", Klammer = Account (Option).
-- Schlüssel ist die NPC-ID aus der GUID, wie in Core/Collect/Kills.lua und Core/Collect/Deaths.lua.
-- Position: Zeile Name/Stufe (rechtes Feld oder an den Text angehängt) oder eigene Zeile (Blizzard-Ende oder
-- Glimpse-Bereich). Geht Name/Stufe nicht sicher (Secret, Feld belegt, Zeile fehlt), Fallback auf eigene Zeile.

local KILL_ICON = "|TInterface\\CURSOR\\Attack:12|t" -- in allen Clients vorhanden
local DEATH_ICON = "|A:poi-graveyard-neutral:14:14|a"
local COLOR = { kills = "|cffd0d0d0", killsAccount = "|cff808080", deaths = "|cffff5555", deathsAccount = "|cff994040", separator = "|cffffffff" }

function S:ShowsTooltipKills()
    return self.account.tooltipKills ~= false
end

function S:ShowsTooltipDeaths()
    return self.account.tooltipDeaths ~= false
end

function S:ShowsTooltipAccount()
    return self.account.tooltipAccount == true
end

--- "name" (Standard), "level" oder "line"
function S:TooltipKillsMode()
    local mode = self.account.tooltipKillsMode
    return (mode == "level" or mode == "line") and mode or "name"
end

--- Für "line": "blizzard" (Standard, Tooltip-Ende) oder "glimpse" (Anfang des Glimpse-Bereichs)
function S:TooltipLineFrame()
    return self.account.tooltipLineFrame == "glimpse" and "glimpse" or "blizzard"
end

--- Für "name"/"level": "right" (Standard, rechtes Textfeld) oder "left" (an den Zeilentext angehängt)
function S:TooltipSide()
    return self.account.tooltipSide == "left" and "left" or "right"
end

-- Name und Zeilenzahl, nil wenn nicht lesbar (Secret)
local function LineCount(tooltip)
    if type(tooltip) ~= "table" or not tooltip.GetName then return nil end
    local name = tooltip:GetName()
    local count = tooltip.NumLines and tooltip:NumLines()
    if not name or type(count) ~= "number" or Glimpse:IsSecret(count) then return nil end
    return name, count
end

-- Ändert den Zeilentext, daher nur bei lesbarem Text. false -> Fallback eigene Zeile.
local function AppendToLine(tooltip, index, text)
    local ok, done = pcall(function()
        local name, count = LineCount(tooltip)
        if not name or count < index then return false end

        local line = _G[name .. "TextLeft" .. index]
        if not (line and line.GetText and line.SetText) then return false end

        local current = line:GetText()
        -- Secrets dürfen weder verglichen noch verkettet werden
        if Glimpse:IsSecret(current) or type(current) ~= "string" or current == "" then return false end
        if current:find(text, 1, true) then return true end -- Tooltip erneut verarbeitet

        line:SetText(current .. " " .. text)
        if tooltip.Show then tooltip:Show() end -- Größe neu berechnen
        return true
    end)
    return ok and done == true
end

-- Nur in ein leeres, lesbares rechtes Feld; wird der Text danach nicht angezeigt, wieder entfernen.
-- false -> Fallback eigene Zeile.
local function SetRightText(tooltip, index, text)
    local ok, done = pcall(function()
        local name, count = LineCount(tooltip)
        if not name or count < index then return false end

        local left, right = _G[name .. "TextLeft" .. index], _G[name .. "TextRight" .. index]
        if not (left and right and right.GetText and right.SetText) then return false end

        local current = right:GetText()
        if current ~= nil and (Glimpse:IsSecret(current) or type(current) ~= "string") then return false end
        if current == text then return true end -- Tooltip erneut verarbeitet
        if current ~= nil and current ~= "" then return false end -- von anderem Addon belegt

        right:SetText(text)
        if right.Show then right:Show() end
        if tooltip.Show then tooltip:Show() end -- Größe neu berechnen

        if right.IsShown and not right:IsShown() then
            right:SetText("")
            return false
        end
        return true
    end)
    return ok and done == true
end

-- Schutz gegen doppelte Zeile bei erneuter Verarbeitung
local function HasLine(tooltip, text)
    local name, count = LineCount(tooltip)
    if not name then return false end

    for index = count, 1, -1 do
        local line = _G[name .. "TextLeft" .. index]
        local current = line and line.GetText and line:GetText()
        if type(current) == "string" and not Glimpse:IsSecret(current) and current == text then return true end
    end
    return false
end

local function AddBlizzardLine(tooltip, text, r, g, b)
    if type(tooltip) ~= "table" or not tooltip.AddLine then return false end

    local ok = pcall(function()
        if HasLine(tooltip, text) then return end
        tooltip:AddLine(text, r, g, b)

        if tooltip.Show then tooltip:Show() end
    end)
    return ok
end

-- Blizzard-Ende, sonst (gewählt oder nicht möglich) Glimpse-Bereich
local function AddOwnLine(self, tooltip, text, fallback)
    local r, g, b = 0.6, 0.6, 0.6
    if self:TooltipLineFrame() == "blizzard" and AddBlizzardLine(tooltip, text, r, g, b) then return end
    if HasLine(tooltip, text) then return end

    fallback[#fallback + 1] = { text, nil, r, g, b }
    fallback[#fallback + 1] = { " " }
end

-- "[Symbol] 3(7)", Klammer nur mit showAccount
local function Part(icon, mine, all, showAccount, color, accountColor)
    local text = format("%s %s%d|r", icon, color, mine)
    if showAccount then text = text .. format("%s(%d)|r", accountColor, all) end
    return text
end

S.KILL_ICON, S.DEATH_ICON = KILL_ICON, DEATH_ICON -- für Core/Options.lua

--- Vorschau für die Optionen, feste Beispielzahlen
function S:ExampleCounterText()
    local showAccount = self:ShowsTooltipAccount()
    return table.concat({
        Part(KILL_ICON, 3, 7, showAccount, COLOR.kills, COLOR.killsAccount),
        Part(DEATH_ICON, 1, 3, showAccount, COLOR.deaths, COLOR.deathsAccount),
    }, COLOR.separator .. " · |r")
end

--- nil, wenn nichts zu zeigen ist.
function S:CreatureCounterText(id)
    local showAccount = self:ShowsTooltipAccount()
    local parts = {}
    -- mit showAccount auch "0(5)", wenn nur andere Charaktere gezählt haben
    local function shows(mine, all) return mine > 0 or (showAccount and all > 0) end

    if self:ShowsTooltipKills() then
        local mine, all = self:GetSub("kills", id, "char"), self:GetSub("kills", id, "account")
        all = math.max(all, mine)
        if shows(mine, all) then parts[#parts + 1] = Part(KILL_ICON, mine, all, showAccount, COLOR.kills, COLOR.killsAccount) end
    end
    if self:ShowsTooltipDeaths() then
        local mine, all = self:GetSub("deaths", id, "char"), self:GetSub("deaths", id, "account")
        all = math.max(all, mine)
        if shows(mine, all) then parts[#parts + 1] = Part(DEATH_ICON, mine, all, showAccount, COLOR.deaths, COLOR.deathsAccount) end
    end

    if #parts == 0 then return nil end
    return table.concat(parts, COLOR.separator .. " · |r")
end

--- data ist bereinigt: data.guid ist String oder nil.
function S:UnitTooltipLines(data, tooltip)
    if not (self:ShowsTooltipKills() or self:ShowsTooltipDeaths()) then return nil end

    local guid = type(data) == "table" and data.guid
    if type(guid) ~= "string" then return nil end

    local kind, id = S.ParseGUID(guid)
    if kind ~= "Creature" or not id then return nil end

    local text = self:CreatureCounterText(id)
    if not text then return nil end

    local mode = self:TooltipKillsMode()
    if mode == "name" or mode == "level" then
        local index = mode == "name" and 1 or 2
        local placed
        if self:TooltipSide() == "left" then placed = AppendToLine(tooltip, index, text) else placed = SetRightText(tooltip, index, text) end
        if placed then return nil end
    end

    local fallback = {}
    AddOwnLine(self, tooltip, text, fallback)
    return #fallback > 0 and fallback or nil
end

--- Läuft nach Blizzard, vor den Zeilen-Providern, damit Glimpse-Zeilen oben im Glimpse-Bereich landen.
function S:UnitTooltipHandler(tooltip, data)
    if type(data) ~= "table" or Glimpse:IsSecret(data) then return end
    if _G.TooltipUtil and _G.TooltipUtil.SurfaceArgs then pcall(_G.TooltipUtil.SurfaceArgs, data) end

    local guid = data.guid
    if type(guid) ~= "string" or Glimpse:IsSecret(guid) then return end

    local lines = self:UnitTooltipLines({ guid = guid }, tooltip)
    for _, line in ipairs(lines or {}) do
        Glimpse:AddTooltipLine(tooltip, line[1], line[2], line[3], line[4], line[5])
    end
end

--- false, wenn der Client keine Tooltip-Daten-API hat.
function S:RegisterTooltips()
    if not (Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit and self.RegisterTooltip) then return false end
    local ok = pcall(self.RegisterTooltip, self, Enum.TooltipDataType.Unit, "UnitTooltipHandler")
    return ok
end
