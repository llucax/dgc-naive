/**
 * Architecture (and compiler) dependent functions.
 *
 * This is a support module for the Naive Garbage Collector. All the code that
 * depends on the architecture (or compiler) is in this module.
 *
 * See_Also:  gc module
 * Copyright: Public Domain
 * License:   Public Domain
 * Authors:   Leandro Lucarella <llucax@gmail.com>
 */

module gc.arch;


package:

/**
 * Small hack to define the string alias if not defined
 *
 * Tango don't define this alias in object.d, but Phobos 1 and 2 does.
 */
/*
 * XXX: this (more general approach) doesn't work:
 *
 * static if (!is(string))
 *    private alias char[] string;
 *
 * See: http://d.puremagic.com/issues/show_bug.cgi?id=2848
 */
version (Tango)
    private alias char[] string;


version (D_Ddoc)
{

    /**
     * Push the registers into the stack.
     *
     * Note that this function should be used as a string mixin because if
     * a regular function call would be done, the stack would be unwound at
     * function exit and the register will not longer be in the stack.
     *
     * A pointer to the top of the stack is stored in a variable with the name
     * 'sp_name' (which is expected to be a void*).
     *
     * Example:
     * -----------------------------------------------------------------------
     *  void some_function()
     *  {
     *      void* sp;
     *      mixin(push_registers("sp"));
     *      // Do something
     *      mixin(pop_registers("sp"));
     *  }
     * -----------------------------------------------------------------------
     *
     * See_Also: pop_registers()
     *
     */
    string push_registers(string sp_name);

    /**
     * Pop the registers out the stack.
     *
     * Note that this function should be used as a string mixin (see
     * push_registers() for more details).
     *
     * A pointer to the top of the stack can be obtained from a variable with
     * the name 'sp_name' (which is expected to be a void*).
     *
     * See_Also: push_registers()
     */
    string pop_registers(string sp_name);

}


// Implementation(s)

version (GNU)
{

    /*
     * GCC has an intrinsic function that does the job of pushing the
     * registers into the stack, we use that function if available because it
     * should work in all GCC supported architectures.
     *
     * Nothing needs to be done to pop the registers from the stack.
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
     * For X86 PUSHAD/POPAD are not used because they are too susceptible to
     * compiler optimizations (like omitting the frame pointer).
     *
     * This method should work safely with all optimizations because it doesn't
     * work behind the compilers back.
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
     * See X86 comment above, X86_64 uses the same trick.
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
else // Unknown compiler/architecture
{

    static assert(false, "Don't know how to push registers into the stack "
                         "for this compiler/architecture");

}

// vim: set et sw=4 sts=4 :
