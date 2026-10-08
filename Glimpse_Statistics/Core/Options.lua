local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Als Funktion gebaut, damit die Zahlen beim Öffnen aktuell sind.
local function BuildMain(self)
    -- Tooltip-Optionen nur aktiv, wenn Kills oder Tode angezeigt werden
    local function tooltipOff() return not (self:ShowsTooltipKills() or self:ShowsTooltipDeaths()) end

    return {
        overview = {
            type = "group", inline = true, order = 1, name = L["Statistics"],
            args = {
                text = {
                    type = "description", order = 1, fontSize = "medium",
                    name = function()
                        local lines = self:OverviewLines()
                        if #lines == 0 then return L["Nothing counted yet. Kills, fishing and gathering are counted automatically from now on."] end
                        return table.concat(lines, "\n")
                    end,
                },
                hint = {
                    type = "description", order = 2, fontSize = "small",
                    name = "|cff999999" .. L["More with /gli stats (Account: /gli stats account, details: /gli stats <counter>)."] .. "|r",
                },
            },
        },
        collect = {
            type = "group", inline = true, order = 1.5, name = L["Counting"],
            args = {
                enabled = {
                    type = "toggle", order = 1, width = "full", name = L["Count automatically"],
                    desc = L["Counts kills, fishing, gathering and skinning while you play. Switching it off stops counting; nothing is deleted."],
                    get = function() return self:IsCollecting() end,
                    set = function(_, value) self.account.collect = value and true or false end,
                },
            },
        },
        tooltip = {
            type = "group", inline = true, order = 1.7, name = L["Tooltips"],
            args = {
                example = {
                    type = "description", order = 0.5, fontSize = "medium", width = "full",
                    name = function()
                        return format("%s\n%s %s\n%s %s\n%s",
                            L["Example:"] .. "  |cffffd100" .. L["Wild Boar"] .. "|r " .. self:ExampleCounterText(),
                            S.KILL_ICON, L["How often you have killed it"],
                            S.DEATH_ICON, L["How often it has killed you"],
                            "|cff999999" .. L["First the number of this character, in brackets the account (if switched on)."] .. "|r")
                    end,
                },
                kills = {
                    type = "toggle", order = 1, width = "full", name = L["Show kills in creature tooltips"],
                    desc = L["Shows how often you have killed a creature, with a symbol, next to its name or in the tooltip."],
                    get = function() return self:ShowsTooltipKills() end,
                    set = function(_, value) self.account.tooltipKills = value and true or false end,
                },
                deaths = {
                    type = "toggle", order = 1.5, width = "full", name = L["Show deaths in creature tooltips"],
                    desc = L["Shows how often a creature has killed you, in red with a graveyard symbol. Who killed you is an estimate: the enemy that attacked you last."],
                    get = function() return self:ShowsTooltipDeaths() end,
                    set = function(_, value) self.account.tooltipDeaths = value and true or false end,
                },
                account = {
                    type = "toggle", order = 1.6, width = "full", name = L["Also show account values"],
                    desc = L["Adds the numbers of all your characters in brackets, e.g. 3(7) for 3 kills, 7 on the account, in a darker color."],
                    get = function() return self:ShowsTooltipAccount() end,
                    set = function(_, value) self.account.tooltipAccount = value and true or false end,
                    disabled = tooltipOff,
                },
                mode = {
                    type = "select", order = 2, name = L["Position 1"], style = "dropdown",
                    desc = L["Where the numbers stand: at the name (line 1), at the level (line 2) or in an own line. If that is not possible, the own line is used."],
                    values = { name = L["Next to the name"], level = L["Next to the level"], line = L["Own line"] },
                    sorting = { "name", "level", "line" },
                    get = function() return self:TooltipKillsMode() end,
                    set = function(_, value) self.account.tooltipKillsMode = value end,
                    disabled = tooltipOff,
                },
                position2 = {
                    type = "select", order = 3, name = L["Position 2"], style = "dropdown",
                    desc = L["Next to the name or level: left (behind the text of the line) or right (right-aligned, the text of the line stays unchanged). Own line: Blizzard frame (a line at the end of the tooltip) or Glimpse frame (at the start of the Glimpse area below the separator line, followed by an empty line)."],
                    values = function()
                        if self:TooltipKillsMode() == "line" then
                            return { blizzard = L["Blizzard frame"], glimpse = L["Glimpse frame"] }
                        end
                        return { left = L["Left"], right = L["Right"] }
                    end,
                    get = function()
                        if self:TooltipKillsMode() == "line" then return self:TooltipLineFrame() end
                        return self:TooltipSide()
                    end,
                    set = function(_, value)
                        if self:TooltipKillsMode() == "line" then
                            self.account.tooltipLineFrame = value == "glimpse" and "glimpse" or "blizzard"
                        else
                            self.account.tooltipSide = value == "left" and "left" or "right"
                        end
                    end,
                    disabled = tooltipOff,
                },
            },
        },
        backup = {
            type = "group", inline = true, order = 2, name = L["Backup"],
            args = {
                export = {
                    type = "execute", order = 1, name = L["Export"],
                    desc = L["Shows all counters (account and characters) as text to copy."],
                    func = function() self:ShowExport() end,
                },
                import = {
                    type = "execute", order = 2, name = L["Import"],
                    desc = L["Paste an exported text to merge it into your counters or to restore a backup."],
                    func = function() self:ShowImport() end,
                },
            },
        },
        reset = {
            type = "group", inline = true, order = 3, name = L["Reset"],
            args = {
                char = {
                    type = "execute", order = 1, name = L["Reset this character"],
                    desc = L["Deletes all counters of this character. Account counters stay."],
                    confirm = true, confirmText = L["Really delete all counters of this character?"],
                    func = function() self:Reset("char") end,
                },
                account = {
                    type = "execute", order = 2, name = L["Reset account"],
                    desc = L["Deletes all account counters. Character counters stay."],
                    confirm = true, confirmText = L["Really delete all account counters?"],
                    func = function() self:Reset("account") end,
                },
            },
        },
    }
end

local function BuildWindow(self)
    return {
        text = {
            type = "description", order = 1, fontSize = "medium", width = "full",
            name = L["The statistics window shows the same overview as this page. Open or close it with /gli stats window. Without a frame: move it with the left mouse button, change its size at the corner at the bottom right, close it with the right mouse button or the small x. It stays open when you close the options."],
        },
        frame = {
            type = "toggle", order = 2, width = "full", name = L["Show frame"],
            desc = L["Shows the window with title bar, border and close button instead of plain text. Both can be resized."],
            get = function() return self:ShowsWindowFrame() end,
            set = function(_, value)
                self.account.windowFrame = value and true or false
                self:ApplyWindowStyle()
            end,
        },
        fontSize = {
            type = "range", order = 2.5, width = "full", name = L["Font size"],
            min = S.FONT_SIZE_MIN, max = S.FONT_SIZE_MAX, step = 1,
            get = function() return self:WindowFontSize() end,
            set = function(_, value)
                self.account.windowFontSize = value
                self:ApplyWindowFont()
            end,
        },
        scope = {
            type = "select", order = 3, style = "radio", width = "full", name = L["Show in the window"],
            values = { all = L["Everything (character and account)"], char = L["Only this character"] },
            get = function() return self:WindowScope() end,
            set = function(_, value)
                self.account.windowScope = value == "char" and "char" or "all"
                self:RefreshWindow()
            end,
        },
        open = {
            type = "execute", order = 4, name = L["Open window"],
            func = function() self:ToggleWindow(true) end,
        },
        reset = {
            type = "execute", order = 5, name = L["Reset position and size"],
            desc = L["Puts the window back to its default position and size."],
            func = function() self:ResetWindowLayout() end,
        },
    }
end

function S:BuildOptions()
    return {
        options = { type = "group", order = 1, name = L["Options"], args = BuildMain(self) },
        window = { type = "group", order = 2, name = L["Window"], args = BuildWindow(self) },
    }
end
