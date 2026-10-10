-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Statistikfenster (Core/Display/Window.lua) und Tab Fenster der Optionen. Einstellungen im Namespace
-- "Statistics" von Glimpse.db (S.settings), Zahlen aus Glimpse: Database.

-- Ein Rahmen, der Aufrufe nur festhält (unbekannte Methoden tun nichts)
local function fakeFrame(kind, name)
    local f = { kind = kind, name = name, scripts = {}, shown = false, points = {}, alpha = 1, state = {}, width = 200, height = 100 }
    setmetatable(f, { __index = function() return function() end end })
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetScript(event, func) self.scripts[event] = func end
    function f:HookScript(event, func) self.state.hooks = self.state.hooks or {} self.state.hooks[event] = func end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:SetAlpha(alpha) self.alpha = alpha end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:GetPoint() local p = self.points[1] return p and p[1], nil, p and p[3], p and p[4], p and p[5] end
    function f:StartMoving() self.state.moving = true end
    function f:StartSizing(corner) self.state.sizing = corner end
    function f:StopMovingOrSizing() self.state.moving, self.state.sizing = false, nil end
    function f:SetScrollChild() end
    function f:SetVerticalScroll(value) self.state.scroll = value end
    function f:GetVerticalScroll() return self.state.scroll or 0 end
    function f:CreateFontString()
        local fs = { state = {} }
        _G.fakeTexts[#_G.fakeTexts + 1] = fs
        setmetatable(fs, { __index = function() return function() end end })
        function fs:SetText(text) self.state.text = text end
        function fs:SetFont(path, size, flags) self.state.font = { path, size, flags } end
        function fs:GetStringWidth() return self.state.text and #self.state.text or 0 end
        function fs:GetStringHeight() return self.state.height or 12 end
        return fs
    end
    if name then _G[name] = f end
    return f
end

-- Ein AceGUI, das seine Widgets nur festhält
local function fakeAceGUI()
    local gui = { created = {} }
    function gui:Create(kind)
        local w = { kind = kind, state = {}, layouts = 0 }
        setmetatable(w, { __index = function() return function() end end })
        function w:SetTitle(text) self.state.title = text end
        function w:SetStatusTable(status) self.state.status = status end
        function w:SetText(text) self.state.text = text end
        function w:SetFont(path, size) self.state.font = { path, size } end
        function w:DoLayout() self.layouts = self.layouts + 1 end
        w.frame = fakeFrame("AceFrame")
        w.closebutton = fakeFrame("Button")
        gui.created[#gui.created + 1] = w
        return w
    end
    return gui
end

local function setupWindow()
    local S, Glimpse, DB, P = stub.setup()
    local frames, gui = {}, fakeAceGUI()
    _G.CreateFrame = function(kind, name)
        local f = fakeFrame(kind, name)
        frames[#frames + 1] = f
        return f
    end
    local libStub = _G.LibStub
    _G.LibStub = function(name, ...) if name == "AceGUI-3.0" then return gui end return libStub(name, ...) end
    _G.fakeTexts = {}
    _G.UIParent = {}
    _G.UISpecialFrames = {}
    _G.GameFontHighlight = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    _G.C_Timer = { After = function(_, func) func() end }
    stub.load("Core/Display/Window.lua", "Glimpse_Statistics")
    local combat = DB:Register("combat", { area = "Core", zones = true })
    return S, Glimpse, frames, gui, combat, P
end

-- Kills eines anderen eigenen Charakters, danach ist wieder der eigene eingeloggt
local function otherKills(P, combat, n)
    local char, key = P.char, P.charKey
    P.char = P.CharIndex("anderer", { name = "Zweit", realm = "Forever" })
    P.meta.characters[P.char].foreign = nil
    combat:Count("kill", 1, 12, n)
    P.char, P.charKey = char, key
end

local function cleanWindow()
    _G.UISpecialFrames, _G.GlimpseStatisticsWindow, _G.C_Timer, _G.UIParent, _G.GameFontHighlight, _G.fakeTexts = nil, nil, nil, nil, nil, nil
end

test("Fenster: Fenster ohne Rahmen öffnen, schließen, Text wie die Übersicht, nie bei Escape", function()
    local S, _, frames, gui, combat, P = setupWindow()
    combat:Count("kill", 1, 12, 3)
    otherKills(P, combat, 7)

    eq(S:ToggleWindow(), true, "öffnet")
    local frame = frames[1]
    eq(frame.name, "GlimpseStatisticsWindow", "Name")
    eq(#gui.created, 0, "ohne Rahmen kein AceGUI-Fenster")
    eq(#_G.UISpecialFrames, 0, "nicht bei Escape (sonst schließt es mit dem Optionenmenü)")
    eq(frame.points[1][1], "TOPLEFT", "Standardposition")
    assert(frame.width >= 100 and frame.height >= 25, "Größe nach dem Text")
    eq(S.settings.char.windowSize, nil, "eine eigene Größe gibt es erst nach dem Ändern")
    eq(S:IsWindowOpen(), true, "offen")

    eq(S:ToggleWindow(), false, "schließt")
    eq(frame.shown, false, "versteckt")
    eq(S:ToggleWindow(true), true, "öffnet wieder")
    eq(#frames, 6, "dasselbe Fenster, nicht neu gebaut (Rahmen, Scrollbereich, Inhalt, Gruppenknopf, x und Griff)")
    eq(S:ToggleWindow(false), false, "false schließt")
    cleanWindow()
end)

test("Fenster: Schriftgröße einstellbar und begrenzt", function()
    local S = setupWindow()
    eq(S:WindowFontSize(), 12, "Standard")
    S.settings.profile.windowFontSize = 16; eq(S:WindowFontSize(), 16, "16")
    S.settings.profile.windowFontSize = 3; eq(S:WindowFontSize(), 8, "nicht kleiner als 8")
    S.settings.profile.windowFontSize = 99; eq(S:WindowFontSize(), 24, "nicht größer als 24")
    S.settings.profile.windowFontSize = "x"; eq(S:WindowFontSize(), 12, "Unsinn: Standard")
    cleanWindow()
end)

test("Fenster: Schrift im Fenster ohne Rahmen und mit Rahmen", function()
    local S, _, frames, gui = setupWindow()
    S.settings.profile.windowFontSize = 18
    S:ToggleWindow(true)
    -- die Textfelder des Fensters ohne Rahmen
    for _, f in ipairs(frames) do
        local fs = f:CreateFontString()
        assert(fs, "Textfeld")
    end
    S.settings.profile.windowFrame = true
    S:ApplyWindowStyle()
    local label = gui.created[#gui.created]
    eq(label.state.font[2], 18, "Schriftgröße im Fenster mit Rahmen")
    eq(label.state.font[1], "Fonts\\FRIZQT__.TTF", "Schriftart der Spielschrift")
    S.settings.profile.windowFontSize = 10
    S:RefreshWindow()
    label = gui.created[#gui.created]
    eq(label.state.font[2], 10, "neue Größe sofort")
    cleanWindow()
end)

test("Fenster: ohne Rahmen verschieben, Größe ändern, Position und Größe merken, x und rechte Maustaste schließen", function()
    local S, _, frames = setupWindow()
    S:ToggleWindow(true)
    local frame, close, grip = frames[1], nil, nil
    -- Knöpfe in der Reihenfolge ihrer Erstellung: x, dann Griff
    for _, f in ipairs(frames) do
        if f.kind == "Button" then if not close then close = f else grip = f end end
    end
    assert(close and grip, "x und Griff")

    frame.scripts.OnDragStart(frame)
    eq(frame.state.moving, true, "wird verschoben")
    frame.points = { { "TOPLEFT", frame, "TOPLEFT", 120, -300 } }
    frame.scripts.OnDragStop(frame)
    eq(frame.state.moving, false, "Verschieben beendet")
    eq(S.settings.char.windowPos.x, 120, "Position gemerkt")

    grip.scripts.OnMouseDown(grip)
    eq(frame.state.sizing, "BOTTOMRIGHT", "Größe ändern")
    frame.width, frame.height = 333, 222
    grip.scripts.OnMouseUp(grip)
    eq(frame.state.sizing, nil, "beendet")
    eq(S.settings.char.windowSize.width, 333, "Breite gemerkt"); eq(S.settings.char.windowSize.height, 222, "Höhe gemerkt")

    frame.scripts.OnMouseUp(frame, "LeftButton")
    eq(frame.shown, true, "linke Maustaste schließt nicht")
    frame.scripts.OnMouseUp(frame, "RightButton")
    eq(frame.shown, false, "rechte Maustaste schließt")

    S:ToggleWindow(true)
    close.scripts.OnEnter(close); eq(close.alpha, 1, "x wird sichtbar")
    close.scripts.OnLeave(close); assert(close.alpha < 1, "x wieder blass")
    close.scripts.OnClick(close)
    eq(frame.shown, false, "x schließt")

    -- nach dem Neuladen: gemerkte Position und Größe
    local S2, _, frames2 = setupWindow()
    S2.settings.char.windowPos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 120, y = -300 }
    S2.settings.char.windowSize = { width = 333, height = 222 }
    S2:ToggleWindow(true)
    eq(frames2[1].points[1][4], 120, "Position wiederhergestellt")
    eq(frames2[1].width, 333, "Breite wiederhergestellt"); eq(frames2[1].height, 222, "Höhe wiederhergestellt")
    cleanWindow()
end)

test("Fenster: Rahmen zeigen nutzt das normale Fenster (AceGUI), Wechsel im laufenden Betrieb", function()
    local S, _, frames, gui = setupWindow()
    S:ToggleWindow(true)
    local plainFrame = frames[1]
    eq(plainFrame.shown, true, "ohne Rahmen offen")
    eq(#gui.created, 0, "noch kein AceGUI-Fenster")

    S.settings.profile.windowFrame = true
    S:ApplyWindowStyle()
    eq(plainFrame.shown, false, "der Text-Rahmen verschwindet")
    local frame, scroll, label = gui.created[1], gui.created[2], gui.created[3]
    eq(frame.kind, "Frame", "Fenster mit Titelleiste"); eq(scroll.kind, "ScrollFrame", "Scrollbereich"); eq(label.kind, "Label", "Text")
    eq(frame.frame.shown, true, "sofort sichtbar")
    eq(frame.state.status, S.settings.char.windowStatus, "Position und Größe im Account")
    eq(label.state.text, S:WindowText(), "dieselbe Übersicht wie die Optionen")
    eq(#_G.UISpecialFrames, 0, "nicht bei Escape")

    eq(S:ToggleWindow(), false, "schließt")
    eq(frame.frame.shown, false, "versteckt")
    eq(S:ToggleWindow(true), true, "öffnet im Rahmen")
    local windows = 0
    for _, widget in ipairs(gui.created) do if widget.kind == "Frame" then windows = windows + 1 end end
    eq(windows, 1, "Fenster nicht neu gebaut, nur der Inhalt")

    S.settings.profile.windowFrame = false
    S:ApplyWindowStyle()
    eq(frame.frame.shown, false, "Rahmenfenster verschwindet")
    eq(plainFrame.shown, true, "Text-Rahmen wieder da")

    -- geschlossen: Umschalten öffnet nichts
    S:ToggleWindow(false)
    S.settings.profile.windowFrame = true
    S:ApplyWindowStyle()
    eq(S:IsWindowOpen(), false, "bleibt geschlossen")
    cleanWindow()
end)

test("Fenster: Fenster zeigt nur den Charakter, wenn eingestellt, und aktualisiert sich", function()
    local S, _, _, _, combat, P = setupWindow()
    eq(S:WindowScope(), "all", "Standard: alles")
    eq(S:WindowText(), "No data has been collected yet.", "Hinweis: gar keine Daten")
    S.settings.profile.windowScope = "char"
    eq(S:WindowScope(), "char", "nur Charakter")
    eq(S:WindowText(), "No data has been collected for this character yet.", "Hinweis: Charakter ohne Daten")

    -- nur ein anderer Charakter hat Kills
    otherKills(P, combat, 4)
    eq(S:WindowText(), "No data has been collected for this character yet.", "Charakter hat noch nichts")
    S.settings.profile.windowScope = "all"
    assert(S:WindowText():find("Account: 4", 1, true), S:WindowText())

    combat:Count("kill", 1, 12, 3)
    assert(S:WindowText():find("Creatures killed: 3", 1, true) and S:WindowText():find("Account: 7", 1, true), S:WindowText())
    S.settings.profile.windowScope = "char"
    assert(not S:WindowText():find("Account", 1, true), S:WindowText())

    -- eine Änderung in Database zeichnet das offene Fenster neu, geschlossen passiert nichts
    S:ToggleWindow(true)
    combat:Count("kill", 1, 12, 2)
    local shown
    for _, fs in ipairs(_G.fakeTexts) do if fs.state.text and fs.state.text:find("Creatures killed: 5", 1, true) then shown = true end end
    eq(shown, true, "Fenster zeigt den neuen Stand")
    S:ToggleWindow(false)
    combat:Count("kill", 1, 12)
    cleanWindow()
end)

test("Fenster: Optionen haben die Tabs Optionen und Fenster, die Einstellungen gelten für das Fenster", function()
    local S, _, frames, gui = setupWindow()
    local options = S:BuildOptions()
    eq(options.options.type, "group", "Tab Optionen")
    assert(options.options.args.overview and options.options.args.source, "Übersicht und Herkunft")
    eq(options.window.type, "group", "Tab Fenster")

    local scope = options.window.args.scope
    eq(scope.get(), "all", "Standard")
    scope.set(nil, "char")
    eq(S.settings.profile.windowScope, "char", "gespeichert")
    scope.set(nil, "unsinn")
    eq(S.settings.profile.windowScope, "all", "Unbekanntes wird zu alles")

    local size = options.window.args.fontSize
    eq(size.type, "range", "Regler"); eq(size.min, 8, "Minimum"); eq(size.max, 24, "Maximum")
    eq(size.get(), 12, "Standard")
    size.set(nil, 15)
    eq(S.settings.profile.windowFontSize, 15, "Schriftgröße gespeichert")

    local border = options.window.args.frame
    eq(border.get(), false, "Rahmen standardmäßig aus")
    options.window.args.open.func()
    eq(frames[1].shown, true, "Knopf öffnet das Fenster")
    border.set(nil, true)
    eq(S.settings.profile.windowFrame, true, "Rahmen gespeichert")
    eq(frames[1].shown, false, "Text-Rahmen weg"); eq(gui.created[1].frame.shown, true, "Fenster mit Rahmen sofort sichtbar")
    border.set(nil, false)
    eq(gui.created[1].frame.shown, false, "Fenster mit Rahmen weg"); eq(frames[1].shown, true, "Text wieder da")
    cleanWindow()
end)

test("Fenster: Position und Größe zurücksetzen (beide Aussehen)", function()
    local S, _, frames = setupWindow()
    S.settings.char.windowStatus = {} -- (im Spiel der Standardwert aus AceDB)
    S.settings.char.windowPos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 500, y = -50 }
    S.settings.char.windowSize = { width = 700, height = 600 }
    S:ToggleWindow(true)
    local frame = frames[1]
    eq(frame.width, 700, "gemerkte Größe")

    S:ResetWindowLayout()
    eq(S.settings.char.windowPos, nil, "Position vergessen"); eq(S.settings.char.windowSize, nil, "Größe vergessen")
    eq(S:IsWindowOpen(), true, "bleibt offen")
    eq(frame.points[1][4], 40, "Standardposition"); assert(frame.width < 700, "Größe nach dem Text")

    -- mit Rahmen: der Status des Fensters wird geleert
    S.settings.profile.windowFrame = true
    S:ApplyWindowStyle()
    S.settings.char.windowStatus.width, S.settings.char.windowStatus.top = 800, 100
    S:ResetWindowLayout()
    eq(next(S.settings.char.windowStatus), nil, "Status geleert")
    eq(S:IsWindowOpen(), true, "bleibt offen")
    cleanWindow()
end)

test("Fenster: das Fenster schließt sich nicht von selbst", function()
    local S, _, frames, gui = setupWindow()
    S:ToggleWindow(true)
    -- Escape (CloseSpecialWindows) wirkt nur auf UISpecialFrames, dort steht das Fenster nicht
    for _, name in ipairs(_G.UISpecialFrames) do _G[name]:Hide() end
    eq(frames[1].shown, true, "Escape schließt es nicht")
    S.settings.profile.windowFrame = true
    S:ApplyWindowStyle()
    for _, name in ipairs(_G.UISpecialFrames) do _G[name]:Hide() end
    eq(gui.created[1].frame.shown, true, "auch mit Rahmen nicht")
    cleanWindow()
end)

test("Fenster: ist der Text länger als das Fenster, scrollt das Mausrad", function()
    local S, _, frames, _, combat = setupWindow()
    combat:Count("kill", 1, 12, 3)
    S:ToggleWindow(true)
    local frame, scroll = frames[1], frames[2]
    eq(scroll.kind, "ScrollFrame", "Scrollbereich")
    assert(frame.scripts.OnMouseWheel, "Mausrad im Fenster")

    -- den Text des Fensters finden (er steht im Inhalt des Scrollbereichs)
    local text
    for _, fs in ipairs(_G.fakeTexts) do if fs.state.text and fs.state.text:find("Creatures killed", 1, true) then text = fs end end
    assert(text, "Textfeld")

    -- Text passt: nichts zu scrollen
    text.state.height = 40; scroll.height = 100; S:RefreshWindow()
    frame.scripts.OnMouseWheel(frame, -1)
    eq(scroll:GetVerticalScroll(), 0, "passt ins Fenster")

    -- Text höher als das Fenster: nach unten (delta < 0) scrollen, begrenzt auf das Ende
    text.state.height = 300; scroll.height = 100; S:RefreshWindow()
    frame.scripts.OnMouseWheel(frame, -1)
    eq(scroll:GetVerticalScroll(), S:WindowFontSize() * 3, "ein Schritt nach unten")
    for _ = 1, 50 do frame.scripts.OnMouseWheel(frame, -1) end
    eq(scroll:GetVerticalScroll(), 224, "höchstens bis zum Ende des Textes")
    frame.scripts.OnMouseWheel(frame, 1)
    eq(scroll:GetVerticalScroll(), 224 - S:WindowFontSize() * 3, "nach oben")
    for _ = 1, 50 do frame.scripts.OnMouseWheel(frame, 1) end
    eq(scroll:GetVerticalScroll(), 0, "nicht über den Anfang")

    -- geschlossen: das Mausrad tut nichts
    S:ToggleWindow(false)
    S:ScrollWindow(-1)
    eq(scroll:GetVerticalScroll(), 0, "geschlossen")
    cleanWindow()
end)

test("Fenster: das Fenster merkt sich je Charakter, ob es offen war, und kommt wieder", function()
    local S = setupWindow()
    eq(S.settings.char.windowOpen, false, "Standard: zu")
    S:RestoreWindow()
    eq(S:IsWindowOpen(), false, "bleibt zu")

    S:ToggleWindow(true)
    eq(S.settings.char.windowOpen, true, "offen gemerkt")

    -- /reload: neues Fenster, dieselben Charakterdaten
    local char = S.settings.char
    cleanWindow()
    local S2, _, frames2, gui2 = setupWindow()
    S2.settings.char = char
    S2:RestoreWindow()
    eq(S2:IsWindowOpen(), true, "nach dem Neuladen wieder offen")

    -- das Spiel versteckt das Fenster (Alt+Z): gemerkt bleibt offen
    frames2[1].shown = false
    eq(S2.settings.char.windowOpen, true, "Verstecken durch das Spiel ändert nichts")

    -- rechte Maustaste schließt für immer
    S2:ToggleWindow(true)
    frames2[1].scripts.OnMouseUp(frames2[1], "RightButton")
    eq(S2.settings.char.windowOpen, false, "rechte Maustaste: gemerkt")

    -- Schließen über den Befehl
    S2:ToggleWindow(true)
    S2:ToggleWindow(false)
    eq(S2.settings.char.windowOpen, false, "Befehl: gemerkt")

    -- mit Rahmen: der Schließen-Knopf
    S2.settings.profile.windowFrame = true
    S2:ToggleWindow(true)
    eq(S2.settings.char.windowOpen, true, "mit Rahmen offen")
    gui2.created[1].closebutton.state.hooks.OnClick()
    eq(S2.settings.char.windowOpen, false, "Schließen-Knopf gemerkt")
    cleanWindow()
end)

test("Fenster: Gruppen lassen sich ein- und ausklappen, der Zustand bleibt je Charakter", function()
    local S, _, frames, gui, combat = setupWindow()
    combat:Count("kill", 1, 12, 3); combat:Count("time", 0, nil, 60)
    S:ToggleWindow(true)

    local function bodyShown()
        for _, fs in ipairs(_G.fakeTexts) do
            if fs.state.text and fs.state.text:find("Creatures killed", 1, true) then return fs end
        end
    end
    local texts = {}
    for _, fs in ipairs(_G.fakeTexts) do if fs.state.text then texts[#texts + 1] = fs.state.text end end
    assert(table.concat(texts, "|"):find("[-] Combat", 1, true), "offene Gruppe mit [-]")
    assert(bodyShown(), "Zähler sichtbar")

    local button
    for _, f in ipairs(frames) do if f.kind == "Button" and f.group == "Combat" then button = f end end
    assert(button, "Knopf der Gruppe")
    button.scripts.OnClick(button)
    eq(S:IsGroupCollapsed("Combat"), true, "eingeklappt")
    eq(S.settings.char.windowCollapsed.Combat, true, "je Charakter gemerkt")
    local last = _G.fakeTexts
    local found
    for _, fs in ipairs(last) do if fs.state.text and fs.state.text:find("[+] Combat", 1, true) then found = true end end
    eq(found, true, "Überschrift mit [+]")

    S:ToggleGroup("Combat")
    eq(S:IsGroupCollapsed("Combat"), false, "wieder offen")
    eq(S.settings.char.windowCollapsed.Combat, nil, "kein Eintrag mehr")

    -- mit Rahmen: eingeklappte Gruppe hat nur die Überschrift
    S.settings.profile.windowFrame = true
    S:ApplyWindowStyle()
    local function count(kind, from)
        local n = 0
        for index = from, #gui.created do if gui.created[index].kind == kind then n = n + 1 end end
        return n
    end
    local before = #gui.created
    S:ToggleGroup("Combat")
    eq(count("InteractiveLabel", before + 1), 1, "eine Überschrift"); eq(count("Label", before + 1), 1, "nur Erfasst-seit, kein Text der Gruppe")
    cleanWindow()
end)
