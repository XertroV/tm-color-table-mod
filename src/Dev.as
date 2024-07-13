CMwNod@ Dev_GetOffsetNodSafer(CMwNod@ nod, uint16 offset) {
    if (nod is null) {
        return null;
    }
    auto ptr = Dev::GetOffsetUint64(nod, offset);
    if (ptr == 0 || ptr % 8 != 0 || ptr < 0xFFFFFFFF || ptr > 0x7FFFFFFF0000) {
        return null;
    }
    return Dev::GetOffsetNod(nod, offset);
}
