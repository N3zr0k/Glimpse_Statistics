local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L
local ADDON_NAME = "Glimpse_Statistics"

-- Statistikfenster (/gli stats window) mit S:OverviewSections. Jede Gruppe hat eine Überschrift zum Ein- und Ausklappen
-- (Zustand je Charakter in windowCollapsed). Zwei Varianten:
--   ohne Rahmen (Standard)  nur Text; Links ziehen, Ecke = Größe, Rechtsklick oder x schließt, Mausrad scrollt
--   mit Rahmen              AceGUI-Frame
-- Beide werden nur versteckt, nie freigegeben. Bewusst nicht in UISpecialFrames, damit Escape es nicht schließt.

local AceGUI = LibStub("AceGUI-3.0")

local FRAME_NAME = "GlimpseStatisticsWindow"
local REFRESH_DELAY = 0.5 -- Zähler ändern sich oft in Serie
local PAD = 8             -- Innenabstand ohne Rahmen
local CLOSE_SPACE = 14    -- Platz für das x
local MIN_WIDTH, MIN_HEIGHT = 120, 40
local FONT_MIN, FONT_MAX, FONT_DEFAULT = 8, 24, 12

local plain  -- { frame, text, close, grip }
local framed -- { frame, scroll, label }
local pending = false

-- Einstellungen aus Statistics.lua: Aussehen je Profil, Position und Zustand je Charakter
local function Profile() return S.settings.profile end
local function Char() return S.settings.char end

--- "all" (Standard) oder "char"
function S:WindowScope()
    return Profile().windowScope == "char" and "char" or "all"
end

function S:ShowsWindowFrame()
    return Profile().windowFrame == true
end

--- 8 bis 24, Standard 12
function S:WindowFontSize()
    local size = tonumber(Profile().windowFontSize) or FONT_DEFAULT
    return math.min(math.max(math.floor(size + 0.5), FONT_MIN), FONT_MAX)
end
S.FONT_SIZE_MIN, S.FONT_SIZE_MAX = FONT_MIN, FONT_MAX

--- Ohne Daten ein Hinweistext.
function S:WindowText()
    local charOnly = self:WindowScope() == "char"
    if not self:HasData(charOnly) then
        return charOnly and L["No data has been collected for this character yet."] or L["No data has been collected yet."]
    end
    return table.concat(self:OverviewLines(false, charOnly), "\n")
end

--- Hinweis statt Übersicht, wenn es keine Daten gibt, sonst nil.
function S:WindowHint()
    local charOnly = self:WindowScope() == "char"
    if self:HasData(charOnly) then return nil end
    return charOnly and L["No data has been collected for this character yet."] or L["No data has been collected yet."]
end

function S:IsGroupCollapsed(group)
    return Char().windowCollapsed ~= nil and Char().windowCollapsed[group] == true
end

--- Klappt eine Gruppe ein oder aus und zeichnet das Fenster neu.
function S:ToggleGroup(group)
    Char().windowCollapsed = Char().windowCollapsed or {}
    Char().windowCollapsed[group] = not self:IsGroupCollapsed(group) or nil
    self:RefreshWindow()
end

--- Überschrift mit Zeichen für den Zustand: [-] offen, [+] eingeklappt
local function Heading(group)
    return format("|cffffd100%s %s|r", S:IsGroupCollapsed(group) and "[+]" or "[-]", group)
end

-- Nur Aktionen des Spielers merken, nicht Verstecken durch das Spiel (z. B. Alt+Z).
local function Remember(open)
    Char().windowOpen = open and true or false
end

-- Spielschrift, nur die Größe ist einstellbar
local function ApplyFont(fontString, setter)
    local base = _G.GameFontHighlight or _G.GameFontHighlightSmall
    local path, _, flags
    if base and base.GetFont then path, _, flags = base:GetFont() end
    if path then setter(fontString, path, S:WindowFontSize(), flags) end
end

-- ---------------------------------------------------------------------------
-- Ohne Rahmen
-- ---------------------------------------------------------------------------

local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    if point then Char().windowPos = { point = point, relPoint = relPoint, x = x, y = y } end
end

local function RestorePosition(frame)
    local pos = Char().windowPos
    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -200)
    end
end

local function MaxScroll()
    return math.max((plain.height or 0) - (plain.scroll:GetHeight() or 0), 0)
end

local function UpdateScroll()
    if not plain then return end
    local content = plain.height or 0
    plain.content:SetHeight(math.max(content, 1))

    local max = MaxScroll()
    local pos = math.min(plain.scroll:GetVerticalScroll() or 0, max)
    plain.scroll:SetVerticalScroll(pos)

    local thumb = plain.thumb
    if not thumb then return end
    local view = plain.scroll:GetHeight() or 0
    if max <= 0 or view <= 0 or content <= 0 then
        thumb:Hide()
        return
    end
    local height = math.max(view * view / content, 12)
    thumb:SetHeight(height)
    thumb:SetPoint("TOPRIGHT", plain.frame, "TOPRIGHT", -4, -(PAD + CLOSE_SPACE) - (pos / max) * (view - CLOSE_SPACE - height))
    thumb:Show()
end

--- delta > 0 nach oben.
function S:ScrollWindow(delta)
    if not (plain and plain.frame:IsShown()) then return end
    local pos = (plain.scroll:GetVerticalScroll() or 0) - (delta or 0) * self:WindowFontSize() * 3
    plain.scroll:SetVerticalScroll(math.min(math.max(pos, 0), MaxScroll()))
    UpdateScroll()
end

-- Nur solange der Spieler keine eigene Größe gewählt hat
local function AutoSize()
    if Char().windowSize then return end
    local width = math.max(plain.widest or 0, 80)
    local height = math.max(plain.height or 0, 12)
    -- max. 60 % der Bildschirmhöhe, Rest scrollt
    if UIParent and UIParent.GetHeight then height = math.min(height, (UIParent:GetHeight() or height) * 0.6) end
    plain.frame:SetSize(width + 2 * PAD + CLOSE_SPACE + 2, height + 2 * PAD)
end

local function BuildPlain()
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    end
    frame:SetClipsChildren(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            Remember(false)
            self:Hide()
        end
    end)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PAD + CLOSE_SPACE), PAD)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    ApplyFont(text, text.SetFont)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) S:ScrollWindow(delta) end)

    -- Scrollposition, nur sichtbar wenn scrollbar
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    if thumb then
        thumb:SetWidth(2)
        thumb:SetColorTexture(1, 1, 1, 0.3)
        thumb:Hide()
    end

    -- neu umbrechen und Scrollposition begrenzen
    frame:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then
            local textWidth = math.max(width - 2 * PAD - CLOSE_SPACE, 1)
            content:SetWidth(textWidth)
            S:RefreshWindow()
        end
    end)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(14, 14)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    close:SetAlpha(0.35)
    local mark = close:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mark:SetPoint("CENTER")
    mark:SetText("x")
    close:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    close:SetScript("OnLeave", function(self) self:SetAlpha(0.35) end)
    close:SetScript("OnClick", function()
        Remember(false)
        frame:Hide()
    end)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    grip:SetAlpha(0.35)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    grip:SetScript("OnLeave", function(self) self:SetAlpha(0.35) end)
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
        Char().windowSize = { width = frame:GetWidth(), height = frame:GetHeight() }
    end)

    plain = { frame = frame, scroll = scroll, content = content, text = text, close = close, grip = grip, thumb = thumb,
        rows = {}, height = 0, widest = 0 }
    RestorePosition(frame)
    local size = Char().windowSize
    if type(size) == "table" and size.width and size.height then frame:SetSize(size.width, size.height) end
    return plain
end

-- Eine Zeile je Gruppe: Überschrift (Knopf) und Text darunter
local function PlainRow(index)
    local row = plain.rows[index]
    if row then return row end
    local button = CreateFrame("Button", nil, plain.content)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    button:SetScript("OnClick", function(self) S:ToggleGroup(self.group) end)
    local body = plain.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    row = { button = button, label = label, body = body }
    plain.rows[index] = row
    return row
end

-- Setzt Hinweis, "Erfasst seit" und die Gruppen untereinander; plain.height und plain.widest für Größe und Scrollen
local function LayoutPlain()
    local content = plain.content
    local width = Char().windowSize and math.max(content:GetWidth() or 1, 1) or 0
    local text = plain.text
    local y, widest = 0, 0
    local function Place(fontString, anchor, value)
        ApplyFont(fontString, fontString.SetFont)
        fontString:SetText(value)
        fontString:SetWidth(width)
        fontString:ClearAllPoints()
        fontString:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -y)
        widest = math.max(widest, fontString:GetStringWidth() or 0)
        y = y + (fontString:GetStringHeight() or 0)
    end

    local hint = S:WindowHint()
    local since, sections
    if not hint then since, sections = S:OverviewSections(false, S:WindowScope() == "char") end
    if hint or since then Place(text, content, hint or since) else text:SetText("") end
    text:Show()

    local used = 0
    for _, section in ipairs(sections or {}) do
        used = used + 1
        local row = PlainRow(used)
        row.button.group = section.group
        Place(row.label, content, Heading(section.group))
        row.button:ClearAllPoints()
        row.button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y - (row.label:GetStringHeight() or 0)))
        row.button:SetSize(math.max(width, row.label:GetStringWidth() or 0, 1), math.max(row.label:GetStringHeight() or 0, 1))
        row.button:Show()
        if S:IsGroupCollapsed(section.group) then
            row.body:Hide()
        else
            Place(row.body, content, table.concat(section.lines, "\n"))
            row.body:Show()
        end
    end
    for index = used + 1, #plain.rows do
        plain.rows[index].button:Hide()
        plain.rows[index].body:Hide()
    end
    plain.height, plain.widest = y, widest
end

-- ---------------------------------------------------------------------------
-- Mit Rahmen (AceGUI)
-- ---------------------------------------------------------------------------

local function BuildFramed()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle((Glimpse.GetMeta and Glimpse:GetMeta("Title", ADDON_NAME)) or L["Statistics"])
    frame:SetWidth(460)
    frame:SetHeight(420)
    frame:SetLayout("Fill")
    if Char().windowStatus then frame:SetStatusTable(Char().windowStatus) end

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    frame:AddChild(scroll)

    -- Hook am Knopf statt OnHide, da OnHide auch beim Verstecken durch das Spiel kommt
    if type(frame.closebutton) == "table" and frame.closebutton.HookScript then
        frame.closebutton:HookScript("OnClick", function() Remember(false) end)
    end

    framed = { frame = frame, scroll = scroll }
    frame.frame:Show()
    return framed
end

-- Text oder Überschrift als AceGUI-Label in den Scrollbereich
local function AddLabel(kind, value)
    local label = AceGUI:Create(kind)
    label:SetFullWidth(true)
    ApplyFont(label, label.SetFont)
    label:SetText(value)
    framed.scroll:AddChild(label)
    return label
end

-- Hinweis oder "Erfasst seit", darunter je Gruppe eine anklickbare Überschrift und ihr Text
local function FillFramed()
    framed.scroll:ReleaseChildren()
    local hint = S:WindowHint()
    if hint then
        AddLabel("Label", hint)
        return
    end
    local since, sections = S:OverviewSections(false, S:WindowScope() == "char")
    if since then AddLabel("Label", since) end
    for _, section in ipairs(sections) do
        local header = AddLabel("InteractiveLabel", Heading(section.group))
        header:SetCallback("OnClick", function() S:ToggleGroup(section.group) end)
        if not S:IsGroupCollapsed(section.group) then AddLabel("Label", table.concat(section.lines, "\n")) end
    end
end

-- ---------------------------------------------------------------------------
-- Gemeinsam
-- ---------------------------------------------------------------------------

local function PlainOpen()
    return plain ~= nil and plain.frame:IsShown()
end

local function FramedOpen()
    return framed ~= nil and framed.frame.frame:IsShown()
end

local function IsOpen()
    return PlainOpen() or FramedOpen()
end

function S:RefreshWindow()
    if PlainOpen() then
        LayoutPlain()
        AutoSize()
        UpdateScroll()
    end
    if FramedOpen() then
        FillFramed()
        framed.scroll:DoLayout()
    end
end

function S:IsWindowOpen()
    return IsOpen()
end

function S:ApplyWindowFont()
    self:RefreshWindow()
end

local function CloseAll()
    if plain then plain.frame:Hide() end
    if framed then framed.frame.frame:Hide() end
end

local function OpenCurrent()
    if S:ShowsWindowFrame() then
        if not framed then BuildFramed() else framed.frame.frame:Show() end
    else
        if not plain then BuildPlain() end
        plain.frame:Show()
    end
    S:RefreshWindow()
end

--- show nil = umschalten. Gibt zurück, ob es danach offen ist.
function S:ToggleWindow(show)
    if show == nil then show = not IsOpen() end
    Remember(show)

    if show then
        -- offenes Fenster der anderen Variante schließen
        if self:ShowsWindowFrame() and PlainOpen() then plain.frame:Hide() end
        if not self:ShowsWindowFrame() and FramedOpen() then framed.frame.frame:Hide() end
        OpenCurrent()
    else
        CloseAll()
    end
    return IsOpen()
end

--- Beide Varianten, wirkt sofort.
function S:ResetWindowLayout()
    Char().windowPos, Char().windowSize = nil, nil
    if Char().windowStatus then wipe(Char().windowStatus) end

    local open = IsOpen()
    if open then CloseAll() end
    if plain then RestorePosition(plain.frame) end
    if open then OpenCurrent() end
end

--- Nach Änderung der Option "Rahmen zeigen".
function S:ApplyWindowStyle()
    if not IsOpen() then return end
    CloseAll()
    OpenCurrent()
end

-- Nach Änderungen in Database (Statistics.lua), gedrosselt auf REFRESH_DELAY
function S:OnCountersChanged()
    if pending or not IsOpen() then return end
    pending = true
    C_Timer.After(REFRESH_DELAY, function()
        pending = false
        S:RefreshWindow()
    end)
end

--- Login und /reload: öffnet das Fenster wieder, wenn es offen war.
function S:RestoreWindow()
    if Char().windowOpen then self:ToggleWindow(true) end
end
