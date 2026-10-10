-- luacheck-Konfiguration für alle Glimpse-Addons (WoW Forever, Lua 5.1-Dialekt)
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "**/Libs/**", ".glimpse/**" }
ignore = {
    "212/self",   -- ungenutztes self
    "212/_.*",    -- ungenutzte Argumente mit Unterstrich
    "211/ADDON_NAME",
}

-- Globale, die die Addons selbst setzen
globals = { "Glimpse", "GlimpseDB", "SLASH_GLIMPSE1", "StaticPopupDialogs" }

-- Blizzard-API und Mixins (nur lesen)
read_globals = {
    "LibStub", "CreateFrame", "C_Timer", "C_Item", "C_TaxiMap", "C_Loot", "C_AddOns", "C_ClickBindings", "C_Spell",
    "C_Container", "C_TooltipInfo", "C_ActionBar", "Enum", "TooltipDataProcessor",
    "UnitExists", "UnitIsUnit", "UnitHealth", "UnitCanAttack",
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "UIParent", "BackdropTemplateMixin", "Settings",
    "GetTime", "UnitGUID", "UnitName", "UnitLevel", "GetLocale", "GetAddOnMetadata", "IsAddOnLoaded",
    "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown", "issecretvalue", "hooksecurefunc",
    "GetProfessions", "GetProfessionInfo", "GetItemInfoInstant", "GetNumLootItems", "GetLootSlotType",
    "GetLootSlotLink", "GetLootSourceInfo", "GetBindingKey", "GetBindingText", "GetBindingAction",
    "GetActionInfo", "GetMacroInfo", "GetMacroBody", "GetShapeshiftForm", "GetBonusBarOffset",
    "GetActionBarPage", "GetOverrideBarIndex", "HasVehicleActionBar", "HasOverrideActionBar",
    "HasBonusActionBar", "GetNumShapeshiftForms", "InCombatLockdown", "GetCVar",
    "CanLootUnit", "UnitIsDead", "UnitIsTapDenied", "IsFishingLoot", "UnitGUID",
    "GetNumSkillLines", "GetSkillLineInfo", "GetSpellInfo", "UnitCreatureType", "C_CreatureInfo",
    "tinsert", "tremove", "wipe", "format", "strsplit", "strjoin", "strmatch", "strtrim", "strlower",
    "strupper", "strfind", "gsub", "strsub", "tostringall", "date", "time", "ceil", "floor",
    "tContains", "CopyTable", "Mixin", "_G",
    "SlashCmdList", "NUM_ACTIONBAR_BUTTONS", "bit", "geterrorhandler", "issecrettable", "TooltipUtil",
    "GetBuildInfo", "GetNumAddOns", "GetAddOnInfo", "GetAddOnDependencies", "MAX_ACCOUNT_MACROS",
    "GetNumBindings", "GetBinding", "GetShapeshiftFormInfo", "GetNumMacros", "GetMacroItem",
    "GetMacroSpell", "ITEM_QUALITY_COLORS",
    -- Orte, Wegpunkte und Fehlerfenster (Modul Locations, GatheringTooltip); TomTom ist optional
    "C_Map", "C_SuperTrack", "UiMapPoint", "CreateVector2D", "IsInInstance", "GetInstanceInfo", "TomTom",
    "StaticPopup_Show", "OKAY", "UISpecialFrames", "YES", "NO",
}

