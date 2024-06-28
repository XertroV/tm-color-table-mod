const string STORAGE_FOLDER = IO::FromStorageFolder("");

void PopulateColorsFromFilesAsync() {
    // colorTableNames
    while (tables.Length == 0) yield();
    yield(5);
    for (uint i = 0; i < tables.Length; i++) {
        auto table = tables[i];
        auto name = GetTableName(table);
        auto path = IO::FromStorageFolder(name + COLOR_TABLES_EXTENSION);
        if (!IO::FileExists(path)) {
            IO::FileSource fd("defaults/" + name + COLOR_TABLES_EXTENSION);
            IO::File f(path, IO::FileMode::Write);
            f.Write(fd.ReadToEnd());
            f.Close();
        }
        auto j = Json::FromFile(path);
        SetColorTableFromJson(table, j);
    }
}

string GetTableName(CPlugMaterialColorTargetTable@ t) {
    return string(GetFidFromNod(t).ShortFileName);
}

void UpdateSavedColorTable(CPlugMaterialColorTargetTable@ table) {
    auto j = ColorTableToJson(table);
    auto name = GetTableName(table);
    // trace('saving '+name+': ' + Json::Write(j));
    auto path = IO::FromStorageFolder(name + COLOR_TABLES_EXTENSION);
    Json::ToFile(path, j);
}

void ResetColorsToDefaultAsync() {
    for (uint i = 0; i < tables.Length; i++) {
        auto table = tables[i];
        auto name = GetTableName(table);
        auto path = IO::FromStorageFolder(name + COLOR_TABLES_EXTENSION);
        // copy default to storage
        IO::FileSource fd("defaults/" + name + COLOR_TABLES_EXTENSION);
        IO::File f(path, IO::FileMode::Write);
        f.Write(fd.ReadToEnd());
        f.Close();
        auto j = Json::FromFile(path);
        SetColorTableFromJson(table, j);
    }
}
