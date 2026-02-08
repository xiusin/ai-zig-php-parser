I will implement the **Loop Invariant Code Motion (LICM)** optimization in the Zig IR Optimizer. This is a critical step in the "IR Optimization" track and does not require external LLVM dependencies, making it suitable for the current environment.

The plan involves two main parts:
1.  **Enhance Control Flow Analysis (`src/aot/analysis.zig`)**:
    *   Implement **Loop Detection**: Add logic to identify "Natural Loops" by finding back-edges (edges where the target dominates the source).
    *   Define `Loop` structure: Store metadata like the loop header, back-edges, and all blocks contained within the loop.
    *   Implement `LoopTree`: Organize nested loops hierarchically.

2.  **Implement LICM Pass (`src/aot/optimizer.zig`)**:
    *   Create `runLICM` and `optimizeLoop` methods.
    *   **Invariant Analysis**: Identify instructions that are "loop-invariant" (i.e., their operands are either constants or defined outside the loop).
    *   **Code Motion**: Move these invariant instructions to a "Pre-Header" block created immediately before the loop entry, reducing the instruction count inside the loop body.
    *   Integrate this pass into the main `optimize` pipeline under the `licm` configuration flag.

This will significantly improve the performance of loops in the generated IR by hoisting static calculations out of the loop body.

**Verification**:
I will create a specific unit test in `src/aot/optimizer.zig` that constructs a loop with an invariant calculation (e.g., `x = a + b` where `a` and `b` don't change in the loop) and asserts that the calculation is moved out of the loop.