local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Startwerte aus den Blizzard-Statistiken (Core/Baseline/Blizzard.lua), einmal je Charakter, nur Gesamtzähler:
--   1197 Siege insgesamt                -> kills
--   60   Tode insgesamt                 -> deaths
--   1456 Fische und andere Angelbeute   -> fishing.catches
--
-- char: baseline[key], baselineDone (Reset löscht beides, nächster Login liest neu).
-- account: baseline[key] = Summe; nach Account-Reset (Startwert und Zähler 0) beim Login neu übernommen.
-- Startwert = Blizzard-Wert minus bereits selbst gezählt, sonst doppelt. "--" gilt als nicht gelesen.

local api = S.api

local SOURCES = {
    { stat = 1197, key = "kills" },
    { stat = 60, key = "deaths" },
    { stat = 1456, key = "fishing.catches" },
}
S.BASELINE_SOURCES = SOURCES

local COUNT_MAX = S.COUNT_MAX
local ATTEMPT_DELAYS = { 5, 20, 60 } -- Client-Statistik ist nach Login nicht sofort da

--- "389", "1,234", "1.234" -> Zahl; nil für "--", Gold ("55 67") und Text mit Zusatz
function S.ParseStatistic(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" or not value:match("^%d[%d%.,]*$") then return nil end
    return tonumber((value:gsub("[%.,]", "")))
end

local function ReadStatistic(statID)
    local fn = _G.GetStatistic
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, statID)
    if not ok then return nil end
    return S.ParseStatistic(S.Clean(value))
end

-- ohne days und Zeitstempel
local function AddBaseline(data, key, amount)
    data.baseline = data.baseline or {}
    data.totals[key] = math.min((data.totals[key] or 0) + amount, COUNT_MAX)
    data.baseline[key] = math.min((data.baseline[key] or 0) + amount, COUNT_MAX)
end

--- Idempotent. Gibt zurück, ob sich etwas geändert hat.
function S:ImportBaseline()
    local char, account = self.char, self.account
    char.baseline, account.baseline = char.baseline or {}, account.baseline or {}

    local changed, read = false, false
    for _, source in ipairs(SOURCES) do
        local key = source.key
        if not char.baselineDone then
            local value = ReadStatistic(source.stat)
            if value then
                read = true
                local extra = math.max(value - (char.totals[key] or 0), 0)
                if extra > 0 then
                    AddBaseline(char, key, extra)
                    AddBaseline(account, key, extra)
                    changed = true
                    self:DebugLog("Baseline %s: Blizzard %d, counted by the addon %d, added %d", key, value, value - extra, extra)
                end
            end
        elseif (account.baseline[key] or 0) == 0 and (account.totals[key] or 0) == 0 and (char.baseline[key] or 0) > 0 then
            AddBaseline(account, key, char.baseline[key])
            changed = true
            self:DebugLog("Baseline %s: account counter was empty, added %d again", key, char.baseline[key])
        end
    end

    if not char.baselineDone and read then
        char.baselineDone = true
        changed = true
    end
    if changed then self:SendMessage(self.MESSAGE_UPDATED, "baseline") end
    return changed
end

local scheduled = false

--- Mehrere Versuche nach dem Login, siehe ATTEMPT_DELAYS.
function S:StartBaseline()
    if scheduled or not api.After then return end
    scheduled = true
    for _, delay in ipairs(ATTEMPT_DELAYS) do
        api.After(delay, function() S.Protected("Baseline", S.ImportBaseline, S) end)
    end
end

function S:BaselineStatusLine()
    local mine, all = {}, {}
    for _, source in ipairs(SOURCES) do
        mine[#mine + 1] = format("%s=%d", source.key, (self.char.baseline or {})[source.key] or 0)
        all[#all + 1] = format("%s=%d", source.key, (self.account.baseline or {})[source.key] or 0)
    end
    return format("baseline (Blizzard statistics from before the addon): character %s [%s], account [%s]",
        self.char.baselineDone and "read" or "not read yet", table.concat(mine, " "), table.concat(all, " "))
end
