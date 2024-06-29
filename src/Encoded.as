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
            table[i] = vec4(buf.ReadFloat(), buf.ReadFloat(), buf.ReadFloat(), buf.ReadFloat());
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
