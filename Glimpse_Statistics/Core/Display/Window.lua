local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L
local ADDON_NAME = "Glimpse_Statistics"

-- Statistikfenster (/gli stats window) mit S:OverviewLines. Zwei Varianten:
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

--- "all" (Standard) oder "char"
function S:WindowScope()
    return self.account.windowScope == "char" and "char" or "all"
end

function S:ShowsWindowFrame()
    return self.account.windowFrame == true
end

--- 8 bis 24, Standard 12
function S:WindowFontSize()
    local size = tonumber(self.account.windowFontSize) or FONT_DEFAULT
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

-- Nur Aktionen des Spielers merken, nicht Verstecken durch das Spiel (z. B. Alt+Z).
local function Remember(open)
    S.char.windowOpen = open and true or false
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
    if point then S.char.windowPos = { point = point, relPoint = relPoint, x = x, y = y } end
end

local function RestorePosition(frame)
    local pos = S.char.windowPos
    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -200)
    end
end

local function MaxScroll()
    return math.max((plain.text:GetStringHeight() or 0) - (plain.scroll:GetHeight() or 0), 0)
end

local function UpdateScroll()
    if not plain then return end
    local content = plain.text:GetStringHeight() or 0
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
    if S.char.windowSize then return end
    plain.text:SetWidth(0)
    local width = math.max(plain.text:GetStringWidth() or 0, 80)
    local height = math.max(plain.text:GetStringHeight() or 0, 12)
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
            text:SetWidth(textWidth)
            UpdateScroll()
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
        S.char.windowSize = { width = frame:GetWidth(), height = frame:GetHeight() }
    end)

    plain = { frame = frame, scroll = scroll, content = content, text = text, close = close, grip = grip, thumb = thumb }
    RestorePosition(frame)
    local size = S.char.windowSize
    if type(size) == "table" and size.width and size.height then frame:SetSize(size.width, size.height) end
    return plain
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
    if S.char.windowStatus then frame:SetStatusTable(S.char.windowStatus) end

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    frame:AddChild(scroll)

    local label = AceGUI:Create("Label")
    label:SetFullWidth(true)
    ApplyFont(label, label.SetFont)
    scroll:AddChild(label)

    -- Hook am Knopf statt OnHide, da OnHide auch beim Verstecken durch das Spiel kommt
    if type(frame.closebutton) == "table" and frame.closebutton.HookScript then
        frame.closebutton:HookScript("OnClick", function() Remember(false) end)
    end

    framed = { frame = frame, scroll = scroll, label = label }
    frame.frame:Show()
    return framed
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
        ApplyFont(plain.text, plain.text.SetFont)
        plain.text:SetText(self:WindowText())
        AutoSize()
        UpdateScroll()
    end
    if FramedOpen() then
        ApplyFont(framed.label, framed.label.SetFont)
        framed.label:SetText(self:WindowText())
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
    self.char.windowPos, self.char.windowSize = nil, nil
    if self.char.windowStatus then wipe(self.char.windowStatus) end

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

-- GLIMPSE_STATISTICS_UPDATED, gedrosselt auf REFRESH_DELAY
function S:OnCountersChanged()
    if pending or not IsOpen() then return end
    pending = true
    C_Timer.After(REFRESH_DELAY, function()
        pending = false
        S:RefreshWindow()
    end)
end

--- Login und /reload. Migriert windowPos/windowSize aus den Account-Daten auf den Charakter.
function S:RestoreWindow()
    local char, account = self.char, self.account
    if not char.windowPos and account.windowPos then char.windowPos = account.windowPos end
    if not char.windowSize and account.windowSize then char.windowSize = account.windowSize end
    account.windowPos, account.windowSize = nil, nil

    if char.windowOpen then self:ToggleWindow(true) end
end

function S:RegisterWindow()
    if self.RegisterMessage then self:RegisterMessage(self.MESSAGE_UPDATED, "OnCountersChanged") end
end
