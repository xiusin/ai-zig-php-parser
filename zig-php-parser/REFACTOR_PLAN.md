# AOT 编译器嵌套循环与类型推导重构任务清单

本清单基于 `AGENTS.md` 的工程规范与 `NESTED_LOOP_FIX_GUIDE.md` 的问题分析制定，旨在通过系统性重构，彻底解决 AOT 编译器在嵌套循环与类型推导上的架构缺陷。

## 🎯 总体目标
1.  **无限嵌套支持**：从架构层面支持任意深度的循环嵌套（Benchmark: 100层嵌套无误）。
2.  **类型推导完备**：消除 `fallback` 到动态类型的静默行为，实现 100% 静态类型覆盖。
3.  **工程化标准**：遵循 SOLID/DRY 原则，废弃基于字符串匹配的脆弱逻辑。

---

## 📅 阶段一：IR 与类型系统重构 (核心底座)
**目标**：消除魔法字符串依赖，建立强类型 IR。

### 1. 中间 IR (Intermediate Representation)
- [ ] **IR 结构增强**：在 `src/aot/ir.zig` 中为 `BasicBlock` 引入显式的 `LoopMetadata` 结构，包含 `header`, `body`, `latch`, `exit` 块的直接引用，替代当前的隐式推断。
- [ ] **消除魔法字符串**：**[关键]** 彻底移除 `analyzeLoopAccumulators` 中依赖 `std.mem.indexOf(..., "init")` 识别初始值的逻辑。
- [ ] **显式 PHI 节点**：在 IR 层实现标准的 SSA PHI 节点表示，确保累加器变量在 BasicBlock 间的传递通过显式数据流完成，而非变量名匹配。

### 2. 类型环境 (Type Environment)
- [ ] **严格类型模式**：改造 `getInferredRegType`，增加 `StrictTypeMode`。在严格模式下，推导失败应报错，而非回退。
- [ ] **类型流定点分析**：实现基于数据流的类型迭代分析器，处理循环中的类型收敛（Type Convergence）。
- [ ] **跨块类型传播**：建立全局类型表，支持跨 BasicBlock 的寄存器类型查询。

### 3. 前端 AST (Abstract Syntax Tree)
- [ ] **AST 语义增强**：在 AST 转 IR 阶段，提前计算循环深度与变量作用域，注入 IR。

---

## 📅 阶段二：后端代码生成重写 (核心攻坚)
**目标**：实现基于结构化构建器的代码生成，支持无限嵌套。

### 4. 后端代码生成 (Code Generation)
- [ ] **结构化代码构建器**：开发 `ZigCodeBuilder` 模块，替代 `writer.print` 的直接输出。
    -   支持自动缩进管理（`IndentStack`）。
    -   支持作用域资源管理（自动生成 `defer`）。
- [ ] **循环生成器重写 (Loop Gen V3)**：
    -   废弃递归下降的 `generateLoopRecursive`。
    -   实现基于栈的迭代式生成器 `generateLoopIterative`，解决递归栈溢出风险。
    -   **[修复]** 实现动态缩进机制，确保生成代码的格式正确性。
- [ ] **类型安全指令生成**：
    -   重构 `generateInstructionSimple`，强制检查操作数类型。
    -   自动注入类型转换代码（如 `i64` -> `Value`）。

### 5. 符号表 (Symbol Table)
- [ ] **作用域链管理**：实现支持嵌套的 `ScopeChain`。

---

## 📅 阶段三：系统增强与稳定性 (工程化)
**目标**：提升编译器的鲁棒性和可用性。

### 6. 错误恢复 (Error Recovery)
- [ ] **上下文感知报错**：提供完整的“推导路径回溯”。
- [ ] **编译屏障**：在代码生成前增加 `ValidationPass`。

### 7. 依赖分析 (Dependency Analysis)
- [ ] **循环依赖强化**：增强 `DependencyResolver` 处理循环引用。

### 8. 增量编译 (Incremental Compilation)
- [ ] **细粒度缓存**：将缓存粒度细化到“函数级”。

---

## 📅 阶段四：测试与交付 (质量验收)
**目标**：通过高强度测试验证重构成果。

### 9. 测试框架 (Test Framework)
- [ ] **极端压力测试集**：
    -   `test_nested_100.php`: 100 层空循环。
    -   `test_nested_complex.php`: 10 层嵌套，含分支和累加器。
- [ ] **Fuzz Testing 集成**：编写生成器自动生成随机 PHP 代码。
- [ ] **回归测试套件**：确保现有用例 100% 通过。
