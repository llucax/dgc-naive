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

module dynarray;

private import tango.stdc.stdlib: realloc;
private import tango.stdc.string: memmove;
private extern (C) void onOutOfMemoryError();

package:

struct DynArray(T)
{

    T* data = null;

    size_t capacity = 0;

    size_t size = 0;

    invariant
    {
        assert (this.data);
        assert (this.capacity >= this.size);
    }

    void append(T x)
    {
        if (this.size == this.capacity)
            this.expand();
        this.data[this.size] = x;
        this.size++;
    }

    void remove(T x)
    {
        for (size_t i = 0; i < this.size; i++) {
            if (this.data[i] == x) {
                this.size--;
                memmove(this.data + i, this.data + i + T.sizeof,
                                (this.size - i) * T.sizeof);
                return;
            }
        }
    }

    void expand(size_t new_capacity=0)
    {
        if (new_capacity == 0)
            new_capacity = this.size * 2;
            if (new_capacity == 0)
                new_capacity = 4;
        T* new_data = cast(T*) realloc(this.data, new_capacity);
        if (new_data is null)
            onOutOfMemoryError();
        this.data = new_data;
        this.capacity = new_capacity;
    }

    int opApply(int delegate(ref T) dg)
    {
        int result = 0;
        for (size_t i = 0; i < this.size; i++) {
            result = dg(this.data[i]);
            if (result)
                break;
        }
        return result;
    }

}

// vim: set et sw=4 sts=4 :
