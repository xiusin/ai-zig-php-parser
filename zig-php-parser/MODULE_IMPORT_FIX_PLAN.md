# 模块导入路径修复计划

## 问题描述

Zig 0.15.2 不允许使用 `../` 进行跨模块导入。需要将所有跨目录的导入改为使用根模块路径。

## 修复策略

### 方案 1：使用 build.zig 中的模块系统（推荐）

在 `build.zig` 中定义模块，然后在代码中使用模块名导入：

```zig
// build.zig
const compiler_mod = b.addModule("compiler", .{
    .root_source_file = b.path("src/compiler/root.zig"),
});

const runtime_mod = b.addModule("runtime", .{
    .root_source_file = b.path("src/runtime/types.zig"),
});

// 在代码中使用
const ast = @import("compiler").ast;
const Value = @import("runtime").Value;
```

### 方案 2：使用相对路径但保持在同一模块内

将相关文件组织在同一目录下，避免跨目录导入。

### 方案 3：创建统一的根导入文件

创建一个 `src/root.zig` 文件，导出所有需要的模块：

```zig
// src/root.zig
pub const compiler = @import("compiler/root.zig");
pub const runtime = @import("runtime/types.zig");
pub const jit = @import("jit/root.zig");
pub const bytecode = @import("bytecode/vm.zig");

// 在代码中使用
const root = @import("root");
const ast = root.compiler.ast;
```

## 受影响的文件

### 高优先级（核心功能）
1. `src/bytecode/vm.zig` - 字节码 VM
2. `src/runtime/vm.zig` - 运行时 VM
3. `src/jit/compiler.zig` - JIT 编译器
4. `src/compiler/parser.zig` - 解析器

### 中优先级（测试和工具）
5. `src/jit/test_*.zig` - JIT 测试文件
6. `src/runtime/test_*.zig` - 运行时测试文件
7. `src/benchmark/*.zig` - 基准测试

### 低优先级（示例）
8. `examples/*.zig` - 示例代码

## 推荐方案

采用**方案 3**：创建统一的根导入文件

**优点**：
- 最小化代码改动
- 保持现有目录结构
- 易于维护
- 符合 Zig 0.15.2 规范

**实施步骤**：
1. 创建 `src/root.zig`
2. 导出所有主要模块
3. 更新所有使用 `../` 的导入语句
4. 运行测试验证

## 实施时间估计

- 创建根文件：5 分钟
- 更新导入语句：30 分钟
- 测试验证：15 分钟
- **总计**：约 50 分钟

## 注意事项

1. 保持向后兼容性
2. 确保所有测试通过
3. 更新文档说明新的导入方式
4. 考虑性能影响（应该没有）

## 状态

- [ ] 创建 `src/root.zig`
- [ ] 更新核心文件导入
- [ ] 更新测试文件导入
- [ ] 更新示例文件导入
- [ ] 运行完整测试套件
- [ ] 更新文档

---

**创建时间**: 2026-01-20  
**优先级**: P1（短期修复）  
**影响范围**: 编译警告修复，不影响功能
