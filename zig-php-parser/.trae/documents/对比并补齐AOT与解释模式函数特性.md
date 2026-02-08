## 对比结论（按功能点）
- 以 AST 为单一真源：先确认各语法节点已存在/字段齐全；再分别对 tree-walking 解释器、AOT、bytecode VM 三条执行链路做“落地能力矩阵”，标出缺口与语义不一致。

## 功能补齐（P0/P1）
- P0：补齐 bytecode VM 的闭包/捕捉/调用指令链路（capture_var / make_closure / closure_call / arrow_fn），实现闭包对象与环境存储，并对齐 tree/AOT 的引用捕捉语义。
- P0：统一 arrow function 的运行时表示与调用路径（避免 tree-walking 用 Closure 冒充 ArrowFunction，或反向删掉 ArrowFunction 体系），确保具名参数/回调分派/GC 路径一致。
- P1：AOT 支持具名参数：IR 层保留 name，调用点构造“位置参数+named map”，并在 runtime 复用与解释器一致的 bind 规则。
- P1：实现实参展开 `...$args`（unpacking_expr）：tree-walking 的 evaluateFunctionCall、AOT 的 generateFunctionCall、bytecode 的参数组装三处同时落地，并处理 array/Traversable。

## 深度优化（P2）
- P2：对 arrow/closure 捕捉做自由变量分析（替代“全量捕捉 locals”），减少分配与副作用面；AOT 与 tree-walking 共享同一分析器输出。
- P2：统一具名参数对 callable 的行为：让 closure/arrow/native/user_function 走同一绑定逻辑，减少分支与语义差异。

## 验证与回归
- 新增/扩展用例覆盖：闭包（值/引用捕捉）、箭头函数、具名参数（含乱序/缺参/默认值）、变参、动态调用（call_user_func/_array）、unpacking。
- 确保三条模式在同一组脚本上输出一致（允许差异需显式记录）。

## 交付物
- 功能矩阵与差异说明文档（短表格）
- 代码补丁（bytecode/AOT/runtime/测试）
- 性能对比：捕捉优化前后分配次数/运行时间基线