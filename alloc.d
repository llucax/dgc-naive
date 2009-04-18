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

module alloc;

version (Win32)
{
    private import tango.sys.win32.UserGdi;
}
else version (Posix)
{
    private import tango.stdc.posix.sys.mman;
    private import tango.stdc.stdlib;
}
else
{
    private import tango.stdc.stdlib;
}

static if (is(typeof(VirtualAlloc)))
{

    void* mem_alloc(size_t size)
    {
        return VirtualAlloc(null, size, MEM_RESERVE, PAGE_READWRITE);
    }

    /**
     * Free memory allocated with alloc().
     * Returns:
     *      0       success
     *      !=0     failure
     */
    int mem_free(void* ptr, size_t size)
    {
        return cast(int)(VirtualFree(ptr, 0, MEM_RELEASE) == 0);
    }

}
else static if (is(typeof(mmap)))
{

    void* mem_alloc(size_t size)
    {
        void* ptr = mmap(null, size, PROT_READ | PROT_WRITE,
                            MAP_PRIVATE | MAP_ANON, -1, 0);
        if (ptr == MAP_FAILED)
           ptr = null;
        return ptr;
    }

    int mem_free(void* ptr, size_t size)
    {
        return munmap(ptr, size);
    }

}
else static if (is(typeof(valloc)))
{

    void* mem_alloc(size_t size)
    {
        return valloc(size);
    }

    int mem_free(void* ptr, size_t size)
    {
        free(ptr);
        return 0;
    }
}
else static if (is(typeof(malloc)))
{

    // NOTE: This assumes malloc granularity is at least size_t.sizeof.  If
    //       (req_size + PAGESIZE) is allocated, and the pointer is rounded up
    //       to PAGESIZE alignment, there will be space for a void* at the end
    //       after PAGESIZE bytes used by the GC.


    enum { PAGESIZE = 4096 }

    const size_t PAGE_MASK = PAGESIZE - 1;

    void* mem_alloc(size_t size)
    {
        byte* p, q;
        p = cast(byte *) malloc(size + PAGESIZE);
        q = p + ((PAGESIZE - ((cast(size_t) p & PAGE_MASK))) & PAGE_MASK);
        * cast(void**)(q + size) = p;
        return q;
    }

    int mem_free(void* ptr, size_t size)
    {
        free(*cast(void**)(cast(byte*) ptr + size));
        return 0;
    }

}
else
{

    static assert(false, "No supported allocation methods available.");

}

// vim: set et sw=4 sts=4 :
