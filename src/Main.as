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


void Main() {
    startnew(LoadFids);
}
void OnEnabled() {
    startnew(LoadFids);
}

CPlugMaterialColorTargetTable@[] tables;

void LoadFids() {
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
}
void OnDisabled() {
    ReleaseTables();
}

enum ColorTableOffsets {
    Colors = 0x18,
    Colors_Blind = 0x3C,
    TM_Stunt = 0x60,
    TM_Stunt_Blind = 0x84
}

bool[] showEditTableRows = {true, true, true, true};
string[] tableRowNames = {"Colors","Colors_Blind","TM_Stunt","TM_Stunt_Blind"};

[SettingsTab name="Color Tables"]
void R_S_ColorTables() {
    UI::AlignTextToFramePadding();

    UI::SeparatorText("Visible Color Table Rows");
    for (uint i = 0; i < 4; i++) {
        if (i > 0) UI::SameLine();
        showEditTableRows[i] = UI::Checkbox(tableRowNames[i], showEditTableRows[i]);
    }

    UI::SeparatorText("Saved Colors");
    if (UI::Button("Reset to Default")) {
        startnew(ResetColorsToDefaultAsync);
    }
    UI::SameLine();
    if (UI::Button("Open Storage Folder")) {
        OpenExplorerPath(IO::FromStorageFolder(""));
    }

    UI::SeparatorText("Edit Colors");
    UI::Indent();
    for (uint i = 0; i < tables.Length; i++) {
        auto table = tables[i];
        string name = GetFidFromNod(table).ShortFileName;
        if (name == "Fun") name = "Fun \\$i(Royal/Plastic)";
        UI::SeparatorText(name);
        // 0x18 = colors, 0x3c = Colors_Blind, stljnt: 0x60, stljnt_blind: 0x84
        UI::PushID(name+i);
        if (showEditTableRows[0]) DrawModColorTable(table, ColorTableOffsets::Colors);
        if (showEditTableRows[1]) DrawModColorTable(table, ColorTableOffsets::Colors_Blind);
        if (showEditTableRows[2]) DrawModColorTable(table, ColorTableOffsets::TM_Stunt);
        if (showEditTableRows[3]) DrawModColorTable(table, ColorTableOffsets::TM_Stunt_Blind);
        UI::PopID();
    }
    UI::Unindent();
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

void SetColorTableRowFromJson(CPlugMaterialColorTargetTable@ table, Json::Value@ j, ColorTableOffsets cto) {
    auto offset = uint(cto);
    string name = tostring(cto);
    if (!j.HasKey(name)) {
        warn("JSON for color table " + GetTableName(table) + " is missing " + name + " row: " + Json::Write(j));
        return;
    }
    auto row = j[name];
    if (row.GetType() != Json::Type::Array) {
        warn("JSON for color table " + GetTableName(table) + " / " + name + " row is not an array: " + Json::Write(row));
        return;
    }
    for (uint i = 0; i < row.Length; i++) {
        vec4 color;
        if (Text::TryParseHexColor(string(row[i]), color)) {
            SetOffsetColorHex(table, offset + 0x4 + i * 0x4, color);
        } else {
            warn("Failed to parse color: " + string(row[i]) + " in " + name + " row of color table " + GetTableName(table));
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
