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

module list;

private import cell: Cell;
private import alloc: mem_free;

struct List
{

    Cell* first;

    Cell* find(bool delegate(Cell*) predicate)
    {
        auto cell = this.first;
        while (cell) {
            if (predicate(cell))
                return cell;
            cell = cell.next;
        }
        return null;
    }

    Cell* find(void* ptr)
    {
        return this.find((Cell* cell) { return cell.ptr == ptr; });
    }

    void link(Cell* cell)
    {
        cell.next = this.first;
        this.first = cell;
    }

    Cell* pop(bool delegate(Cell*) predicate)
    {
        Cell* prev = null;
        auto cell = this.first;
        while (cell) {
            if (predicate(cell)) {
                if (prev)
                    prev.next = cell.next;
                else
                    this.first = cell.next;
                return cell;
            }
            prev = cell;
            cell = cell.next;
        }
        return null;
    }

    Cell* pop(void* ptr)
    {
        return this.pop((Cell* cell) { return cell.ptr == ptr; });
    }

    Cell* pop(size_t min_size)
    {
        return this.pop((Cell* cell) { return cell.capacity >= min_size; });
    }

    void unlink(Cell* cell)
    {
        this.pop((Cell* cell2) { return cell is cell2; });
    }

    void swap(Cell* old_cell, Cell* new_cell)
    {
        Cell* prev = null;
        auto cell = this.first;
        while (cell) {
            if (cell is old_cell) {
                new_cell.next = cell.next;
                if (prev)
                    prev.next = new_cell;
                else
                    this.first = new_cell;
                return;
            }
            prev = cell;
            cell = cell.next;
        }
    }

    int opApply(int delegate(ref Cell*) dg)
    {
        int result = 0;
        auto cell = this.first;
        while (cell) {
            // this is necessary to allow removing node while iterating
            auto next = cell.next;
            result = dg(cell);
            if (result)
                break;
            cell = next;
        }
        return result;
    }

}

// vim: set et sw=4 sts=4 :
