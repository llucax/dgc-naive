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

module cell;

package:

enum BlkAttr : uint
{
    FINALIZE = 0b0000_0001,
    NO_SCAN  = 0b0000_0010,
    NO_MOVE  = 0b0000_0100,
    ALL_BITS = 0b1111_1111,
}

struct Cell
{

    size_t size = 0;

    size_t capacity = 0;

    bool marked = true;

    BlkAttr attr = cast(BlkAttr) 0;

    Cell* next = null;

    static Cell* from_ptr(void* ptr)
    {
        if (ptr is null)
            return null;
        return cast(Cell*) (cast(byte*) ptr - Cell.sizeof);
    }

    void* ptr()
    {
        return cast(void*) (cast(byte*) this + Cell.sizeof);
    }

    bool finalize()
    {
        return cast(bool) (this.attr & BlkAttr.FINALIZE);
    }

    bool has_pointers()
    {
        return !(this.attr & BlkAttr.NO_SCAN);
    }

    int opApply(int delegate(ref void*) dg)
    {
        int result = 0;
        auto from = cast(void**) this.ptr;
        auto to = cast(void**) this.ptr + this.size;
        // TODO: alignment. The range should be aligned and the size
        //       should be a multiple of the word size. If the later does
        //       not hold, the last bytes that are not enough to build
        //       a complete word should be ignored. Right now we are
        //       doing invalid reads in that cases.
        for (auto current = from; current < to; current++) {
            result = dg(*current);
            if (result)
                break;
        }
        return result;
    }

}

// vim: set et sw=4 sts=4 :
