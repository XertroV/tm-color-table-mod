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

uint lastMapMwId = 0;

void OnLoadCallback(CMwNod@ nod) {
    auto map = cast<CGameCtnChallenge>(nod);
    if (map is null) return;
    trace('root map null: ' + tostring(GetApp().RootMap is null));
    if (GetFidFromNod(map) is null) {
        warn("Failed to get Fid from map; skipping");
        return;
    }
    if (lastMapMwId == map.Id.Value) {
        trace('load map callback: duplicate map; id: ' + Text::Format("%08x", map.Id.Value));
        return;
    }
    lastMapMwId = map.Id.Value;
    trace('load map callback: new map; id: ' + Text::Format("%08x", map.Id.Value));
    // trace('load map callback: add ref');
    // map.MwAddRef();
    trace('load map callback: start coro');
    // startnew(OnLoadCallbackForMapAsync, map);
}

void OnLoadCallbackForMapAsync(ref@ mapRef) {
    trace('load map callback: coro running');
    auto map = cast<CGameCtnChallenge>(mapRef);
    trace('load map callback: got map from ref');
    trace('root map null: ' + tostring(GetApp().RootMap is null));
    if (map is null) return;
    trace('map is not null; gettid mwid');
    trace('got map: ' + Text::Format("%08x", map.Id.Value));
    yield(1);
    trace('yielded 1 frame; getting ref count');
    auto rc = Reflection::GetRefCount(map);
    trace('got ref count: ' + rc);
    trace('root map null: ' + tostring(GetApp().RootMap is null));
    if (rc == 1) {
        // map was destroyed before we could process it
        warn("map was destroyed before we could process it");
        // map.MwRelease();
        // @map = null;
        return;
    }
    // ! process map metadata
}


void ProcessEmbeddedCTsInMapMD(CGameCtnChallenge@ map) {
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
            auto val = Dev::GetOffsetString(bufFakeNod, elOffset + O_MAP_SCRIPTMD_STR_VAL);
            trace('read CCT_CustomColorTables value: ' + val);
            // found it
            return;
        }
    }
    warn("Checked " + len + " script metadata entries, but did not find CCT_CustomColorTables");
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
