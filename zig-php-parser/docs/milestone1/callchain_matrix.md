# Milestone 1：主链路调用链矩阵（自动生成）

| 功能 | 实现位置 | 调用点 | 输入/输出契约 | 副作用 | 性能热点 | 分配次数 | 异常路径 |
|---|---|---|---|---|---|---|---|
| CLI 入口与模式路由 | [main.zig:L238-L244](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/main.zig#L238-L244) | if (compile_mode) { | argv → (compile\|run) 分支 | 读取配置/文件；写 stdout/stderr | I/O + 解析/编译为主 | GPA+Arena（按源码读取大小分配） | 参数解析/文件读失败/parse 失败/compile 失败 |
| Parser：源码→AST 根节点 | [parser.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/compiler/parser.zig) | pub fn parse(self: *Parser) !ast.Node.Index { | php_code → ast.Node.Index(root) | 写入 PHPContext.nodes/string_pool/errors | tokenize+parse（与源码长度相关） | Arena 分配 AST/字符串池 | 语法错误/资源耗尽 |
| VM.run：执行模式分发 | [vm.zig:L5054-L5060](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/vm.zig#L5054-L5060) | pub fn run(self: *VM, node: ast.Node.Index) !Value { | AST(root) → Value/错误 | 可能输出；可能修改全局变量/对象堆；调度协程 | 分发本身 O(1)，主体由模式决定 | 运行时对象/字符串/数组等按需分配 | 异常抛出、Return 特例、运行期错误 |
| Tree：eval 主分发 | [vm.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/vm.zig) | fn eval(self: *VM, node: ast.Node.Index) anyerror!Value { | AST(node) → Value/错误 | echo 走 Value.print（debug.print） | tag 分发 O(1)；递归深度敏感 | 表达式/容器构造按语义分配 | Unsupported tag/throwException/递归深度溢出 |
| Bytecode：AST→字节码→执行循环 | [generator.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/bytecode/generator.zig) | pub fn compile(self: *BytecodeGenerator, root_index: ast.Node.Index) !CompiledFunction { | AST(root) → CompiledFunction | 构建常量表/指令流/用户函数表 | 遍历 AST O(n)+优化 | 指令/常量表/临时结构分配 | 未覆盖 tag 可能静默跳过导致语义缺失 |
| BytecodeVM：dispatch-table 执行循环 | [vm.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/bytecode/vm.zig) | fn runOptimized(self: *BytecodeVM) !?Value { | bytecode → ?Value/错误 | 写 output_buffer；修改堆/全局 | 每条指令一次分发（热点：dispatch+内建调用） | 按指令语义分配 | 指令错误/异常抛出/栈帧错误 |
| FastVM：AST→FastCompiler→执行 | [fast_compiler.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/fast_compiler.zig) | fn compileNode(self: *FastCompiler, index: ast.Node.Index) anyerror!void { | AST(node) → fast bytecode | 生成 fast 指令流 | 目标是减少分发与装箱 | fast 指令/常量表 | 未覆盖 tag 静默跳过风险高 |
| AOT：compile 总入口 | [main.zig:L371-L377](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/main.zig#L371-L377) | fn runAOTCompilation(allocator: std.mem.Allocator, options: aot.CompileOptions) !void { | php file → (ir/zig/exe) | 读取源码；生成/写出构建目录与产物；调用 zig 编译器 | parse+IR+优化+zig 编译 | GPA 分配 AST/IR/字符串表等 | 解析失败/IR 生成失败/链接失败 |
| AOT：IR 生成（语句分发） | [ir_generator.zig:L669-L675](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/ir_generator.zig#L669-L675) | fn generateStatement(self: *Self, index: Node.Index) anyerror!void { | AST stmt → IR | 写入 module/functions/blocks/symbol_table | AST 遍历 O(n) | IR 指令/块/寄存器等分配 | anyerror 传播；部分 tag 回退表达式路径 |
| AOT：IR 生成（表达式分发） | [ir_generator.zig:L1834-L1840](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/ir_generator.zig#L1834-L1840) | pub fn generateExpression(self: *Self, index: Node.Index) anyerror!Register { | AST expr → Register | 追加 IR 指令 | 表达式树遍历 | IR 指令/常量池 | 未覆盖 tag 回退 const_null（语义风险） |
| AOT：NativeLinker（IR→Zig→zig build-exe） | [native_linker.zig:L4083-L4089](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/native_linker.zig#L4083-L4089) | pub fn compileToExecutable( | IR module → 可执行文件 | 写 zig 源码、拷贝 runtime、spawn zig 编译进程 | Zig 编译占主导 | 代码生成缓冲、临时字符串 | 指令覆盖缺口/zig 编译失败/文件写入失败 |

## 说明
- 本文档仅覆盖 Milestone1 需要的“端到端主链路 + 分发点”，不等价于全量业务逻辑矩阵。
- Tree/Bytecode/Fast 的 AST tag 覆盖详见 artifacts/diff_matrix.xlsx。