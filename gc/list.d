/**
 * Singly linked list of Cells.
 *
 * This module implements a simple singly linked list of Cells to be used as
 * live/free list in the Naive Garbage Collector implementation.
 *
 * See_Also:  gc module
 * Copyright: Public Domain
 * License:   Public Domain
 * Authors:   Leandro Lucarella <llucax@gmail.com>
 */

module gc.list;

// Internal imports
private import gc.cell: Cell;


package:

/**
 * Singly linked list of Cells.
 *
 * This is used for live and free lists.
 */
struct List
{

    /// First element in the list.
    Cell* first = null;

    /**
     * Find the first cell for which predicate(cell) is true.
     *
     * Returns a pointer to the cell if found, null otherwise.
     */
    Cell* find(bool delegate(Cell*) predicate)
    {
        auto cell = this.first;
        while (cell !is null) {
            if (predicate(cell))
                return cell;
            cell = cell.next;
        }
        return null;
    }

    /**
     * Find the cell that holds the object pointed by ptr.
     *
     * Returns a pointer to the cell if found, null otherwise.
     */
    Cell* find(void* ptr)
    {
        return this.find((Cell* cell) { return cell.ptr == ptr; });
    }

    /**
     * Link a new cell into the list.
     */
    void link(Cell* cell)
    {
        cell.next = this.first;
        this.first = cell;
    }

    /**
     * Find and remove the first cell for which predicate(cell) is true.
     *
     * If no cell is found, no cell is removed.
     *
     * Returns a pointer to the removed cell if found, null otherwise.
     */
    Cell* pop(bool delegate(Cell*) predicate)
    {
        Cell* prev = null;
        auto cell = this.first;
        while (cell !is null) {
            if (predicate(cell)) {
                if (prev is null)
                    this.first = cell.next;
                else
                    prev.next = cell.next;
                return cell;
            }
            prev = cell;
            cell = cell.next;
        }
        return null;
    }

    /**
     * Find and remove the cell that holds the object pointed by ptr.
     *
     * If no cell is found, no cell is removed.
     *
     * Returns a pointer to the removed cell if found, null otherwise.
     */
    Cell* pop(void* ptr)
    {
        return this.pop((Cell* cell) { return cell.ptr == ptr; });
    }

    /**
     * Find and remove the first cell with a capacity of at least min_size.
     *
     * If no cell is found, no cell is removed.
     *
     * Returns a pointer to the removed cell if found, null otherwise.
     */
    Cell* pop(size_t min_size)
    {
        return this.pop((Cell* cell) { return cell.capacity >= min_size; });
    }

    /**
     * Remove a cell from the list.
     *
     * If the cell was not linked into the list, this method has no effect.
     */
    void unlink(Cell* cell)
    {
        this.pop((Cell* cell2) { return cell is cell2; });
    }

    /**
     * Iterate over the cells in the list.
     *
     * unlink()ing cells from the list while iterating is supported, but
     * link()ing may not work.
     */
    int opApply(int delegate(ref Cell*) dg)
    {
        int result = 0;
        auto cell = this.first;
        while (cell !is null) {
            // this is necessary to allow removing a node while iterating
            auto next = cell.next;
            result = dg(cell);
            if (result)
                break;
            cell = next;
        }
        return result;
    }

}

debug (UnitTest)
{

private:

    import tango.stdc.stdlib: malloc;

    unittest // List
    {
        List l;
        assert (l.first is null);
        assert (l.find(cast(void*) null) is null);
        assert (l.find(cast(void*) &l) is null);
        Cell[5] cells;
        foreach (ref c; cells)
            l.link(&c);
        size_t i = 5;
        foreach (c; l)
            assert (c is &cells[--i]);
    }

} // debug (UnitTest)

// vim: set et sw=4 sts=4 :
