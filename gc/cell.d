/**
 * Memory Cell header manipulation.
 *
 * This module has the Cell header definition and other support stuff (like
 * BlkAttr) for the Naive Garbage Collector implementation. The Cell header has
 * all the information needed for the bookkeeping of the GC allocated memory,
 * like the mark bit, if the cell contents should be finalized or if it has
 * pointers that should be scanned, etc.
 *
 * See_Also:  gc module
 * Copyright: Public Domain
 * License:   Public Domain
 * Authors:   Leandro Lucarella <llucax@gmail.com>
 */

module gc.cell;

import cstdlib = tango.stdc.stdlib;

package:

/**
 * Iterates a range of memory interpreting it as an array of void*.
 *
 * This function is designed to be used as a opApply implementation.
 */
int op_apply_ptr_range(void* from, void* to, int delegate(ref void*) dg)
{
    int result = 0;
    auto start = cast(void**) from;
    auto end = cast(void**) to;
    // since we sweep the memory range in word-sized steps, we need to make
    // sure we don't scan for pointers beyond the end of the memory range
    for (auto current = start; current + 1 <= end; current++) {
        result = dg(*current);
        if (result)
            break;
    }
    return result;
}

/// Memory block (cell) attributes.
enum BlkAttr : uint
{
    /// All attributes disabled.
    NONE     = 0b0000_0000,
    /// The cell is an object with a finalizer.
    FINALIZE = 0b0000_0001,
    /// The cell has no pointers.
    NO_SCAN  = 0b0000_0010,
    /// The cell should not be moved (unimplemented).
    NO_MOVE  = 0b0000_0100,
    /// All attributes enabled.
    ALL      = 0b1111_1111,
}

/**
 * Memory block (cell) header.
 *
 * All memory cells in the GC heap have this header.
 */
struct Cell
{

    /// Size of the object stored in this memory cell.
    size_t size = 0;

    /// Real size of the memory cell.
    size_t capacity = 0;

    /// Mark bit.
    bool marked = true;

    /// Cell attributes.
    BlkAttr attr = BlkAttr.NONE;

    /// Next cell (this is used for free/live lists linking).
    Cell* next = null;

    invariant()
    {
        assert (this.size > 0);
        assert (this.capacity >= this.size);
    }

    /**
     * Allocate a new cell.
     *
     * Allocate a new cell (asking for fresh memory to the OS). The cell is
     * initialized with the provided size and attributes. The capacity can be
     * larger than the requested size, though. The attribute marked is set to
     * true (assuming the cell will be used as soon as allocated) and next is
     * set to null.
     *
     * Returns a pointer to the new cell or null if it can't allocate new
     * memory.
     */
    static Cell* alloc(size_t size, uint attr = 0)
    {
        auto cell = cast(Cell*) cstdlib.malloc(size + Cell.sizeof);
        if (cell is null)
            return null;
        cell.capacity = size;
        cell.size = size;
        cell.attr = cast(BlkAttr) attr;
        cell.marked = true;
        cell.next = null;
        return cell;
    }

    /// Free a cell allocated by Cell.alloc().
    static void free(Cell* cell)
    {
        cstdlib.free(cell);
    }

    /**
     * Get a cell pointer for the cell that stores the object pointed to by
     * ptr.
     *
     * If ptr is null, null is returned.
     */
    static Cell* from_ptr(void* ptr)
    {
        if (ptr is null)
            return null;
        return cast(Cell*) (cast(byte*) ptr - Cell.sizeof);
    }

    /// Get the base address of the object stored in the cell.
    void* ptr()
    {
        return cast(void*) (cast(byte*) this + Cell.sizeof);
    }

    /// Return true if the cell should be finalized, false otherwise.
    bool has_finalizer()
    {
        return cast(bool) (this.attr & BlkAttr.FINALIZE);
    }

    /// Return true if the cell should may have pointers, false otherwise.
    bool has_pointers()
    {
        return !(this.attr & BlkAttr.NO_SCAN);
    }

    /**
     * Iterates over the objects pointers.
     *
     * Current implementation interprets the whole object as if it were
     * an array of void*.
     */
    int opApply(int delegate(ref void*) dg)
    {
        return op_apply_ptr_range(this.ptr, this.ptr + this.size, dg);
    }

}

debug (UnitTest)
{

private:

    unittest // op_apply_ptr_range()
    {
        size_t[10] v;
        int i = 5;
        foreach (ref x; v)
            x = i++;
        i = 5;
        int r = op_apply_ptr_range(v.ptr, v.ptr + 10,
                (ref void* ptr) {
                    assert (cast (size_t) ptr == i++);
                    return 0;
                });
    }

    unittest // Cell
    {
        auto N = 10;
        auto size = N * size_t.sizeof;
        auto cell = Cell.alloc(size, BlkAttr.FINALIZE | BlkAttr.NO_SCAN);
        assert (cell !is null);
        assert (cell.ptr is cell + 1);
        for (int i = 0; i < N; ++i) {
            auto ptr = cast(size_t*) cell.ptr + i;
            *ptr = i + N;
        }
        size_t i = N;
        foreach (void* ptr; *cell) {
            assert (cast(size_t) ptr == i++);
        }
        assert (*(cast(size_t*) cell.ptr) == N);
        assert (cell.has_finalizer());
        assert (!cell.has_pointers());
        assert (cell is Cell.from_ptr(cell.ptr));
    }

} // debug (UnitTest)

// vim: set et sw=4 sts=4 :
