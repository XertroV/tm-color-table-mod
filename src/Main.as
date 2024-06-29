const string PluginName = Meta::ExecutingPlugin().Name;
const string MenuIconColor = "\\$f5d";
const string PluginIcon = Icons::Cogs;
const string MenuTitle = MenuIconColor + PluginIcon + "\\$z " + PluginName;

const string[] colorTableNames = {
    "Sport",
    "SportIllum",
    "SportDecals",
    "SportDecals2",
    "SportObstacles",
    "TrackWall",
    "Canopy",
    "CanopyLights",
    "CanopyStructure",
    "Fun"
};

const string COLOR_TABLES_FOLDER = "GameData/Stadium/Media/ColorTargetTables";
const string COLOR_TABLES_EXTENSION = ".ColorTable.gbx.json";


string GetGameVersion() {
    auto app = GetApp();
    return app.SystemPlatform.ExeVersion;
}

string TmGameVersion;
bool GameVersionOkay = false;

void Main() {
    RunMain();
}
void OnEnabled() {
    RunMain();
}

void RunMain() {
    TmGameVersion = GetGameVersion();
    GameVersionOkay = TmGameVersion >= "2024-06-28_13_46";
    startnew(LoadFids);
    UpdateEmbeddedCustomColorTablesHook();
}

CPlugMaterialColorTargetTable@[] tables;

void LoadFids() {
    if (!GameVersionOkay) return;
    if (tables.Length > 0) return;
    for (uint i = 0; i < colorTableNames.Length; i++) {
        auto name = COLOR_TABLES_FOLDER + "/" + colorTableNames[i] + COLOR_TABLES_EXTENSION;
        auto fid = Fids::GetGame(name);
        if (fid is null) {
            warn("null fid: " + name);
        } else {
            auto nod = Fids::Preload(fid);
            if (nod is null) {
                warn("null nod: " + name);
                continue;
            }
            auto table = cast<CPlugMaterialColorTargetTable>(nod);
            if (table is null) {
                warn("null table: " + name);
            } else {
                table.MwAddRef();
                tables.InsertLast(table);
            }
        }
    }
    PopulateColorsFromFilesAsync();
}

void ReleaseTables() {
    for (uint i = 0; i < tables.Length; i++) {
        tables[i].MwRelease();
    }
    tables.RemoveRange(0, tables.Length);
}

void OnDestroyed() {
    ReleaseTables();
    EmbeddedCustomColorTables::Disable();
}
void OnDisabled() {
    ReleaseTables();
    EmbeddedCustomColorTables::Disable();
}

enum ColorTableOffsets {
    Colors = 0x18,
    Colors_Blind = 0x3C,
    TM_Stunt = 0x60,
    TM_Stunt_Blind = 0x84
}

bool[] showEditTableRows = {true, true, true, true};
string[] tableRowNames = {"Colors","Colors_Blind","TM_Stunt","TM_Stunt_Blind"};

bool setOpenState = true;
bool openState = true;

bool g_IsInMapWithCustomColors = false;
uint g_MapWithCustomColorsMwId = 0;

[Setting hidden]
bool S_EnableEmbeddedCustomColorTables = true;
[Setting hidden]
bool S_OverrideColorblindColorsToo = false;

[SettingsTab name="Color Tables"]
void R_S_ColorTables() {
    if (!GameVersionOkay) return;

    UI::SeparatorText("Custom Embedded Color Tables");
    UI::AlignTextToFramePadding();
    bool wasEmbeddedCCTEnabled = S_EnableEmbeddedCustomColorTables;
    S_EnableEmbeddedCustomColorTables = UI::Checkbox("Enable Embedded Custom Color Tables", S_EnableEmbeddedCustomColorTables);
    if (wasEmbeddedCCTEnabled != S_EnableEmbeddedCustomColorTables) {
        UpdateEmbeddedCustomColorTablesHook();
    }

    S_OverrideColorblindColorsToo = UI::Checkbox("Override Colorblind Colors Too", S_OverrideColorblindColorsToo);
    AddSimpleTooltip("If you use the colorblind colors, you must enable this option to see custom colors in maps.");

    UI::SeparatorText("Visible Color Table Rows");
    for (uint i = 0; i < 4; i++) {
        if (i > 0) UI::SameLine();
        showEditTableRows[i] = UI::Checkbox(tableRowNames[i], showEditTableRows[i]);
    }

    if (g_IsInMapWithCustomColors) {
        UI::AlignTextToFramePadding();
        UI::TextWrapped("You are in a map with custom colors -- please head back to the menu to customize your default colors.");
    }

    UI::BeginDisabled(g_IsInMapWithCustomColors);

    UI::SeparatorText("Saved Colors");
    if (UI::Button("Reset to Default")) {
        startnew(ResetColorsToDefaultAsync);
    }
    UI::SameLine();
    if (UI::Button("Open Storage Folder")) {
        OpenExplorerPath(IO::FromStorageFolder(""));
    }
    UI::SameLine();
    if (UI::Button("Refresh From Files")) {
        startnew(PopulateColorsFromFilesAsync);
    }

    UI::AlignTextToFramePadding();
    UI::TextWrapped("\\$i\\$cccTo save the current colors, copy the files in the storage folder to a new directory. To restore them, copy them back to the main storage directory and refresh.\\$z");

    UI::SeparatorText("Presets");
    if (UI::Button("Copy current TM_Stunt* to Colors*")) {
        ColorTables_CopyFromTo(ColorTableOffsets::TM_Stunt, ColorTableOffsets::Colors);
        ColorTables_CopyFromTo(ColorTableOffsets::TM_Stunt_Blind, ColorTableOffsets::Colors_Blind);
    }
    UI::SameLine();
    if (UI::Button("Copy current Colors* to TM_Stunt*")) {
        ColorTables_CopyFromTo(ColorTableOffsets::Colors, ColorTableOffsets::TM_Stunt);
        ColorTables_CopyFromTo(ColorTableOffsets::Colors_Blind, ColorTableOffsets::TM_Stunt_Blind);
    }
    // UI::SameLine();
    if (UI::Button("Copy default TM_Stunt* to Colors*")) {
        ColorTables_CopyFromTo(ColorTableOffsets::TM_Stunt, ColorTableOffsets::Colors, true);
        ColorTables_CopyFromTo(ColorTableOffsets::TM_Stunt_Blind, ColorTableOffsets::Colors_Blind, true);
    }
    UI::SameLine();
    if (UI::Button("Copy default Colors* to TM_Stunt*")) {
        ColorTables_CopyFromTo(ColorTableOffsets::Colors, ColorTableOffsets::TM_Stunt, true);
        ColorTables_CopyFromTo(ColorTableOffsets::Colors_Blind, ColorTableOffsets::TM_Stunt_Blind, true);
    }

    UI::SeparatorText("Edit Colors");
    if (UI::Button("Expand All")) {
        setOpenState = true;
        openState = true;
    }
    UI::SameLine();
    if (UI::Button("Collapse All")) {
        setOpenState = true;
        openState = false;
    }

    UI::Indent();
    for (uint i = 0; i < tables.Length; i++) {
        auto table = tables[i];
        string name = GetFidFromNod(table).ShortFileName;
        if (name == "Fun") name = "Fun \\$i(Royal/Plastic)";
        if (setOpenState) UI::SetNextItemOpen(openState);
        if (UI::CollapsingHeader(name)) {
            // 0x18 = colors, 0x3c = Colors_Blind, stljnt: 0x60, stljnt_blind: 0x84
            UI::PushID(name+i);
            if (showEditTableRows[0]) DrawModColorTable(table, ColorTableOffsets::Colors);
            if (showEditTableRows[1]) DrawModColorTable(table, ColorTableOffsets::Colors_Blind);
            if (showEditTableRows[2]) DrawModColorTable(table, ColorTableOffsets::TM_Stunt);
            if (showEditTableRows[3]) DrawModColorTable(table, ColorTableOffsets::TM_Stunt_Blind);
            UI::PopID();
        }
    }
    UI::Unindent();
    setOpenState = false;

    UI::EndDisabled();
}

void DrawModColorTable(CPlugMaterialColorTargetTable@ table, ColorTableOffsets cto) {
    string name = tostring(cto);
    UI::Indent();
    UI::SeparatorText(name);
    auto offset = uint(cto);
    auto nbColors = Dev::GetOffsetUint32(table, offset);
    // there is only enough space for 5 colors, so more than this = error
    if (nbColors == 0 || nbColors > 5) {
        UI::Text("No colors");
        UI::Unindent();
        return;
    }
    for (uint i = 0; i < nbColors; i++) {
        auto color = GetOffsetColorHex(table, offset + 0x4 + i * 0x4);
        auto newCol = UI::InputColor4(name + "[" + i + "]", color);
        if (newCol != color) {
            SetOffsetColorHex(table, offset + 0x4 + i * 0x4, newCol);
            UpdateSavedColorTable(table);
        }
    }
    UI::Unindent();
}

uint Get_CT_NbColors(CPlugMaterialColorTargetTable@ table, ColorTableOffsets cto) {
    return Dev::GetOffsetUint32(table, uint(cto));
}

vec4 GetOffsetColorHex(CPlugMaterialColorTargetTable@ table, uint offset) {
    auto color = Dev::GetOffsetUint32(table, offset);
    return vec4(
        (color & 0xFF) / 255.0,
        ((color >> 8) & 0xFF) / 255.0,
        ((color >> 16) & 0xFF) / 255.0,
        ((color >> 24) & 0xFF) / 255.0
    );
}

void SetOffsetColorHex(CPlugMaterialColorTargetTable@ table, uint offset, const vec4 &in color) {
    Dev::SetOffset(table, offset,
        uint(color.x * 255) |
        (uint(color.y * 255) << 8) |
        (uint(color.z * 255) << 16) |
        (uint(color.w * 255) << 24)
    );
}

void SetColorTableFromJson(CPlugMaterialColorTargetTable@ table, Json::Value@ j) {
    SetColorTableRowFromJson(table, j, ColorTableOffsets::Colors);
    SetColorTableRowFromJson(table, j, ColorTableOffsets::Colors_Blind);
    if (!GameVersionOkay) return;
    SetColorTableRowFromJson(table, j, ColorTableOffsets::TM_Stunt);
    SetColorTableRowFromJson(table, j, ColorTableOffsets::TM_Stunt_Blind);
}

Json::Value@ ColorTableToJson(CPlugMaterialColorTargetTable@ table) {
    auto j = Json::Object();
    j["ClassId"] = "CPlugMaterialColorTargetTable";
    j["Colors"] = ColorTableRowToJson(table, j, ColorTableOffsets::Colors);
    j["Colors_Blind"] = ColorTableRowToJson(table, j, ColorTableOffsets::Colors_Blind);
    j["TM_Stunt"] = ColorTableRowToJson(table, j, ColorTableOffsets::TM_Stunt);
    j["TM_Stunt_Blind"] = ColorTableRowToJson(table, j, ColorTableOffsets::TM_Stunt_Blind);
    return j;
}

void SetColorTableRowFromJson(CPlugMaterialColorTargetTable@ table, Json::Value@ j, ColorTableOffsets to_cto, ColorTableOffsets from_cto = ColorTableOffsets(0)) {
    if (int(from_cto) == 0) from_cto = to_cto;
    auto offset = uint(to_cto);
    string from_name = tostring(from_cto);
    if (!j.HasKey(from_name)) {
        warn("JSON for color table " + GetTableName(table) + " is missing " + from_name + " row: " + Json::Write(j));
        return;
    }
    auto row = j[from_name];
    if (row.GetType() != Json::Type::Array) {
        warn("JSON for color table " + GetTableName(table) + " / " + from_name + " row is not an array: " + Json::Write(row));
        return;
    }
    for (uint i = 0; i < row.Length; i++) {
        vec4 color;
        if (Text::TryParseHexColor(string(row[i]), color)) {
            SetOffsetColorHex(table, offset + 0x4 + i * 0x4, color);
        } else {
            warn("Failed to parse color: " + string(row[i]) + " in " + from_name + " row of color table " + GetTableName(table));
        }
    }
}

Json::Value@ ColorTableRowToJson(CPlugMaterialColorTargetTable@ table, Json::Value@ j, ColorTableOffsets cto) {
    auto offset = uint(cto);
    auto nbColors = Dev::GetOffsetUint32(table, offset);
    if (nbColors == 0 || nbColors > 5) return Json::Array(); // error (no colors or too many
    auto row = Json::Array();
    for (uint i = 0; i < nbColors; i++) {
        auto colorUint = Dev::GetOffsetUint32(table, offset + 0x4 + i * 0x4);
        row.Add(ColorUintToHexString(colorUint));
    }
    return row;
}

string ColorUintToHexString(uint color) {
    return Text::Format("#%02X", color & 0xFF)
        + Text::Format("%02X", (color >> 8) & 0xFF)
        + Text::Format("%02X", (color >> 16) & 0xFF)
        + Text::Format("%02X", (color >> 24) & 0xFF);
}

void ColorTables_CopyFromTo(ColorTableOffsets from, ColorTableOffsets to, bool useDefaults = false) {
    if (!GameVersionOkay) return;
    for (uint i = 0; i < tables.Length; i++) {
        auto table = tables[i];
        auto fromOffset = uint(from);
        auto toOffset = uint(to);
        auto nbColors = Dev::GetOffsetUint32(table, fromOffset);
        if (useDefaults) {
            auto name = GetTableName(table);
            IO::FileSource fd("defaults/" + name + COLOR_TABLES_EXTENSION);
            auto j = Json::Parse(fd.ReadToEnd());
            SetColorTableRowFromJson(table, j, to, from);
        } else {
            if (nbColors == 0 || nbColors > 5) continue; // error (no colors or too many
            for (uint j = 0; j < nbColors; j++) {
                auto color = Dev::GetOffsetUint32(table, fromOffset + 0x4 + j * 0x4);
                Dev::SetOffset(table, toOffset + 0x4 + j * 0x4, color);
            }
        }
        UpdateSavedColorTable(table);
    }
}









void Notify(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg);
    trace("Notified: " + msg);
}

void NotifySuccess(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg, vec4(.4, .7, .1, .3), 10000);
    trace("Notified: " + msg);
}

void NotifyError(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Error", msg, vec4(.9, .3, .1, .3), 15000);
}

void NotifyWarning(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Warning", msg, vec4(.9, .6, .2, .3), 15000);
}

void AddSimpleTooltip(const string &in msg) {
    if (UI::IsItemHovered()) {
        UI::SetNextWindowSize(400, 0, UI::Cond::Appearing);
        UI::BeginTooltip();
        UI::TextWrapped(msg);
        UI::EndTooltip();
    }
}
