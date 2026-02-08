I will proceed with implementing **Loop Unrolling** optimization in the Zig IR Optimizer. This is a high-impact optimization that complements the recently added LICM pass.

The plan involves:
1.  **Enhance Optimizer Configuration**: Add `loop_unroll` flag and `unroll_factor` (default 4) to `PassConfig`.
2.  **Implement Loop Unrolling Logic**:
    *   Target **canonical loops** (loops with a single induction variable, constant step, and constant bounds) initially.
    *   Implement `canUnroll(loop)`: Analyze the loop header and latch to identify the induction variable and trip count.
    *   Implement `unrollLoop(loop)`:
        *   Duplicate the loop body `N-1` times.
        *   Update the induction variable for each copy.
        *   Adjust the latch condition and back-edge.
        *   Or, for full unrolling (if trip count is small and constant), completely linearize the loop.
    *   Update `optimizeLoop` to call the unrolling pass.
3.  **Fix CSE Safety**: Add a dominance check to the existing CSE implementation to ensure it doesn't illegally reuse values from non-dominating blocks.
4.  **Verification**: Create a new test file `src/aot/test_loop_unroll.zig` to verify that loops are correctly unrolled and the instruction count increases as expected (trading size for speed).

I will prioritize Loop Unrolling as it's the primary task, and then address the CSE safety issue as a secondary improvement.