/**
 * Naive Garbage Collector (Tango/Druntime compliant) C interface.
 *
 * This module contains the C interface of the Naive Garbage Collector
 * implementation to comply with the Tango/Druntime specification.
 *
 * See_Also:  gc module
 * Copyright: Public Domain
 * License:   Public Domain
 * Authors:   Leandro Lucarella <llucax@gmail.com>
 */

module gc.iface;

private {

    // Internal imports
    import gc.gc: GC, BlkInfo;

    // Standard imports
    import tango.stdc.stdlib;

    /// GC implementation instance.
    GC gc;

    /// Dummy class for the GC lock.
    class GCLock {}

    /**
     * The GC lock.
     *
     * This is a ClassInfo instance because is an easy way to get an object
     * instance that is not allocated in the GC heap (which is not an option
     * for implementing the GC).
     *
     * This avoids using OS-specific mutex.
     */
    ClassInfo lock;

}

/**
 * Initialize the GC.
 *
 * This function initializes the thread library too. This is a requirement
 * imposed by the current implementation, it's not in the D runtime specs.
 *
 * This method should be called before any other call to the GC.
 */
extern (C) void gc_init()
{
    lock = GCLock.classinfo;
    gc.init();
}

/**
 * Terminate the GC.
 *
 * After this function is called, no other GC methods should be called, except
 * for gc_init(), which should initialize the GC again.
 */
extern (C) void gc_term()
{
    gc.term();
}

/**
 * Enable the GC.
 *
 * When the GC is enabled, collections can happen at any time in the program.
 * Different implementations can trigger a collection for different reasons.
 *
 * gc_enable() and gc_disable() can be called recursively. The number of calls
 * to gc_enable() should match the number of calls to gc_disable(), though.
 *
 * If gc_disable() is called more times than gc_enable(), the GC will stay
 * disabled. If gc_enable() is called more times than gc_disable(), the
 * results of this function are undefined.
 *
 * See_Also: gc_disable()
 */
extern (C) void gc_enable()
{
    synchronized (lock)
        gc.enable();
}

/**
 * Disable the GC.
 *
 * See_Also: gc_enable() for details.
 */
extern (C) void gc_disable()
{
    synchronized (lock)
        gc.disable();
}

/**
 * Run a GC collection in order to free unreferenced objects.
 *
 * The gc_enable() and gc_disable() functions don't affect this function, the
 * collection will happen even if the GC is disabled.
 */
extern (C) void gc_collect()
{
    synchronized (lock)
        gc.collect();
}

/**
 * Minimize free space usage.
 *
 * This function tries to minimize the programs memory footprint returning
 * free memory to the OS.
 *
 * This should be used with care, because it would impose a performance
 * penalty for further allocations.
 */
extern (C) void gc_minimize()
{
    synchronized (lock)
        gc.minimize();
}

/**
 * Get the attributes of the cell pointed by ptr.
 *
 * Bit significance of the uint value used for block attribute passing is as
 * follows, by position:
 *
 *  $(UL
 *      $(LI 1: The object stored in the cell have to be finalized)
 *      $(LI 2: The cell should not be scanned for pointers)
 *      $(LI 4: The cell should not be moved during a collection)
 *      $(LI 3-15: Reserved for future use by the D standard library)
 *      $(LI 16-31: Reserved for internal use by the garbage collector and
 *                  compiler)
 *  )
 *
 * See_Also: BlkAttr, gc_setAttr(), gc_clrAttr()
 */
extern (C) uint gc_getAttr(void* ptr)
{
    synchronized (lock)
        return gc.getAttr(ptr);
}

/**
 * Set the attributes of the memory block pointed by ptr.
 *
 * All bits present in attr are set, other bits are untouched. The old
 * attributes are returned.
 *
 * See_Also: BlkAttr, gc_getAttr(), gc_clrAttr()
 */
extern (C) uint gc_setAttr(void* ptr, uint attr)
{
    synchronized (lock)
        return gc.setAttr(ptr, attr);
}

/**
 * Clear the attributes of the cell pointed by ptr.
 *
 * All bits present in attr are cleared, other bits are untouched. The old
 * attributes are returned.
 *
 * See_Also: BlkAttr, gc_getAttr(), gc_setAttr()
 */
extern (C) uint gc_clrAttr(void* ptr, uint attr)
{
    synchronized (lock)
        return gc.clrAttr(ptr, attr);
}

/**
 * Allocate memory with attributes attr.
 *
 * See_Also: BlkAttr, gc_getAttr() for attr details.
 */
extern (C) void* gc_malloc(size_t size, uint attr=0)
{
    synchronized (lock)
        return gc.malloc(size, attr);
}

/**
 * Allocate memory (set memory to zero).
 *
 * Same as gc_malloc() but set the allocated memory block to zero.
 */
extern (C) void* gc_calloc(size_t size, uint attr=0)
{
    synchronized (lock)
        return gc.calloc(size, attr);
}

/**
 * Reallocate memory.
 *
 * This function attempts to extend the current memory block to size. If ptr
 * is null, then this function behaves exactly the same as gc_malloc(). If
 * size is 0, then this function behaves exactly like gc_free(). Otherwise
 * this function can resize the memory block in-place or it can move the
 * memory block to another address, in which case the new memory address is
 * returned (if the memory block is not moved, the return address is the same
 * as ptr).
 *
 * attr are the same as malloc().
 */
extern (C) void* gc_realloc(void* ptr, size_t size, uint attr=0)
{
    synchronized (lock)
        return gc.realloc(ptr, size, attr);
}

/**
 * Attempt to in-place enlarge a memory block pointed to by ptr.
 *
 * The memory is enlarged to at least min_size beyond its current capacity, up
 * to a maximum of max_size. This does not attempt to move the memory block
 * (like gc_realloc() does).
 *
 * The total size of entire memory block is returned on success, 0 is returned
 * if the memory block could not be extended.
 */
extern (C) size_t gc_extend(void* ptr, size_t min_size, size_t max_size)
{
    synchronized (lock)
        return gc.extend(ptr, min_size, max_size);
}

/**
 * Reserve memory to anticipate memory allocations.
 *
 * This method instructs the GC to pre-allocate at least size bytes of memory
 * in anticipation of future gc_malloc()s.
 *
 * The actual number of bytes reserver are returned, or 0 on error.
 */
extern (C) size_t gc_reserve(size_t size)
{
    synchronized (lock)
        return gc.reserve(size);
}

/**
 * Free unused memory.
 *
 * This method tells the GC that a cell is not longer used. If the memory was
 * actually still used the effects of this function is undefined (but memory
 * corruption will probably happen).
 *
 * Note that finalizers are not called by this function. Finalizers are called
 * by the runtime when the delete operator is used, and the delete operator
 * calls this method through the runtime.
 */
extern (C) void gc_free(void* ptr)
{
    synchronized (lock)
        gc.free(ptr);
}

/**
 * Get the base address of an interior pointer into the GC heap.
 *
 * If ptr is not pointing into the GC heap null is returned.
 */
extern (C) void* gc_addrOf(void* ptr)
{
    synchronized (lock)
        return gc.addrOf(ptr);
}

/**
 * Return the real size (capacity) of the memory block pointed by ptr.
 *
 * ptr should be the base address of a heap allocated object, interior
 * pointers are not supported (use gc_addrOf() if you have an interior
 * pointer). If ptr is not the base address of a heap allocated object this
 * function returns 0.
 *
 * realloc(ptr, sizeOf(ptr), attr) is guaranteed not to allocate/move memory.
 */
extern (C) size_t gc_sizeOf(void* ptr)
{
    synchronized (lock)
        return gc.sizeOf(ptr);
}

/** Get information about the memory block pointed by ptr.
 *
 * ptr should be the base address of a heap allocated object, interior
 * pointers are not supported (use gc_addrOf() if you have an interior
 * pointer). If ptr is not the base address of a heap allocated object this
 * function returns a BlkInfo structure with all zeros.
 *
 * See BlkInfo for the information provided by this method.
 */
extern (C) BlkInfo gc_query(void* ptr)
{
    synchronized (lock)
        return gc.query(ptr);
}

/** Add a root pointer to the root set.
 *
 * This method can be used to register new root to the GC heap. This is only
 * needed when the user has custom memory that has pointers into the GC heap
 * (for example for interfacing with C programs, which allocates memory using
 * malloc() directly).
 *
 * See_Also: gc_removeRoot(), gc_addRange(), gc_removeRange()
 */
extern (C) void gc_addRoot(void* ptr)
{
    synchronized (lock)
        gc.addRoot(ptr);
}

/**
 * Add a root range to the root set.
 *
 * This method can be used to register new root range (a memory chunk that
 * should be scanned for pointers into the GC heap). Pointers will be scanned
 * assuming they are aligned.
 *
 * See_Also: gc_removeRange(), gc_addRoot(), gc_removeRoot()
 */
extern (C) void gc_addRange(void* ptr, size_t size)
{
    synchronized (lock)
        gc.addRange(ptr, size);
}

/**
 * Remove a root pointer from the root set.
 *
 * ptr has to be previously registered using gc_addRoot(), in other case the
 * results of this function is undefined.
 *
 * See_Also: gc_addRoot(), gc_addRange(), gc_removeRange()
 */
extern (C) void gc_removeRoot(void* ptr)
{
    synchronized (lock)
        gc.removeRoot(ptr);
}

/**
 * Remove a root range from the root set.
 *
 * ptr has to be previously registered using gc_addRange(), in other case the
 * results of this function is undefined.
 *
 * See_Also: gc_addRange(), gc_addRoot(), gc_removeRoot()
 */
extern (C) void gc_removeRange(void* ptr)
{
    synchronized (lock)
        gc.removeRange(ptr);
}

// vim: set et sw=4 sts=4 :
