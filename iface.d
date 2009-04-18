/**
 * This module contains a minimal garbage collector implementation according to
 * Tango requirements.  This library is mostly intended to serve as an example,
 * but it is usable in applications which do not rely on a garbage collector
 * to clean up memory (ie. when dynamic array resizing is not used, and all
 * memory allocated with 'new' is freed deterministically with 'delete').
 *
 * Please note that block attribute data must be tracked, or at a minimum, the
 * FINALIZE bit must be tracked for any allocated memory block because calling
 * rt_finalize on a non-object block can result in an access violation.  In the
 * allocator below, this tracking is done via a leading uint bitmask.  A real
 * allocator may do better to store this data separately, similar to the basic
 * GC normally used by Tango.
 *
 * Copyright: Public Domain
 * License:   BOLA
 * Authors:   Leandro Lucarella
 */

module iface;

private {

    import gc: NaiveGC, BlkInfo;

    import tango.stdc.stdlib;
    debug (gc_naive_iface) import tango.stdc.stdio;

    NaiveGC gc;

    class GCLock {} // TODO

}

extern (C) void gc_init()
{
    debug (gc_naive_iface) printf("gc_init()\n");
    gc.init();
}

extern (C) void gc_term()
{
    debug (gc_naive_iface) printf("gc_term()\n");
    gc.term();
}

extern (C) void gc_enable()
{
    debug (gc_naive_iface) printf("gc_enable()\n");
    gc.enable();
}

extern (C) void gc_disable()
{
    debug (gc_naive_iface) printf("gc_disable()\n");
    gc.disable();
}

extern (C) void gc_collect()
{
    debug (gc_naive_iface) printf("gc_collect()\n");
    gc.collect();
}

extern (C) void gc_minimize()
{
    debug (gc_naive_iface) printf("gc_minimize()\n");
    gc.minimize();
}

extern (C) uint gc_getAttr(void* ptr)
{
    debug (gc_naive_iface) printf("gc_getAttr(%p)\n", ptr);
    return gc.getAttr(ptr);
}

// return the old value
extern (C) uint gc_setAttr(void* ptr, uint attr)
{
    debug (gc_naive_iface) printf("gc_setAttr(%p, %u)\n", ptr, attr);
    return gc.setAttr(ptr, attr);
}

extern (C) uint gc_clrAttr(void* ptr, uint attr)
{
    debug (gc_naive_iface) printf("gc_clrAttr(%p, %u)\n", ptr, attr);
    return gc.clrAttr(ptr, attr);
}

extern (C) void* gc_malloc(size_t size, uint attr=0)
{
    debug (gc_naive_iface) printf("gc_malloc(%u, %u)\n", size, attr);
    auto p = gc.malloc(size, attr);
    debug (gc_naive_iface) printf("gc_malloc() -> %p\n", p);
    return p;
}

extern (C) void* gc_calloc(size_t size, uint attr=0)
{
    debug (gc_naive_iface) printf("gc_calloc(%u, %u)\n", size, attr);
    return gc.calloc(size, attr);
}

extern (C) void* gc_realloc(void* ptr, size_t size, uint attr=0)
{
    debug (gc_naive_iface) printf("gc_realloc(%p, %u, %u)\n", ptr, size, attr);
    return gc.realloc(ptr, size, attr);
}

extern (C) size_t gc_extend(void* ptr, size_t min_size, size_t max_size)
{
    debug (gc_naive_iface)
        printf("gc_extend(%p, %u, %u)\n", ptr, min_size, max_size);
    return gc.extend(ptr, min_size, max_size);
}

extern (C) size_t gc_reserve(size_t size)
{
    debug (gc_naive_iface) printf("gc_reserve(%u)\n", size);
    return gc.reserve(size);
}

extern (C) void gc_free(void* ptr)
{
    debug (gc_naive_iface) printf("gc_free(%p)\n", ptr);
    gc.free(ptr);
}

extern (C) void* gc_addrOf(void* ptr)
{
    debug (gc_naive_iface) printf("gc_addrOf(%p)\n", ptr);
    return gc.addrOf(ptr);
}

// TODO: acepta un address que no sea el base?
//       es valido aceptar un ptr que no pertenezca al heap?
extern (C) size_t gc_sizeOf(void* ptr)
{
    debug (gc_naive_iface) printf("gc_sizeOf(%p)\n", ptr);
    return gc.sizeOf(ptr);
}

// TODO: acepta un address que no sea el base?
//       es valido aceptar un ptr que no pertenezca al heap?
extern (C) BlkInfo gc_query(void* ptr)
{
    debug (gc_naive_iface) printf("gc_query(%p)\n", ptr);
    return gc.query(ptr);
}

extern (C) void gc_addRoot(void* ptr)
{
    debug (gc_naive_iface) printf("gc_addRoot(%p)\n", ptr);
    gc.addRoot(ptr);
}

extern (C) void gc_addRange(void* ptr, size_t size)
{
    debug (gc_naive_iface) printf("gc_addRange(%p, %u)\n", ptr, size);
    gc.addRange(ptr, size);
}

extern (C) void gc_removeRoot(void* ptr)
{
    debug (gc_naive_iface) printf("gc_removeRoot(%p)\n", ptr);
    gc.removeRoot(ptr);
}

extern (C) void gc_removeRange(void* ptr)
{
    debug (gc_naive_iface) printf("gc_removeRange(%p)\n", ptr);
    gc.removeRange(ptr);
}

// vim: set et sw=4 sts=4 :
