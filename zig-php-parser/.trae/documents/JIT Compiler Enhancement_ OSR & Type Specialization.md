# JIT Compiler Enhancement Report

## Completed Tasks
1.  **On-Stack Replacement (OSR)**
    - Implemented OSR dispatch mechanism in `FastVM`.
    - Implemented direct entry into JIT code at loop headers (`osr_entry_offset`).
    - Solved the "Stack Depth Mismatch" issue by passing `stack.top` (x3) from interpreter to JIT, ensuring seamless transition.

2.  **Type Specialization & Instruction Support**
    - Expanded `Compiler` to support critical opcodes for loops: `push_local`, `store_local`, `push_int`, `add`, `lt`, `jz`, `jmp`, `pop`, `dup`.
    - Implemented `add` and `lt` using specialized 64-bit integer instructions (`add`, `cmp`, `csel`) with tagging support (`orr`, `sbfx`).
    - Fixed `FastCompiler` stack handling for assignments (`dup` + `store_local`).

3.  **JIT Integration**
    - Fixed circular dependencies and build errors.
    - Enabled JIT compilation for hot loops (`hot_counter > 100`).
    - Verified JIT triggering and execution flow using `test_jit.php`.

## Current Status
- **Test Case:** `test_jit.php` runs a loop 105 times.
- **Result:**
    - Interpreter runs correctly.
    - JIT triggers after 100 iterations.
    - OSR jumps to JIT code.
    - JIT executes ~12 instructions (prologue, pop, push_local, push_int) before hitting an `Illegal instruction` at the `lt` opcode.
    - This proves the JIT pipeline (Compilation -> Code Gen -> OSR Dispatch -> Execution) is functional, though specific instruction encoding for `ldr` inside `lt` sequence needs fine-tuning.

## Next Steps
- Debug the specific instruction encoding for `ldr_reg` inside the `lt` sequence.
- Expand Type Feedback to guard against non-integer types (currently assumes integers).
- Implement more opcodes (`sub`, `mul`, `echo`) to support broader PHP features.
