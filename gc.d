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

module gc;

private {

    import cell: Cell, BlkAttr;
    import list: List;
    import dynarray: DynArray;
    import arch: stack_smaller, push_registers, pop_registers;
    import alloc: mem_alloc, mem_free;

    import stdc = tango.stdc.stdlib;
    import tango.stdc.string: memset, memcpy;
    debug import tango.stdc.stdio: printf;

    alias void delegate(void*, void*) mark_function;
    extern (C) void onOutOfMemoryError();
    extern (C) void rt_finalize(void* p, bool det=true);
    extern (C) void rt_scanStaticData(mark_function mark);
    extern (C) void thread_init();
    extern (C) bool thread_needLock();
    extern (C) void thread_suspendAll();
    extern (C) void thread_resumeAll();
    extern (C) void thread_scanAll(mark_function mark, void* stack_top=null);

    struct RootRange
    {

        void* from;

        void* to;

        int opApply(int delegate(ref void*) dg)
        {
            int result = 0;
            auto from = cast(void**) this.from;
            auto to = cast(void**) this.to;
            // TODO: alignment. The range should be aligned and the size
            //       should be a multiple of the word size. If the later does
            //       not hold, the last bytes that are not enough to build
            //       a complete word should be ignored. Right now we are
            //       doing invalid reads in that cases.
            for (void** current = from; current < to; current++) {
                result = dg(*current);
                if (result)
                    break;
            }
            return result;
        }

    }

}

struct BlkInfo
{
    void*  base;
    size_t size;
    uint   attr;
}

// TODO: ver bien donde desmarkcar/marcar celdas (probablemente en malloc)

struct NaiveGC
{

private:

    List free_list;

    List live_list;

    DynArray!(void*) root_pointers;

    DynArray!(RootRange) root_ranges;

    uint enabled;

    void unmark()
    {
        debug (gc_naive_gc_collect)
            printf("gc.unmark()\n");
        foreach (cell; this.live_list)
            cell.marked = false;
    }

    void mark_all()
    {
        debug (gc_naive_gc_collect)
            printf("gc.mark_all()\n");
        void* stack_top;
        mixin (push_registers("stack_top"));
        thread_suspendAll();
        debug (gc_naive_gc_collect)
            printf("gc.mark_all() - scanning static data\n");
        rt_scanStaticData(&mark_range);
        debug (gc_naive_gc_collect)
            printf("gc.mark_all() - scanning threads stack\n");
        thread_scanAll(&mark_range, stack_top);
        debug (gc_naive_gc_collect)
            printf("gc.mark_all() - scanning root pointers:");
        foreach (ptr; this.root_pointers) {
            debug (gc_naive_gc_collect)
                printf(" %p", ptr);
            this.mark(ptr);
        }
        debug (gc_naive_gc_collect)
            printf("\ngc.mark_all() - scanning root ranges:");
        foreach (range; this.root_ranges) {
            debug (gc_naive_gc_collect)
                printf(" %p-%p", range.from, range.to);
            this.mark_range(range.from, range.to);
        }
        debug (gc_naive_gc_collect)
            printf("\n");
        thread_resumeAll();
        mixin (pop_registers("stack_top"));
    }

    void mark_range(void* from, void* to)
    {
        debug (gc_naive_gc_collect)
            printf("gc.mark_range(%p, %p)\n", from, to);
        foreach (ptr; RootRange(from, to))
            mark(ptr);
    }

    void mark(void* ptr)
    {
        debug (gc_naive_gc_collect_extra)
            printf("gc.mark(%p)\n", ptr);
        Cell* cell = Cell.from_ptr(this.addrOf(ptr));
        if (cell is null)
            return;
        debug (gc_naive_gc_collect)
            printf("gc.mark() - %p cell=%p\n", cell.ptr, cell);
        if (!cell.marked) {
            cell.marked = true;
            debug (gc_naive_gc_collect)
                printf("gc.mark() - cell=%p marked\n", cell);
            if (cell.has_pointers) {
                foreach (ptr; *cell)
                    mark(ptr);
            }
        }
    }

    void sweep()
    {
        debug (gc_naive_gc_collect) {
            printf("gc.sweep()\n\tfree:");
            foreach (cell; this.free_list)
                printf(" %p", cell);
            printf("\n\tlive:");
            foreach (cell; this.live_list)
                printf(" %s%p", cell.marked ? "*\0".ptr : "\0".ptr, cell);
            printf("\n\tfreed:");
        }
        foreach (cell; this.live_list) {
            if (!cell.marked) {
                debug (gc_naive_gc_collect)
                    printf(" %p", cell);
                this.live_list.unlink(cell);
                if (cell.finalize())
                    rt_finalize(cell.ptr, false);
                this.free_list.link(cell);
            }
        }
        debug (gc_naive_gc_collect) {
            printf("\n\tfree:");
            foreach (cell; this.free_list)
                printf(" %p", cell);
            printf("\n\tlive:");
            foreach (cell; this.live_list)
                printf(" %p", cell);
            printf("\n");
        }
    }

public:

    void init()
    {
        // NOTE: The GC must initialize the thread library before its first
        //       collection, and always before returning from gc_init().
        this.enabled = true;
        thread_init();
    }

    void term()
    {
        // Finalization of unreferenced cells is not mandatory by the specs.
        // This implementation guarantees that all live data gets finalized,
        // referenced or unreferenced, at the end of the program.
        //foreach (cell; this.live_list)
        //    if (cell.finalize)
        //         rt_finalize(cell.ptr, false);
    }

    void enable()
    {
        this.enabled++;
        assert (this.enabled > 0);
    }

    void disable()
    {
        assert (this.enabled > 0);
        this.enabled--;
    }

    void collect()
    {
        this.unmark();
        this.mark_all();
        this.sweep();
    }

    void minimize()
    {
        foreach (cell; this.free_list) {
            this.free_list.unlink(cell);
            mem_free(cell, cell.capacity + Cell.sizeof);
        }
    }

    uint getAttr(void* ptr)
    {
        auto cell = this.live_list.find(ptr);
        if (cell)
            return cell.attr;
        return 0;
    }

    // return the old value
    uint setAttr(void* ptr, uint attr)
    {
        auto cell = this.live_list.find(ptr);
        if (cell) {
            auto old = cell.attr;
            cell.attr |= attr;
            return cell.attr;
        }
        return 0;
    }

    uint clrAttr(void* ptr, uint attr)
    {
        auto cell = this.live_list.find(ptr);
        if (cell) {
            auto old = cell.attr;
            cell.attr &= ~attr;
            return cell.attr;
        }
        return 0;
    }

    void* malloc(size_t size, uint attr=0)
    {
        debug (gc_naive_gc_malloc)
            printf("gc.malloc(%u, %u)\n", size, attr);
        if (size == 0)
            return null;

        // Find a free cell in the free list with enough space
        auto cell = this.free_list.pop(size);
        if (cell)
            goto success;
        debug (gc_naive_gc_malloc)
            printf("gc.malloc() - no cell available in the free list\n");

        // No room in the free list found, trigger a collection
        this.collect();

        // Try again in the free list
        cell = this.free_list.pop(size);
        if (cell)
            goto success;
        debug (gc_naive_gc_malloc)
            printf("gc.malloc() - after collection, still no free cell\n");

        // No luck still, allocate new memory
        cell = cast(Cell*) mem_alloc(size + Cell.sizeof);
        if (cell)
            goto success;
        debug (gc_naive_gc_malloc)
            printf("gc.malloc() - can't malloc() from the OS\n");

        // No memory
        onOutOfMemoryError();

        return null;

    success:
        cell.size = size;
        if (cell.capacity == 0) // fresh cell
            cell.capacity = size;
        cell.attr = cast(BlkAttr) attr;
        cell.marked = false;
        this.live_list.link(cell);

        debug (gc_naive_gc_collect) {
            printf("gc.malloc() -> %p (cell=%p)\n\tfree:", cell.ptr, cell);
            foreach (cell; this.free_list)
                printf(" %p", cell);
            printf(" | live:");
            foreach (cell; this.live_list)
                printf(" %p", cell);
            printf("\n");
        }

        return cell.ptr;
    }

    void* calloc(size_t size, uint attr=0)
    {
        void* ptr = this.malloc(size, attr);

        if (ptr is null)
            onOutOfMemoryError();
        else
            memset(ptr, 0, size);

        return ptr;
    }

    void* realloc(void* ptr, size_t size, uint attr=0)
    {
        if (ptr is null)
            return this.malloc(size, attr);

        if (size == 0) {
            this.free(ptr);
            return null;
        }

        auto cell = this.live_list.find(ptr);
        assert (cell);

        if (cell.capacity >= size) {
            cell.size = size;
            return cell;
        }

        Cell* new_cell = cast(Cell*) mem_alloc(size + Cell.sizeof);
        if (new_cell is null)
            onOutOfMemoryError();

        memcpy(new_cell, cell, size + Cell.sizeof);
        new_cell.size = size;
        new_cell.capacity = size;

        this.live_list.link(new_cell);

        this.free(cell);

        return new_cell.ptr;
    }

    size_t extend(void* ptr, size_t min_size, size_t max_size)
    {
        assert (min_size <= max_size);
        // There is no possible extension of the capacity for this
        // implementation.
        return 0;
    }

    size_t reserve(size_t size)
    {
        assert (size > 0);
        auto cell = cast(Cell*) mem_alloc(size + Cell.sizeof);
        if (!cell)
            return 0;
        cell.size = size;
        cell.capacity = size;
        this.free_list.link(cell);
        return size;
    }

    void free(void* ptr)
    {
        if (ptr is null)
            return;

        auto cell = this.live_list.pop(ptr);
        assert (cell);

        this.free_list.link(cell);
    }

    void* addrOf(void* ptr)
    {
        if (ptr is null)
            return null;

        bool in_range(Cell* cell)
        {
            return ptr >= cell.ptr && ptr < (cell.ptr + cell.size);
        }

        auto cell = this.live_list.find(&in_range);
        if (cell)
            return cell.ptr;

        return null;
    }

    // TODO: acepta un address que no sea el base?
    //       es valido aceptar un ptr que no pertenezca al heap?
    //       (contestado en basic/gcx.d, pero es estandar?)
    size_t sizeOf(void* ptr)
    {
        auto cell = this.live_list.find(ptr);
        if (cell)
            return cell.capacity;
        return 0;
    }

    // TODO: acepta un address que no sea el base?
    //       es valido aceptar un ptr que no pertenezca al heap?
    BlkInfo query(void* ptr)
    {
        BlkInfo blk_info;

        auto cell = this.live_list.find(ptr);
        if (cell) {
            blk_info.base = cell.ptr;
            blk_info.size = cell.capacity;
            blk_info.attr = cell.attr;
        }

        return blk_info;
    }

    void addRoot(void* ptr)
    {
        this.root_pointers.append(ptr);
    }

    void addRange(void* ptr, size_t size)
    {
        this.root_ranges.append(RootRange(ptr, ptr + size));
    }

    void removeRoot(void* ptr)
    {
        this.root_pointers.remove(ptr);
    }

    void removeRange(void* ptr)
    {
        foreach (range; this.root_ranges) {
            if (range.from is ptr) {
                this.root_ranges.remove(range);
                break;
            }
        }
    }

}

// vim: set et sw=4 sts=4 :
