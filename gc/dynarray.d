/**
 * Dynamic array.
 *
 * This module contains a simple dynamic array implementation for use in the
 * Naive Garbage Collector. Standard D dynamic arrays can't be used because
 * they rely on the GC itself.
 *
 * See_Also:  gc module
 * Copyright: Public Domain
 * License:   Public Domain
 * Authors:   Leandro Lucarella <llucax@gmail.com>
 */

module gc.dynarray;

// Standard imports
private import tango.stdc.stdlib: realloc;
private import tango.stdc.string: memmove;

// External runtime functions
private extern (C) void onOutOfMemoryError();


package:

/**
 * Dynamic array.
 *
 * This is a simple dynamic array implementation. D dynamic arrays can't be
 * used because they rely on the GC, and we are implementing the GC.
 */
struct DynArray(T)
{

private:

    /// Memory block to hold the array.
    T* data = null;

    /// Total array capacity, in number of elements.
    size_t capacity = 0;

    /// Current array size, in number of elements.
    size_t size = 0;

    invariant()
    {
        assert ((this.data && this.capacity)
                    || ((this.data is null) && (this.capacity == 0)));
        assert (this.capacity >= this.size);
    }


public:

    /**
     * Append a copy of the element x at the end of the array.
     *
     * This can trigger an allocation if the array is not big enough.
     */
    void append(in T x)
    {
        if (this.size == this.capacity)
            this.expand();
        this.data[this.size] = x;
        this.size++;
    }

    /**
     * Remove the first element for which predicate(element) is true.
     */
    void remove_if(bool delegate(ref T) predicate)
    {
        for (size_t i = 0; i < this.size; i++) {
            if (predicate(this.data[i])) {
                this.size--;
                // move the rest of the items one place to the front
                memmove(this.data + i, this.data + i + 1,
                            (this.size - i) * T.sizeof);
                return;
            }
        }
    }

    /**
     * Remove the first occurrence of the element x from the array.
     */
    void remove(in T x)
    {
        this.remove_if((ref T e) { return e == x; });
    }

    /**
     * Change the current capacity of the array to new_capacity.
     *
     * This can enlarge or shrink the array, depending on the current capacity.
     * If new_capacity is 0, the array is enlarged to hold double the current
     * size. If new_capacity is less than the current size, the current size is
     * truncated, and the (size - new_capacity) elements at the end are lost.
     */
    void expand(in size_t new_capacity=0)
    {
        // adjust new_capacity if necessary
        if (new_capacity == 0)
            new_capacity = this.size * 2;
            if (new_capacity == 0)
                new_capacity = 4;
        // reallocate the memory with the new_capacity
        T* new_data = cast(T*) realloc(this.data, new_capacity);
        if (new_data is null)
            onOutOfMemoryError();
        this.data = new_data;
        this.capacity = new_capacity;
        // truncate the size if necessary
        if (this.size > this.capacity)
            this.size = this.capacity;
    }

    /**
     * Remove all the elements of the array and set the capacity to 0.
     */
    void clear()
    {
        this.data = cast(T*) realloc(this.data, 0);
        assert (this.data is null);
        this.size = 0;
        this.capacity = 0;
    }

    /**
     * Iterate over the array elements.
     */
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

debug (UnitTest)
{

private:

    unittest // DynArray
    {
        DynArray!(int) array;
        assert (array.size == 0);
        assert (array.capacity == 0);
        assert (array.data == null);
        foreach (x; array)
            assert (false, "there should be no elements in the array");
        array.append(5);
        assert (array.size == 1);
        assert (array.capacity >= 1);
        assert (array.data);
        foreach (x; array)
            assert (x == 5);
        array.append(6);
        assert (array.size == 2);
        assert (array.capacity >= 2);
        assert (array.data);
        int i = 0;
        foreach (x; array)
            assert (x == 5 + i++);
        assert (i == 2);
        array.remove(5);
        assert (array.size == 1);
        assert (array.capacity >= 1);
        assert (array.data);
        foreach (x; array)
            assert (x == 6);
        array.expand(100);
        assert (array.size == 1);
        assert (array.capacity >= 100);
        assert (array.data);
        foreach (x; array)
            assert (x == 6);
        array.clear();
        assert (array.size == 0);
        assert (array.capacity == 0);
        assert (array.data == null);
        foreach (x; array)
            assert (false, "there should be no elements in the array");
    }

} // debug (UnitTest)

// vim: set et sw=4 sts=4 :
