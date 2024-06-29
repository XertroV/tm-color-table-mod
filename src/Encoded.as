// Simple encoding for color tables to put them as a string in map metadata

class ColorTablesInMap {
    vec4[] Canopy;
    vec4[] CanopyLights;
    vec4[] CanopyStructure;
    vec4[] Fun;
    vec4[] Sport;
    vec4[] SportDecals;
    vec4[] SportDecals2;
    vec4[] SportIllum;
    vec4[] SportObstacles;
    vec4[] TrackWall;

    ColorTablesInMap() {}

    bool isBackup = false;
    ColorTableOffsets backupCTO;

    ColorTablesInMap(ColorTableOffsets cto) {
        isBackup = true;
        backupCTO = cto;
        for (uint i = 0; i < 10; i++) {
            SetTableFromCTT(i, cto);
        }
    }

    ColorTablesInMap(const string &in encoded) {
        auto verRaw = encoded[0];
        if (verRaw <= 0x30) throw("Invalid version");
        auto version = encoded[0] - 0x30;
        if (version != 1) throw("Unk version: " + version);
        ParseVersionOne(encoded.SubStr(1));
    }

    void ParseVersionOne(const string &in encoded) {
        MemoryBuffer@ buf = MemoryBuffer();
        buf.WriteFromBase64(encoded);
        buf.Seek(0);
        while (!buf.AtEnd()) {
            // tables are alphabetical
            auto tableIx = buf.ReadUInt8();
            if (tableIx > 10) throw("Invalid table index");
            auto @table = GetTable(tableIx);
            ReadTableFromBuf(table, buf);
        }
    }

    void ReadTableFromBuf(vec4[]@ table, MemoryBuffer@ buf) {
        auto count = buf.ReadUInt8();
        if (count != 0 && count != 5) throw("invalid length for table: " + count);
        if (buf.GetSize() - buf.GetPosition() < count * 16) throw("not enough data left!");
        table.Resize(count);
        for (uint i = 0; i < count; i++) {
            table[i].x = buf.ReadFloat();
            table[i].y = buf.ReadFloat();
            table[i].z = buf.ReadFloat();
            table[i].w = buf.ReadFloat();
        }
    }

    vec4[]@ GetTable(uint ix) {
        switch (ix) {
            case 0: return @Canopy;
            case 1: return @CanopyLights;
            case 2: return @CanopyStructure;
            case 3: return @Fun;
            case 4: return @Sport;
            case 5: return @SportDecals;
            case 6: return @SportDecals2;
            case 7: return @SportIllum;
            case 8: return @SportObstacles;
            case 9: return @TrackWall;
        }
        throw("Invalid table index: " + ix);
        return null;
    }

    string TableIxToName(uint ix) {
        switch (ix) {
            case 0: return "Canopy";
            case 1: return "CanopyLights";
            case 2: return "CanopyStructure";
            case 3: return "Fun";
            case 4: return "Sport";
            case 5: return "SportDecals";
            case 6: return "SportDecals2";
            case 7: return "SportIllum";
            case 8: return "SportObstacles";
            case 9: return "TrackWall";
        }
        throw("Invalid table index: " + ix);
        return "";
    }

    void SetTableFromDefault(uint ix, ColorTableOffsets cto) {
        auto name = TableIxToName(ix);
        IO::FileSource fd("defaults/" + name + COLOR_TABLES_EXTENSION);
        SetTableFromJson(ix, Json::Parse(fd.ReadToEnd()), cto);
    }

    void SetTableFromJson(uint ix, Json::Value@ j, ColorTableOffsets cto) {
        auto @table = GetTable(ix);
        trace('setting table from json: ' + Json::Write(j));
        auto row = j[tostring(cto)];
        auto nbCols = row.Length;
        table.Resize(nbCols);
        for (uint i = 0; i < nbCols; i++) {
            vec4 color;
            if (Text::TryParseHexColor(string(row[i]), color)) {
                table[i] = color;
            } else {
                warn("Failed to parse color: " + Json::Write(row[i]));
            }
        }
    }

    void SetTableFromCTT(uint ix, ColorTableOffsets cto) {
        auto name = TableIxToName(ix);
        for (uint i = 0; i < tables.Length; i++) {
            auto table = tables[i];
            if (GetTableName(table) == name) {
                SetTableFromCTT(ix, table, cto);
                return;
            }
        }
    }

    void SetTableFromCTT(uint ix, CPlugMaterialColorTargetTable@ table, ColorTableOffsets cto) {
        auto @tableData = GetTable(ix);
        auto offset = uint(cto);
        auto nbCols = Get_CT_NbColors(table, cto);
        tableData.Resize(nbCols);
        for (uint i = 0; i < nbCols; i++) {
            tableData[i] = GetOffsetColorHex(table, offset + 4 + i * 4);
        }
    }

    void WriteTableToCTT(uint ix, ColorTableOffsets cto) {
        auto name = TableIxToName(ix);
        for (uint i = 0; i < tables.Length; i++) {
            auto table = tables[i];
            if (GetTableName(table) == name) {
                WriteTableToCTT(ix, table, cto);
                return;
            }
        }
    }

    void WriteTableToCTT(uint ix, CPlugMaterialColorTargetTable@ table, ColorTableOffsets cto) {
        auto @tableData = GetTable(ix);
        auto offset = uint(cto);
        auto nbCols = tableData.Length;
        // Set_CT_NbColors(table, cto, nbCols);
        for (uint i = 0; i < nbCols; i++) {
            SetOffsetColorHex(table, offset + 4 + i * 4, tableData[i]);
        }
    }

    string Encode() {
        MemoryBuffer@ buf = MemoryBuffer();
        for (uint i = 0; i < 10; i++) {
            auto @t = GetTable(i);
            if (t.Length == 0) continue;
            buf.Write(uint8(i)); // table index
            EncodeColorsListToBuf(t, buf);
        }
        buf.Seek(0);
        return "1" // version
            + buf.ReadToBase64(buf.GetSize());
    }
}

void EncodeColorsListToBuf(vec4[]@ list, MemoryBuffer@ buf) {
    buf.Write(uint8(list.Length));
    for (uint i = 0; i < list.Length; i++) {
        auto col = list[i];
        buf.Write(col.x);
        buf.Write(col.y);
        buf.Write(col.z);
        buf.Write(col.w);
    }
}

ColorTablesInMap@ ParseColorTablesInMap(const string &in encoded) {
    try {
        return ColorTablesInMap(encoded);
    } catch {
        warn("Failed to parse color tables in map: " + encoded);
        warn("Exception: " + getExceptionInfo());
        PrintActiveContextStack(false);
        return null;
    }
}

const string[] colorTableNamesSortedForEncodingIndex = {
    "Canopy",
    "CanopyLights",
    "CanopyStructure",
    "Fun"
    "Sport",
    "SportDecals",
    "SportDecals2",
    "SportIllum",
    "SportObstacles",
    "TrackWall",
};

void EncodeTableToBuf(CPlugMaterialColorTargetTable@ table, MemoryBuffer@ buf, ColorTableOffsets cto) {
    auto tableName = GetTableName(table);
    auto tableIx = colorTableNamesSortedForEncodingIndex.Find(tableName);
    if (tableIx == -1) throw("Invalid table name: " + tableName);
    buf.Write(uint8(tableIx));
    auto offset = uint(cto);
    auto nbCols = Get_CT_NbColors(table, cto);
    buf.Write(uint8(nbCols));
    for (uint i = 0; i < nbCols; i++) {
        auto col = GetOffsetColorHex(table, offset + 4 + i * 4);
        buf.Write(col.x);
        buf.Write(col.y);
        buf.Write(col.z);
        buf.Write(col.w);
    }
}

string EncodeTables(CPlugMaterialColorTargetTable@[]@ tables, ColorTableOffsets cto) {
    MemoryBuffer@ buf = MemoryBuffer();
    buf.Write(uint8(1)); // version
    for (uint i = 0; i < tables.Length; i++) {
        EncodeTableToBuf(tables[i], buf, cto);
    }
    buf.Seek(0);
    return buf.ReadToBase64(buf.GetSize());
}
