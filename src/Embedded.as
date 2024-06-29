void UpdateEmbeddedCustomColorTablesHook() {
    if (!S_EnableEmbeddedCustomColorTables) {
        EmbeddedCustomColorTables::Disable();
    } else {
        EmbeddedCustomColorTables::Enable();
    }
}

namespace EmbeddedCustomColorTables {
    bool _enabled = false;
    uint mapClassId = 0;

    void Enable() {
        OnPlaygroundPrepareHook.Apply();
        // if (_enabled) return;
        // if (mapClassId == 0) {
        //     auto ty = Reflection::GetType("CGameCtnChallenge");
        //     mapClassId = ty.ID;
        // }
        // if (mapClassId == 0) throw("Failed to get map class ID");
        // RegisterLoadCallback(mapClassId);
        // _enabled = true;
        // trace("Registered load callback for map class ID: " + Text::Format("%08x", mapClassId));
    }

    void Disable() {
        OnPlaygroundPrepareHook.Unapply();
        // if (!_enabled) return;
        // UnregisterLoadCallback(mapClassId);
        // _enabled = false;
        // trace('Unregistered load callback for map class ID: ' + Text::Format("%08x", mapClassId));
    }
}

// uint lastMapMwId = 0;

// void OnLoadCallback(CMwNod@ nod) {
//     auto map = cast<CGameCtnChallenge>(nod);
//     if (map is null) return;
//     trace('root map null: ' + tostring(GetApp().RootMap is null));
//     if (GetFidFromNod(map) is null) {
//         warn("Failed to get Fid from map; skipping");
//         return;
//     }
//     if (lastMapMwId == map.Id.Value) {
//         trace('load map callback: duplicate map; id: ' + Text::Format("%08x", map.Id.Value));
//         return;
//     }
//     lastMapMwId = map.Id.Value;
//     trace('load map callback: new map; id: ' + Text::Format("%08x", map.Id.Value));
//     // trace('load map callback: add ref');
//     // map.MwAddRef();
//     trace('load map callback: start coro');
//     // startnew(OnLoadCallbackForMapAsync, map);
// }

// void OnLoadCallbackForMapAsync(ref@ mapRef) {
//     trace('load map callback: coro running');
//     auto map = cast<CGameCtnChallenge>(mapRef);
//     trace('load map callback: got map from ref');
//     trace('root map null: ' + tostring(GetApp().RootMap is null));
//     if (map is null) return;
//     trace('map is not null; gettid mwid');
//     trace('got map: ' + Text::Format("%08x", map.Id.Value));
//     yield(1);
//     trace('yielded 1 frame; getting ref count');
//     auto rc = Reflection::GetRefCount(map);
//     trace('got ref count: ' + rc);
//     trace('root map null: ' + tostring(GetApp().RootMap is null));
//     if (rc == 1) {
//         // map was destroyed before we could process it
//         warn("map was destroyed before we could process it");
//         // map.MwRelease();
//         // @map = null;
//         return;
//     }
//     // ! process map metadata
// }


void ProcessEmbeddedCTsInMapMD(CGameCtnChallenge@ map) {
    if (g_IsInMapWithCustomColors && g_MapWithCustomColorsMwId == map.Id.Value) {
        trace('loaded custom colors; skipping');
        return;
    }
    if (map.ScriptMetadata is null) {
        warn("Map has no script metadata: " + map.Id.GetName());
        return;
    }
    auto meta = map.ScriptMetadata;
    auto bufPtr = Dev::GetOffsetUint64(meta, O_MAP_SCRIPTMD_VALUES_BUF);
    if (!PtrLooksOkay(bufPtr)) {
        warn("Invalid buffer pointer: " + Text::FormatPointer(bufPtr));
        return;
    }
    uint len = Dev::GetOffsetUint32(meta, O_MAP_SCRIPTMD_VALUES_BUF + 0x8);
    uint cap = Dev::GetOffsetUint32(meta, O_MAP_SCRIPTMD_VALUES_BUF + 0xC);
    if (len > cap) {
        warn("Invalid buffer length: " + len + " > " + cap);
        return;
    }
    // loop through buffer entries and look for CCT_CustomColorTables
    auto bufFakeNod = Dev::GetOffsetNod(meta, O_MAP_SCRIPTMD_VALUES_BUF);
    if (bufFakeNod is null) {
        warn("Failed to get script MD values buffer");
        return;
    }
    string mdName;
    uint elOffset;
    for (uint i = 0; i < len; i++) {
        elOffset = i * SZ_MAP_SCRIPT_METADATA_EL;
        mdName = Dev::GetOffsetString(bufFakeNod, elOffset + O_MAP_SCRIPTMD_NAME_STR);
        if (mdName == "CCT_CustomColorTables") {
            auto ty = Dev::GetOffsetUint32(bufFakeNod, elOffset + O_MAP_SCRIPTMD_TYPE);
            if (ty != 5) {
                warn("Unexpected type for CCT_CustomColorTables: " + ty + " (expected 5 = string");
                return;
            }
            // found it
            auto val = Dev::GetOffsetString(bufFakeNod, elOffset + O_MAP_SCRIPTMD_STR_VAL);
            trace('read CCT_CustomColorTables value: ' + val);
            SetCustomColorsForMapFromEncoded(val);
            return;
        }
    }
    warn("Checked " + len + " script metadata entries, but did not find CCT_CustomColorTables");
}


void SetCustomColorsForMapFromEncoded(string encoded) {
    ColorTablesInMap@ colors = ColorTablesInMap(encoded);
    if (colors is null) {
        warn("Failed to decode custom colors from encoded string: " + encoded);
        return;
    }
    auto map = GetApp().RootMap;
    if (map is null) {
        NotifyWarning("Failed to get root map -- should not be null?!");
        return;
    }
    g_IsInMapWithCustomColors = true;
    g_MapWithCustomColorsMwId = map.Id.Value;
    trace('decoded custom colors from encoded string; activating for map ' + Text::Format("%08x", g_MapWithCustomColorsMwId));
    Embedded::BackupColorsAndSet(map, colors);
    startnew(WatchMapAndResetColorsAfter);
}


void WatchMapAndResetColorsAfter() {
    auto app = GetApp();
    while (app.RootMap !is null && app.RootMap.Id.Value == g_MapWithCustomColorsMwId && cast<CGameCtnEditorFree>(app.Editor) is null) {
        yield();
    }
    trace('map changed; resetting custom colors');
    Embedded::ResetColors();
    g_IsInMapWithCustomColors = false;
    g_MapWithCustomColorsMwId = 0;
}


namespace Embedded {
    ColorTablesInMap@ backupColors;
    // if we set color blind too
    ColorTablesInMap@ backupColorsCB;

    void BackupColorsAndSet(CGameCtnChallenge@ map, ColorTablesInMap@ colors) {
        bool isStunt = map.MapType.EndsWith("TM_Stunt");
        auto cto = isStunt ? ColorTableOffsets::TM_Stunt : ColorTableOffsets::Colors;
        auto cto2 = isStunt ? ColorTableOffsets::TM_Stunt_Blind : ColorTableOffsets::Colors_Blind;
        @backupColors = GetCurrentColorsTables(cto);
        if (S_OverrideColorblindColorsToo) {
            @backupColorsCB = GetCurrentColorsTables(cto2);
        } else {
            @backupColorsCB = null;
        }
        SetColorsFromEncoded(colors, cto, cto2);
    }

    void ResetColors() {
        if (backupColors is null) {
            warn("No backup colors to restore");
            return;
        }
        SetColorsFromEncoded(backupColors, backupColors.backupCTO);
        if (backupColorsCB !is null) {
            SetColorsFromEncoded(backupColorsCB, backupColorsCB.backupCTO);
        }
    }

    void SetColorsFromEncoded(ColorTablesInMap@ colors, ColorTableOffsets cto, ColorTableOffsets cto2) {
        SetColorsFromEncoded(colors, cto);
        if (S_OverrideColorblindColorsToo) {
            SetColorsFromEncoded(colors, cto2);
        }
    }

    void SetColorsFromEncoded(ColorTablesInMap@ colors, ColorTableOffsets cto) {
        for (uint i = 0; i < 10; i++) {
            colors.WriteTableToCTT(i, cto);
        }
    }
}



const uint16 O_MAP_SCRIPTMD_VALUES_BUF = 0x28;

const uint16 SZ_MAP_SCRIPT_METADATA_EL = 0x88;
const uint16 O_MAP_SCRIPTMD_NAME_STR = 0x0;
const uint16 O_MAP_SCRIPTMD_TYPE = 0x10;
const uint16 O_MAP_SCRIPTMD_STR_VAL = 0x28;
const uint16 O_MAP_SCRIPTMD_INT_VAL = 0x30;

enum ScriptMetadataTypes {
    Bool = 1,
    Int = 2,
    Float = 3,
    String = 5,
}





bool PtrLooksOkay(uint64 ptr) {
    return ptr != 0 && ptr % 8 == 0 && ptr < 0x0000030000000000 && ptr > 0xFFFFFFFF;
}


HookHelper@ OnPlaygroundPrepareHook = HookHelper(
    // v load PlaygroundPrepare string
    "48 8D 15 ?? ?? ?? ?? 33 ED 48 8D 4C 24 20 89 6C 24 30 E8 ?? ?? ?? ?? 4C 8B 0E",
    9, 0, "OnPlaygroundPrepare", Dev::PushRegisters::Basic
);

void OnPlaygroundPrepare() {
    auto app = GetApp();
    trace('OnPlaygroundPrepare');
    trace('RootMap is null: ' + tostring(app.RootMap is null));
    trace('RootMap script md: ' + app.RootMap.ScriptMetadata.MetadataTraitsCount);
    ProcessEmbeddedCTsInMapMD(app.RootMap);
}

[SettingsTab name="Embedded Custom Color Tables"]
void R_S_EmbedCustomColors() {
    UI::SeparatorText("\\$<\\$f80Notice\\$>");
    UI::TextWrapped("Please Note! These custom colors are managed entirely through this plugin. They are not like a map mod. They will not work on consoles, nor for people who don't have " + PluginName + " installed.");
    auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
    UI::SeparatorText("Embed in Map");
#if DEPENDENCY_EDITOR
    if (editor is null) {
        UI::TextWrapped("You must be in the map editor to use this feature.");
        return;
    }
    auto ep = Meta::GetPluginFromID("Editor");
    if (ep is null) {
        UI::TextWrapped("Failed to get Editor++ plugin info");
        return;
    }
    if (!ep.Enabled) {
        UI::TextWrapped("Editor++ is disabled. Please enable it via: Developer > Toggle Plugin > Editor++.\nAlternatively: Settings > Toggle Plugins.");
        return;
    }
    DrawEmbedCustomColorsUI();
#else
    UI::Text("Saving custom color tables to maps requires that you have \\$<\\$iEditor++\\$> installed.");
#endif
}



#if DEPENDENCY_EDITOR
void DrawEmbedCustomColorsUI() {
    if (UI::Button("Set Map to Stunt Colors")) {
        EmbedStuntColorsToMap();
    }
    if (UI::Button("Set Map to Race Colors")) {
        EmbedNormalColorsToMap();
    }
    if (UI::Button("Set Map to current Stunt Colors")) {
        EmbedCurrStuntColorsToMap();
    }
    if (UI::Button("Set Map to current Race Colors")) {
        EmbedCurrNormalColorsToMap();
    }
}

void EmbedStuntColorsToMap() {
    EmbedDefaultColorsToMap(ColorTableOffsets::TM_Stunt);
}

void EmbedNormalColorsToMap() {
    EmbedDefaultColorsToMap(ColorTableOffsets::Colors);
}

void EmbedDefaultColorsToMap(ColorTableOffsets cto) {
    ColorTablesInMap@ colors = GetDefaultColorsTables(cto);
    auto encoded = colors.Encode();
    Editor::Set_Map_EmbeddedCustomColorsEncoded(encoded);
    Notify("Embedded custom colors to map.\n\n\\$ccc\\$iRaw: " + encoded);
}

ColorTablesInMap@ GetDefaultColorsTables(ColorTableOffsets cto) {
    ColorTablesInMap@ colors = ColorTablesInMap();
    for (uint i = 0; i < 10; i++) {
        colors.SetTableFromDefault(i, cto);
    }
    return colors;
}

void EmbedCurrStuntColorsToMap() {
    EmbedCurrTableColorsToMap(ColorTableOffsets::TM_Stunt);
}

void EmbedCurrNormalColorsToMap() {
    EmbedCurrTableColorsToMap(ColorTableOffsets::Colors);
}

void EmbedCurrTableColorsToMap(ColorTableOffsets cto) {
    auto cs = GetCurrentColorsTables(cto);
    auto encoded = cs.Encode();
    Editor::Set_Map_EmbeddedCustomColorsEncoded(encoded);
    Notify("Embedded custom colors to map.\n\n\\$ccc\\$iRaw: " + encoded);
}

#endif
