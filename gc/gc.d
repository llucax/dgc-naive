/**
 * Naive Garbage Collector implementation.
 *
 * This module implements a Naive Garbage Collector. The idea behind this
 * implementation is to document all the bookkeeping and considerations that
 * have to be taken in order to implement a garbage collector for D.
 *
 * The garbage collector algorithm itself is extremely simple to make it
 * easier to focus on the specifics of D. A completely naive mark and sweep
 * algorithm is used, with a recursive mark phase. The code is extremely
 * inefficient in order to keep it clean, and easy to read and understand.
 *
 * The implementation is split in several modules to ease the reading even
 * more. All architecture/compiler specific code is done in the arch module,
 * in order to avoid confusing version statements all over the places. The
 * cell module has all the code related to the memory cells header. dynarray
 * is another support module which holds the implementation of a simple
 * dynamic array used to store root pointers and ranges. The list module holds
 * a simple singly linked list (of cells) implementation to store the live and
 * free lists. Finally, the iface module is the one with the C interface to
 * comply with the Tango/Druntime GC specification.
 *
 * Copyright: Public Domain
 * License:   Public Domain
 * Authors:   Leandro Lucarella <llucax@gmail.com>
 */

module gc.gc;

private:

// Internal imports
import gc.cell: Cell, BlkAttr, op_apply_ptr_range;
import gc.list: List;
import gc.dynarray: DynArray;
import gc.arch: push_registers, pop_registers;

// Standard imports
import cstdlib = tango.stdc.stdlib;
import cstring = tango.stdc.string;

// Debug imports

/*
 * These are external functions coming from the D/Tango runtime. It's pretty
 * intuitive what they do based on their names, for more details please
 * refer to the functions documentation.
 */
alias void delegate(void*, void*) mark_function;
extern (C) void onOutOfMemoryError();
extern (C) void rt_finalize(void* p, bool det=true);
extern (C) void rt_scanStaticData(mark_function mark);
extern (C) void thread_init();
extern (C) bool thread_needLock();
extern (C) void thread_suspendAll();
extern (C) void thread_resumeAll();
extern (C) void thread_scanAll(mark_function mark, void* stack_top=null);

/**
 * A range of memory that should be scanned for pointers.
 *
 * This object is iterable, yielding a pointer (void*) for each iteration.
 */
struct RootRange
{

    /// Beginning of the memory range
    void* from;

    /// End of the memory range
    void* to;

    /// Iterate over a memory range applying dg to its elements
    int opApply(int delegate(ref void*) dg)
    {
        return op_apply_ptr_range(this.from, this.to, dg);
    }

}


package:


/**
 * Information on a block of memory.
 *
 * This is part of the GC specification, it's used for the query() method.
 *
 * Standards: Tango/Druntime specs
 */
struct BlkInfo
{

    /// Base address of the block
    void* base;

    /// Size of the block (this is the total capacity, not the requested size)
    size_t size;

    /**
     * Memory block attributes
     *
     * See_Also: cell.BlkAttr for possible values
     */
    uint attr;

}


/**
 * GC implementation.
 *
 * This object contains the whole GC implementation. This is instantiated in
 * the iface module as a global variable to provide the GC services.
 *
 * This implementation is designed to be extremely simple. The algorithm
 * implemented is the most basic stop-the-world mark-sweep known.
 *
 * Memory is organized in cells. Each cell has a header where all the
 * bookkeeping information is stored (like the mark bit, cell attributes,
 * capacity, etc.), and the memory allocated for the requested memory itself.
 *
 * Two lists of cells are kept: free list and live list.
 *
 * The free list store cells known not to be referenced by the program. The
 * live list stores cells that were referenced by the program at the end of
 * the last collection (and just allocated cells).
 *
 * The root set is composed by several elements:
 *
 * $(UL
 *      $(LI Static data)
 *      $(LI Threads stack)
 *      $(LI Registers)
 *      $(LI Root pointers)
 *      $(LI Root ranges)
 * )
 *
 * Root pointers and ranges are user-defined.
 *
 * See_Also:
 *
 *  $(UL
 *      $(LI cell.Cell for the cell header layout)
 *      $(LI collect() for the main collection algorithm)
 *      $(LI )
 * )
 *
 */
struct GC
{

private:

    /// List of free cells.
    List free_list;

    /// List of live cells.
    List live_list;

    /// Single root pointers.
    DynArray!(void*) root_pointers;

    /// Root ranges.
    DynArray!(RootRange) root_ranges;

    /**
     * "Flag" to indicate when the GC is disabled.
     *
     * This is a number because calls to enable() and disable() can be
     * recursive. The number of calls to enable() should match the number of
     * calls to disable(), though, if you want the GC to be effectively
     * enabled again.
     */
    uint disabled = 0;

    /**
     * Remove the mark bit to all the live cells.
     *
     * This is done before starting the mark phase.
     *
     * See_Also:
     *
     *  $(UL
     *      $(LI collect() for the main collect algorithm)
     *      $(LI mark_all() for details on the marking phase)
     *  )
     */
    void unmark()
    {
        foreach (cell; this.live_list)
            cell.marked = false;
    }

    /**
     * Mark all live data (pausing all threads)
     *
     * This methods start marking following all the known roots:
     *
     *  $(UL
     *      $(LI Static data)
     *      $(LI Threads stack)
     *      $(LI Registers)
     *      $(LI Root pointers)
     *      $(LI Root ranges)
     *  )
     *
     * Note that the registers are pushed into the stack to get scanned.
     *
     * This is the complete mark phase. The algorithm roughly does:
     *
     *  $(OL
     *      $(LI Push registers into the stack)
     *      $(LI Pause all threads (but the current one, of course))
     *      $(LI Scan the static data)
     *      $(LI Scan all threads stack)
     *      $(LI Scan the root pointers and ranges)
     *      $(LI Resume all threads)
     *      $(LI Pop the registers from the stack)
     *  )
     *
     *
     * See_Also:
     *
     *  $(UL
     *      $(LI collect() for the main collect algorithm)
     *      $(LI mark() for details on the marking algorithm)
     *      $(LI sweep() for details on the sweep phase)
     *  )
     */
    void mark_all()
    {
        void* stack_top;
        mixin (push_registers("stack_top"));
        thread_suspendAll();
        rt_scanStaticData(&mark_range);
        thread_scanAll(&mark_range, stack_top);
        foreach (ptr; this.root_pointers) {
            this.mark(ptr);
        }
        foreach (range; this.root_ranges) {
            this.mark_range(range.from, range.to);
        }
        thread_resumeAll();
        mixin (pop_registers("stack_top"));
    }

    /**
     * Wrapper for mark() over a range, needed by some runtime functions.
     *
     * This function is used as a delegate to be passed to rt_scanStaticData()
     * and thread_scanAll(), because they expect a function taking 2 pointers.
     *
     * This extremely inefficient on purpose. The goal of this implementation
     * is simplicity, nor performance.
     *
     * See_Also:
     *  $(UL
     *      $(LI mark() for details on the marking algorithm)
     *  )
     */
    void mark_range(void* from, void* to)
    {
        foreach (ptr; RootRange(from, to))
            mark(ptr);
    }

    /**
     * Mark all cells accessible from a pointer.
     *
     * This is the mark algorithm itself. It's recursive and dumb as a log. No
     * care is taken in regards to stack overflows. This is the first example
     * in text books.
     *
     * Marking is done with all threads stopped.
     *
     * See_Also:
     *  $(UL
     *      $(LI collect() for the main collect algorithm)
     *      $(LI mark_all() for details on the marking phase)
     *      $(LI sweep() for details on the sweep phase)
     *  )
     */
    void mark(void* ptr)
    {
        Cell* cell = Cell.from_ptr(this.addrOf(ptr));
        if (cell is null)
            return;
        if (!cell.marked) {
            cell.marked = true;
            if (cell.has_pointers) {
                foreach (ptr; *cell)
                    mark(ptr);
            }
        }
    }

    /**
     * Move unreferenced live objects to the free list (calling finalizers).
     *
     * This is the sweep phase. It's very simple, it just searches the live
     * list and move unmarked cells to the free list. This function is in
     * charge of calling finalizers too, through the rt_finalize() runtime
     * function.
     *
     * Sweeping is done concurrently with the mutator threads.
     *
     * See_Also:
     *  $(UL
     *      $(LI collect() for the main collect algorithm)
     *      $(LI mark_all() for details on the marking phase)
     *  )
     */
    void sweep()
    {
        foreach (cell; this.live_list) {
            if (!cell.marked) {
                this.live_list.unlink(cell);
                if (cell.has_finalizer)
                    rt_finalize(cell.ptr, false);
                this.free_list.link(cell);
            }
        }
    }


public:

    /**
     * Initialize the GC.
     *
     * This initializes the thread library too, as requested by the
     * Tango/Druntime specs.
     */
    void init()
    {
        this.disabled = 0;
        thread_init();
    }

    /**
     * Terminate the GC.
     *
     * Finalization of unreferenced cells is not mandatory by the specs.
     * This implementation guarantees that all finalizers are called, at least
     * at program exit (i.e. at GC termination).
     *
     * The specs says that "objects referenced from the data segment never get
     * collected by the GC". While this is true for this implementation,
     * finalizers are called for objects referenced from the data segment at
     * program exit.
     *
     * There could be some problems with this, in very strange situations. For
     * a more complete discussion about the topic please take a look at the
     * bug 2858: http://d.puremagic.com/issues/show_bug.cgi?id=2858
     */
    void term()
    {
        foreach (cell; this.live_list)
            if (cell.has_finalizer)
                rt_finalize(cell.ptr, false);
        // Let the OS free the memory on exit.
    }

    /**
     * Enable the GC.
     *
     * When the GC is enabled, a collection is triggered when malloc() can't
     * find room in the free list to fulfill the requested size.
     *
     * enable() and disable() can be called recursively. The number of calls
     * to enable() should match the number of calls to disable(), though, if
     * you want the GC to be effectively enabled again.
     *
     * See_Also: disable()
     */
    void enable()
    {
        assert (this.disabled > 0);
        this.disabled--;
    }

    /**
     * Disable the GC.
     *
     * See_Also: enable()
     */
    void disable()
    {
        this.disabled++;
        assert (this.disabled > 0);
    }

    /**
     * Run a GC collection in order to find unreferenced objects.
     *
     * This is the simplest stop-the-world mark-sweep algorithm ever. It first
     * removes the mark bit from all the live cells, then it marks the cells
     * that are reachable through the root set (static data, stack, registers
     * and custom root), and finally sweeps the live list looking for unmarked
     * cells to free.
     *
     * The world is stopped only for the mark phase.
     *
     * See_Also:
     *  $(UL
     *      $(LI mark_all() for details on the marking phase)
     *      $(LI sweep() for details on the sweep phase)
     *  )
     */
    void collect()
    {
        this.unmark();
        this.mark_all();
        this.sweep();
    }

    /**
     * Minimize free space usage.
     *
     * This method returns to the OS memory that is not longer used by
     * the program. Usually calling this method manually is not
     * necessary, because unused cells are recycled for future
     * allocations. But if there is some small part of the program that
     * requires a lot of memory and it's known that it won't be used
     * further, calling this can reduce the memory footprint of the program
     * considerably (at the expense of some performance lost in future
     * allocations).
     *
     * This implementation just return to the OS all the cells in the free
     * list.
     */
    void minimize()
    {
        foreach (cell; this.free_list) {
            this.free_list.unlink(cell);
            cstdlib.free(cell);
        }
    }

    /**
     * Get attributes associated to the cell pointed by ptr.
     *
     * Attributes is a bitmap that can have these values:
     *
     *  $(UL
     *      $(LI 1: The object stored in the cell has to be finalized)
     *      $(LI 2: The cell should not be scanned for pointers)
     *      $(LI 4: The cell should not be moved during a collection
     *           (unimplemented))
     *  )
     *
     * See_Also: cell.BlkAttr, setAttr(), clrAttr()
     */
    uint getAttr(void* ptr)
    {
        auto cell = this.live_list.find(ptr);
        if (cell)
            return cell.attr;
        return 0;
    }

    /**
     * Set the attributes of the cell pointed by ptr.
     *
     * All bits present in attr are set, other bits are untouched. The old
     * attributes are returned.
     *
     * See_Also: cell.BlkAttr, getAttr(), clrAttr()
     */
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

    /**
     * Clear the attributes of the cell pointed by ptr.
     *
     * All bits present in attr are cleared, other bits are untouched. The old
     * attributes are returned.
     *
     * See_Also: cell.BlkAttr, getAttr(), setAttr()
     */
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

    /**
     * Allocate memory.
     *
     * This is the main allocator of the GC. The algorithm is really
     * simple. It does a first-fit search in the free list, if no free cell is
     * found with enough room, it runs a collection and retry (unless the GC
     * is disabled). If there is no room still, it uses C malloc to allocate
     * a new cell. If all that fails, then onOutOfMemoryError() runtime
     * function is called to handle the error.
     *
     * attr are the attributes to associate to the new cell (see getAttr() for
     * details).
     */
    void* malloc(size_t size, uint attr=0)
    {
        if (size == 0)
            return null;

        // Find a free cell in the free list with enough space
        auto cell = this.free_list.pop(size);
        if (cell)
            goto success;

        // No room in the free list found, if the GC is enabled, trigger
        // a collection and try again
        if (!this.disabled) {
            this.collect();
            cell = this.free_list.pop(size);
            if (cell)
                goto success;
        }

        // No luck still, allocate new memory
        cell = cast(Cell*) cstdlib.malloc(size + Cell.sizeof);
        cell.capacity = 0; // so we can later tell it's new
        if (cell)
            goto success;

        // No memory
        onOutOfMemoryError();

        return null;

    success:
        cell.size = size;
        if (cell.capacity == 0) // fresh cell
            cell.capacity = size;
        cell.attr = cast(BlkAttr) attr;
        this.live_list.link(cell);

        return cell.ptr;
    }

    /**
     * Allocate memory (set memory to zero).
     *
     * Same as malloc() but set the allocated memory cell to zero.
     */
    void* calloc(size_t size, uint attr=0)
    {
        if (size == 0)
            return null;

        void* ptr = this.malloc(size, attr);

        if (ptr !is null) // in case onOutOfMemoryError didn't throw
            cstring.memset(ptr, 0, size);

        return ptr;
    }

    /**
     * Reallocate memory.
     *
     * This implementation is very simple, if size less or equals than the
     * cells capacity, the cell's size is changed and the same address is
     * returned. Otherwise a new cell is allocated using malloc() (this can
     * trigger a collection), the contents are moved and the old cell is freed.
     *
     * attr has the same meaning as in malloc().
     */
    void* realloc(void* ptr, size_t size, uint attr=0)
    {

        // Undercover malloc()
        if (ptr is null)
            return this.malloc(size, attr);

        // Undercover free()
        if (size == 0) {
            this.free(ptr);
            return null;
        }

        auto cell = this.live_list.find(ptr);
        assert (cell);

        // We have enough capacity already, just change the size
        if (cell.capacity >= size) {
            cell.size = size;
            return cell.ptr;
        }

        // We need to move the cell because of the lack of capacity, find
        // a free cell with the requested capacity (at least)
        ptr = this.malloc(size, attr);
        if (ptr is null) // in case onOutOfMemoryError didn't throw
            return null;
        Cell* new_cell = Cell.from_ptr(ptr);
        assert (new_cell !is null);

        // Move cell attributes and contents
        new_cell.attr = cell.attr;
        cstring.memcpy(new_cell.ptr, cell.ptr, cell.size);

        // Free the old cell
        this.free(cell);

        return new_cell.ptr;
    }

    /**
     * Attempt to in-place enlarge a memory block pointed to by ptr.
     *
     * The memory should be enlarged to at least min_size beyond its current
     * capacity, up to a maximum of max_size. This does not attempt to move
     * the memory block (like realloc() does).
     *
     * Returns:
     *  0 if could not extend ptr, total size of entire memory block if
     *  successful.
     */
    size_t extend(void* ptr, size_t min_size, size_t max_size)
    {
        assert (min_size <= max_size);
        // There is no possible extension of the capacity for this
        // implementation.
        return 0;
    }

    /**
     * Reserve memory to anticipate memory allocations.
     *
     * This implementation is really dumb, a single cell is allocated with
     * size bytes. If 2 malloc()s follow a call to reserve(size), requesting
     * size/2 bytes each, one allocation will still be done (and half the
     * memory of the first malloc will be wasted =). Since this is a trivial
     * implementation, we don't care about this.
     *
     * The actual number of bytes reserved are returned, or 0 on error.
     */
    size_t reserve(size_t size)
    {
        assert (size > 0);
        auto cell = cast(Cell*) cstdlib.malloc(size + Cell.sizeof);
        if (!cell)
            return 0;
        cell.size = size;
        cell.capacity = size;
        this.free_list.link(cell);
        return size;
    }

    /**
     * Free unused memory.
     *
     * This method tells the GC that a cell is not longer used. The GC doesn't
     * perform any connectivity check, if the cell was referenced by others,
     * nasty things will happen (much like C/C++).
     *
     * Note that finalizers are not called by this method. Finalizers are
     * called by the runtime when the delete operator is used, and the delete
     * operator calls this method through the runtime.
     */
    void free(void* ptr)
    {
        if (ptr is null)
            return;

        auto cell = this.live_list.pop(ptr);
        assert (cell);

        this.free_list.link(cell);
    }

    /**
     * Get the base address of an interior pointer into the GC heap.
     *
     * If ptr is not pointing into the GC heap null is returned.
     */
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

    /**
     * Return the real size (capacity) for the cell pointed to by ptr.
     *
     * ptr should be the base address of a heap allocated object, interior
     * pointers are not supported (use addrOf() if you have an interior
     * pointer). If this is not true, this method returns 0.
     *
     * realloc(ptr, sizeOf(ptr), attr) is guaranteed not to allocate/move
     * memory.
     */
    size_t sizeOf(void* ptr)
    {
        auto cell = this.live_list.find(ptr);
        if (cell)
            return cell.capacity;
        return 0;
    }

    /**
     * Get information about the cell pointed to by ptr.
     *
     * ptr should be the base address of a heap allocated object, interior
     * pointers are not supported (use addrOf() if you have an interior
     * pointer). If this is not true, this method returns BlkInfo.init.
     *
     * See BlkInfo for the information provided by this method.
     */
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

    /**
     * Add a root pointer to the root set.
     *
     * This method can be used to register new root to the GC heap. This is
     * only needed when the user has custom memory that has pointers into the
     * GC heap (for example for interfacing with C programs, which allocates
     * memory using malloc() directly).
     *
     * See_Also: removeRoot(), addRange(), removeRange()
     */
    void addRoot(void* ptr)
    {
        this.root_pointers.append(ptr);
    }

    /**
     * Add a root range to the root set.
     *
     * This method can be used to register new root range (a memory chunk
     * that should be scanned for pointers into the GC heap). This is
     * only needed when the user has custom memory that has pointers into the
     * GC heap (for example for interfacing with C programs, which allocates
     * memory using malloc() directly).
     *
     * Pointers will be scanned assuming they are aligned.
     *
     * See_Also: removeRange(), addRoot(), removeRoot()
     */
    void addRange(void* ptr, size_t size)
    {
        this.root_ranges.append(RootRange(ptr, ptr + size));
    }

    /**
     * Remove a root pointer from the root set.
     *
     * ptr has to be previously registered using addRoot(), otherwise the
     * results are undefined.
     *
     * See_Also: addRoot(), addRange(), removeRange()
     */
    void removeRoot(void* ptr)
    {
        this.root_pointers.remove(ptr);
    }

    /**
     * Remove a root range from the root set.
     *
     * ptr has to be previously registered using addRange(), otherwise the
     * results are undefined.
     *
     * See_Also: addRange(), addRoot(), removeRoot()
     */
    void removeRange(void* ptr)
    {
        this.root_ranges.remove_if((ref RootRange range) {
                    return range.from is ptr;
                });
    }

} // struct GC

// vim: set et sw=4 sts=4 :
