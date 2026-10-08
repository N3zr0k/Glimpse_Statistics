local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- UI zu Core/Transfer/Transfer.lua. Nur ein Fenster, ein neuer Aufruf ersetzt das offene.

local AceGUI = LibStub("AceGUI-3.0")

local window

local function CloseWindow()
    if window then
        AceGUI:Release(window)
        window = nil
    end
end

local function ErrorText(key)
    local texts = {
        empty = L["Nothing to import. Paste the exported text first."],
        tooLarge = L["The text is too long."],
        notExport = L["This is not an export of Glimpse: Statistics."],
        formatNewer = L["The export was made by a newer version of the addon. Please update the addon."],
        unsupported = L["The export is compressed, but the compression library is missing."],
        damaged = L["The text is damaged or incomplete. Was it copied completely?"],
        duplicate = L["This export has already been imported (or was made on this account)."],
    }
    return texts[key] or tostring(key)
end

local function SummaryText(info)
    local text = format(L["Imported: %d counters, %d characters."], info.counters, info.chars)
    if info.removed > 0 then text = text .. " " .. format(L["Removed entries: %d."], info.removed) end
    return text
end

local function RunImport(text, mode, edit)
    local ok, result = S:ImportData(text, mode)
    if ok then
        Glimpse:Print(SummaryText(result))
        if window then window:SetStatusText(SummaryText(result)) end
        if edit then edit:SetText("") end
        LibStub("AceConfigRegistry-3.0"):NotifyChange(Glimpse.name .. "_" .. ADDON_NAME)
    else
        Glimpse:Print(ErrorText(result))
        if window then window:SetStatusText(ErrorText(result)) end
    end
end

StaticPopupDialogs["GLIMPSE_STATISTICS_REPLACE"] = {
    text = L["Replace ALL statistics (account and all characters) with the imported data? This cannot be undone."],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) RunImport(data.text, "replace", data.edit) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Open(title)
    CloseWindow()

    window = AceGUI:Create("Frame")
    window:SetTitle(title)
    window:SetWidth(580)
    window:SetHeight(440)
    window:SetLayout("List")
    window:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        if window == widget then window = nil end
    end)
    return window
end

local function AddLabel(parent, text)
    local label = AceGUI:Create("Label")
    label:SetText(text)
    label:SetFullWidth(true)
    parent:AddChild(label)
end

local function AddEditBox(parent)
    local edit = AceGUI:Create("MultiLineEditBox")
    edit:SetLabel("")
    edit:SetFullWidth(true)
    edit:SetNumLines(14)
    edit:DisableButton(true)
    parent:AddChild(edit)
    return edit
end

function S:ShowExport()
    local text, info = self:ExportData()

    local frame = Open(L["Export statistics"])
    frame:SetStatusText(format(L["%d counters, %d characters, %d characters of text"], info.counters, info.chars, info.length))
    AddLabel(frame, L["Select the text (Ctrl+A), copy it (Ctrl+C) and keep it somewhere safe. It contains the account and all characters."])

    local edit = AddEditBox(frame)
    edit:SetText(text)
    -- HighlightText greift erst nach dem Layout
    C_Timer.After(0.1, function()
        if window == frame and edit.editBox then
            edit.editBox:HighlightText()
            edit:SetFocus()
        end
    end)
end

function S:ShowImport()
    local frame = Open(L["Import statistics"])
    AddLabel(frame, L["Paste the exported text here. Merge adds the numbers to your counters, Replace deletes all counters first (use it to restore a backup)."])

    local edit = AddEditBox(frame)

    local group = AceGUI:Create("SimpleGroup")
    group:SetFullWidth(true)
    group:SetLayout("Flow")
    frame:AddChild(group)

    local merge = AceGUI:Create("Button")
    merge:SetText(L["Merge"])
    merge:SetWidth(160)
    merge:SetCallback("OnClick", function() RunImport(edit:GetText(), "merge", edit) end)
    group:AddChild(merge)

    local replace = AceGUI:Create("Button")
    replace:SetText(L["Replace"])
    replace:SetWidth(160)
    replace:SetCallback("OnClick", function()
        StaticPopup_Show("GLIMPSE_STATISTICS_REPLACE", nil, nil, { text = edit:GetText(), edit = edit })
    end)
    group:AddChild(replace)
end

--- Kopierfenster für beliebigen Text, z. B. Blizzard-Dump.
function S:ShowText(title, text)
    local frame = Open(title)
    frame:SetStatusText(format("%d characters", #text))
    AddLabel(frame, "Select the text (Ctrl+A) and copy it (Ctrl+C).")

    local edit = AddEditBox(frame)
    edit:SetText(text)
    C_Timer.After(0.1, function()
        if window == frame and edit.editBox then
            edit.editBox:HighlightText()
            edit:SetFocus()
        end
    end)
end
