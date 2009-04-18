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

module arch;

// TODO: explain why the functions return strings to use as string mixins

/*
 * Small hack to define the string alias if not defined
 *
 * Tango don't define this alias in object.d, but Phobos 1 and 2 does.
 */
// XXX: this doesnt work:
// static if (!is(string))
//    alias char[] string;
// See: http://d.puremagic.com/issues/show_bug.cgi?id=2848
version (Tango)
    alias char[] string;

/*
 * Functions dependant on the direction in which the stack grows
 *
 * By default, stack is considered to grow down, as in x86 architectures.
 */

version = STACK_GROWS_DOWN;

bool stack_smaller(void* ptr1, void* ptr2)
{
    version (STACK_GROWS_DOWN)
        return ptr1 > ptr2;
    else
        return ptr1 < ptr2;
}

// Functions to push/pop registers into/from the stack

version (GNU)
{

    /*
     * GCC has an intrinsic function that does the job of pushing the registers
     * into the stack, we use that function if available because it should work
     * in all GCC supported architectures.
     */

    string push_registers(string sp_name)
    {
        return "
            __builtin_unwind_init();
            " ~ sp_name ~ " = &" ~ sp_name ~ ";
        ";
    }

    string pop_registers(string sp_name)
    {
        return "";
    }

}
else version (X86)
{

    /*
     * For X86 PUSHAD/POPAD are not used because they are too fragile to
     * compiler optimizations (like ommitting the frame pointer).
     *
     * This method should work safely with all optimizations because it doesn't
     * works behind the compilers back.
     */

    string push_registers(string sp_name)
    {
        return "
            size_t eax, ecx, edx, ebx, ebp, esi, edi;
            asm
            {
                mov eax[EBP], EAX;
                mov ecx[EBP], ECX;
                mov edx[EBP], EDX;
                mov ebx[EBP], EBX;
                mov ebp[EBP], EBP;
                mov esi[EBP], ESI;
                mov edi[EBP], EDI;
                mov " ~ sp_name ~ "[EBP],  ESP;
            }
        ";
    }

    string pop_registers(string sp_name)
    {
        return "";
    }

}
else version (X86_64)
{

    /*
     * See X86 comment above.
     */

    string push_registers(string sp_name)
    {
        return "
            size_t rax, rbx, rcx, rdx, rbp, rsi, rdi,
                   r10, r11, r12, r13, r14, r15;
            asm
            {
                movq rax[RBP], RAX;
                movq rbx[RBP], RBX;
                movq rcx[RBP], RCX;
                movq rdx[RBP], RDX;
                movq rbp[RBP], RBP;
                movq rsi[RBP], RSI;
                movq rdi[RBP], RDI;
                movq r10[RBP], R10;
                movq r11[RBP], R11;
                movq r12[RBP], R12;
                movq r13[RBP], R13;
                movq r14[RBP], R14;
                movq r15[RBP], R15;
                movq " ~ sp_name ~ "[RBP],  RSP;
            }
        ";
    }

    string pop_registers(string sp_name)
    {
        return "";
    }

}
else // Unkown compiler/architecture
{

    pragma(msg, "Don't know how to push registers into the stack for this "
                "compiler/architecture");
    static assert(false);

}

// vim: set et sw=4 sts=4 :
