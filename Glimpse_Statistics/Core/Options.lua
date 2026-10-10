local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Als Funktion gebaut, damit die Zahlen beim Öffnen aktuell sind.
local function BuildMain(self)
    return {
        overview = {
            type = "group", inline = true, order = 1, name = L["Statistics"],
            args = {
                text = {
                    type = "description", order = 1, fontSize = "medium",
                    name = function()
                        local lines = self:OverviewLines()
                        if #lines == 0 then return L["Nothing counted yet."] end
                        return table.concat(lines, "\n")
                    end,
                },
                hint = {
                    type = "description", order = 2, fontSize = "small",
                    name = "|cff999999" .. L["More with /gli stats (Account: /gli stats account, details: /gli stats <counter>)."] .. "|r",
                },
            },
        },
        source = {
            type = "group", inline = true, order = 2, name = L["Data"],
            args = {
                text = {
                    type = "description", order = 1, fontSize = "medium",
                    name = L["Statistics only shows the numbers. They are recorded by Glimpse (combat and travel), Glimpse: Professions (fishing) and Glimpse: Gathering (gathering and skinning) and stored in Glimpse: Database. Topics of addons that are not installed are left out. Backup, transfer and reset are in the tab Data of the Glimpse options."],
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
                self.settings.profile.windowFrame = value and true or false
                self:ApplyWindowStyle()
            end,
        },
        fontSize = {
            type = "range", order = 2.5, width = "full", name = L["Font size"],
            min = S.FONT_SIZE_MIN, max = S.FONT_SIZE_MAX, step = 1,
            get = function() return self:WindowFontSize() end,
            set = function(_, value)
                self.settings.profile.windowFontSize = value
                self:ApplyWindowFont()
            end,
        },
        scope = {
            type = "select", order = 3, style = "radio", width = "full", name = L["Show in the window"],
            values = { all = L["Everything (character and account)"], char = L["Only this character"] },
            get = function() return self:WindowScope() end,
            set = function(_, value)
                self.settings.profile.windowScope = value == "char" and "char" or "all"
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
