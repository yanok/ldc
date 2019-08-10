/**
 * Compiler implementation of the D programming language
 * http://dlang.org
 *
 * Copyright: Copyright (C) 1999-2019 by The D Language Foundation, All Rights Reserved
 * Authors:   Walter Bright, http://www.digitalmars.com
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:    $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/root/stringtable.d, root/_stringtable.d)
 * Documentation:  https://dlang.org/phobos/dmd_root_stringtable.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/root/stringtable.d
 */

module dmd.root.stringtable;

import core.stdc.string;
import dmd.root.rmem, dmd.root.hash;

private enum POOL_BITS = 12;
private enum POOL_SIZE = (1U << POOL_BITS);

/*
Returns the smallest integer power of 2 larger than val.
if val > 2^^63 it enters and endless loop since 2^^64 does not fit in a size_t
*/
private size_t nextpow2(size_t val) pure nothrow @nogc @safe
{
    size_t res = 1;
    while (res < val)
        res <<= 1;
    return res;
}

unittest
{
    assert(nextpow2(0) == 1);
    assert(nextpow2(0xFFFF) == (1 << 16));
    assert(nextpow2(1UL << 63) == 1UL << 63);
    // note: nextpow2((1UL << 63) + 1) results in an endless loop
}

private enum loadFactorNumerator = 8;
private enum loadFactorDenominator = 10;        // for a load factor of 0.8

private struct StringEntry
{
    uint hash;
    uint vptr;
}

// StringValue is a variable-length structure. It has neither proper c'tors nor a
// factory method because the only thing which should be creating these is StringTable.
struct StringValue
{
    void* ptrvalue;
    private size_t length;

nothrow:
pure:
@nogc:
    char* lstring() return
    {
        return cast(char*)(&this + 1);
    }

    size_t len() const @safe
    {
        return length;
    }

    const(char)* toDchars() const return
    {
        return cast(const(char)*)(&this + 1);
    }

    /// Returns: The content of this entry as a D slice
    inout(char)[] toString() inout
    {
        return (cast(inout(char)*)(&this + 1))[0 .. length];
    }
}

struct StringTable
{
private:
    StringEntry[] table;
    ubyte*[] pools;
    size_t nfill;
    size_t count;
    size_t countTrigger;   // amount which will trigger growing the table

public:
nothrow:
    void _init(size_t size = 0) pure
    {
        size = nextpow2((size * loadFactorDenominator) / loadFactorNumerator);
        if (size < 32)
            size = 32;
        table = (cast(StringEntry*)mem.xcalloc(size, (table[0]).sizeof))[0 .. size];
        countTrigger = (table.length * loadFactorNumerator) / loadFactorDenominator;
        pools = null;
        nfill = 0;
        count = 0;
    }

    void reset(size_t size = 0) pure
    {
        freeMem();
        _init(size);
    }

    ~this() pure
    {
        freeMem();
    }

    /**
    Looks up the given string in the string table and returns its associated
    value.

    Params:
     s = the string to look up
     length = the length of $(D_PARAM s)
     str = the string to look up

    Returns: the string's associated value, or `null` if the string doesn't
     exist in the string table
    */
    inout(StringValue)* lookup(const(char)[] str) inout pure @nogc
    {
        const(size_t) hash = calcHash(str);
        const(size_t) i = findSlot(hash, str);
        // printf("lookup %.*s %p\n", cast(int)str.length, str.ptr, table[i].value ?: null);
        return getValue(table[i].vptr);
    }

    /// ditto
    inout(StringValue)* lookup(const(char)* s, size_t length) inout pure @nogc
    {
        return lookup(s[0 .. length]);
    }

    /**
    Inserts the given string and the given associated value into the string
    table.

    Params:
     s = the string to insert
     length = the length of $(D_PARAM s)
     ptrvalue = the value to associate with the inserted string
     str = the string to insert
     value = the value to associate with the inserted string

    Returns: the newly inserted value, or `null` if the string table already
     contains the string
    */
    StringValue* insert(const(char)[] str, void* ptrvalue) pure
    {
        const(size_t) hash = calcHash(str);
        size_t i = findSlot(hash, str);
        if (table[i].vptr)
            return null; // already in table
        if (++count > countTrigger)
        {
            grow();
            i = findSlot(hash, str);
        }
        table[i].hash = hash;
        table[i].vptr = allocValue(str, ptrvalue);
        // printf("insert %.*s %p\n", cast(int)str.length, str.ptr, table[i].value ?: NULL);
        return getValue(table[i].vptr);
    }

    /// ditto
    StringValue* insert(const(char)* s, size_t length, void* value) pure
    {
        return insert(s[0 .. length], value);
    }

    StringValue* update(const(char)[] str) pure
    {
        const(size_t) hash = calcHash(str);
        size_t i = findSlot(hash, str);
        if (!table[i].vptr)
        {
            if (++count > countTrigger)
            {
                grow();
                i = findSlot(hash, str);
            }
            table[i].hash = hash;
            table[i].vptr = allocValue(str, null);
        }
        // printf("update %.*s %p\n", cast(int)str.length, str.ptr, table[i].value ?: NULL);
        return getValue(table[i].vptr);
    }

    StringValue* update(const(char)* s, size_t length) pure
    {
        return update(s[0 .. length]);
    }

    /********************************
     * Walk the contents of the string table,
     * calling fp for each entry.
     * Params:
     *      fp = function to call. Returns !=0 to stop
     * Returns:
     *      last return value of fp call
     */
    int apply(int function(const(StringValue)*) nothrow fp)
    {
        foreach (const se; table)
        {
            if (!se.vptr)
                continue;
            const sv = getValue(se.vptr);
            int result = (*fp)(sv);
            if (result)
                return result;
        }
        return 0;
    }

    /// ditto
    extern(D) int opApply(scope int delegate(const(StringValue)*) nothrow dg)
    {
        foreach (const se; table)
        {
            if (!se.vptr)
                continue;
            const sv = getValue(se.vptr);
            int result = dg(sv);
            if (result)
                return result;
        }
        return 0;
    }

private:
nothrow:
pure:
    /// Free all memory in use by this StringTable
    void freeMem()
    {
        foreach (pool; pools)
            mem.xfree(pool);
        mem.xfree(table.ptr);
        mem.xfree(pools.ptr);
        table = null;
        pools = null;
    }

    uint allocValue(const(char)[] str, void* ptrvalue)
    {
        const(size_t) nbytes = StringValue.sizeof + str.length + 1;
        if (!pools.length || nfill + nbytes > POOL_SIZE)
        {
            pools = (cast(ubyte**) mem.xrealloc(pools.ptr, (pools.length + 1) * (pools[0]).sizeof))[0 .. pools.length + 1];
            pools[$-1] = cast(ubyte*) mem.xmalloc(nbytes > POOL_SIZE ? nbytes : POOL_SIZE);
            nfill = 0;
        }
        StringValue* sv = cast(StringValue*)&pools[$ - 1][nfill];
        sv.ptrvalue = ptrvalue;
        sv.length = str.length;
        .memcpy(sv.lstring(), str.ptr, str.length);
        sv.lstring()[str.length] = 0;
        const(uint) vptr = cast(uint)(pools.length << POOL_BITS | nfill);
        nfill += nbytes + (-nbytes & 7); // align to 8 bytes
        return vptr;
    }

    inout(StringValue)* getValue(uint vptr) inout @nogc
    {
        if (!vptr)
            return null;
        const(size_t) idx = (vptr >> POOL_BITS) - 1;
        const(size_t) off = vptr & POOL_SIZE - 1;
        return cast(inout(StringValue)*)&pools[idx][off];
    }

    size_t findSlot(hash_t hash, const(char)[] str) const pure @nogc
    {
        // quadratic probing using triangular numbers
        // http://stackoverflow.com/questions/2348187/moving-from-linear-probing-to-quadratic-probing-hash-collisons/2349774#2349774
        for (size_t i = hash & (table.length - 1), j = 1;; ++j)
        {
            const(StringValue)* sv;
            auto vptr = table[i].vptr;
            if (!vptr || table[i].hash == hash && (sv = getValue(vptr)).length == str.length && .memcmp(str.ptr, sv.toDchars(), str.length) == 0)
                return i;
            i = (i + j) & (table.length - 1);
        }
    }

    void grow()
    {
        const odim = table.length;
        auto otab = table;
        const ndim = table.length * 2;
        countTrigger = (ndim * loadFactorNumerator) / loadFactorDenominator;
        table = (cast(StringEntry*)mem.xcalloc(ndim, (table[0]).sizeof))[0 .. ndim];
        foreach (const se; otab[0 .. odim])
        {
            if (!se.vptr)
                continue;
            const sv = getValue(se.vptr);
            table[findSlot(se.hash, sv.toString())] = se;
        }
        mem.xfree(otab.ptr);
    }
}

nothrow unittest
{
    StringTable tab;
    tab._init(10);

    // construct two strings with the same text, but a different pointer
    const(char)[6] fooBuffer = "foofoo";
    const(char)[] foo = fooBuffer[0 .. 3];
    const(char)[] fooAltPtr = fooBuffer[3 .. 6];

    assert(foo.ptr != fooAltPtr.ptr);

    // first insertion returns value
    assert(tab.insert(foo, cast(void*) foo.ptr).ptrvalue == foo.ptr);

    // subsequent insertion of same string return null
    assert(tab.insert(foo.ptr, foo.length, cast(void*) foo.ptr) == null);
    assert(tab.insert(fooAltPtr, cast(void*) foo.ptr) == null);

    const lookup = tab.lookup("foo");
    assert(lookup.ptrvalue == foo.ptr);
    assert(lookup.len == 3);
    assert(lookup.toString() == "foo");

    assert(tab.lookup("bar") == null);
    tab.update("bar".ptr, "bar".length);
    assert(tab.lookup("bar").ptrvalue == null);

    tab.reset(0);
    assert(tab.lookup("foo".ptr, "foo".length) == null);
    //tab.insert("bar");
}

nothrow unittest
{
    StringTable tab;
    tab._init(100);

    enum testCount = 2000;

    char[2 * testCount] buf;

    foreach(i; 0 .. testCount)
    {
        buf[i * 2 + 0] = cast(char) (i % 256);
        buf[i * 2 + 1] = cast(char) (i / 256);
        auto toInsert = cast(const(char)[]) buf[i * 2 .. i * 2 + 2];
        tab.insert(toInsert, cast(void*) i);
    }

    foreach(i; 0 .. testCount)
    {
        auto toLookup = cast(const(char)[]) buf[i * 2 .. i * 2 + 2];
        assert(tab.lookup(toLookup).ptrvalue == cast(void*) i);
    }
}

nothrow unittest
{
    StringTable tab;
    tab._init(10);
    tab.insert("foo", cast(void*) 4);
    tab.insert("bar", cast(void*) 6);

    static int resultFp = 0;
    int resultDg = 0;
    static bool returnImmediately = false;

    int function(const(StringValue)*) nothrow applyFunc = (const(StringValue)* s)
    {
        resultFp += cast(int) s.ptrvalue;
        return returnImmediately;
    };

    scope int delegate(const(StringValue)*) nothrow applyDeleg = (const(StringValue)* s)
    {
        resultDg += cast(int) s.ptrvalue;
        return returnImmediately;
    };

    tab.apply(applyFunc);
    tab.opApply(applyDeleg);

    assert(resultDg == 10);
    assert(resultFp == 10);

    returnImmediately = true;

    tab.apply(applyFunc);
    tab.opApply(applyDeleg);

    // Order of string table iteration is not specified, either foo or bar could
    // have been visited first.
    assert(resultDg == 14 || resultDg == 16);
    assert(resultFp == 14 || resultFp == 16);
}
