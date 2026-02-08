# AOT 差异对比与收敛计划报告 (Phase 2)

**生成日期**: 2026-02-03
**状态**: Phase 2 完成 (Array Access Fix & File I/O)

## 1. 核心修复：`array_get` 字符串键查找

### 问题描述
在 Phase 1 中，`json_decode` 返回的数组可以通过 `foreach` 遍历，但无法通过字符串键（如 `$data["key"]`）访问。

### 根因分析
AOT 编译器 (`native_linker.zig`) 在生成 `array_get` 指令时，简单粗暴地将所有类型的键都转换为整数 (`.asInt()`) 进行查找。这导致字符串键 `"a"` 被转换为 `0`，从而查找失败。

### 解决方案
1.  **Runtime**: 在 `PHPArray` 中添加了 `getByValue(key: Value)` 方法，根据 Key 的运行时类型（String 或 Int）分发到底层的 `HashMap` 查找。
2.  **Compiler**: 修改 `native_linker.zig`，当键是 `Value` 类型时，生成调用 `getByValue` 的代码，而不是强制转换。

### 验证结果
`tests/aot_verification/json_test.php` 现在可以正确输出：
```
Decoded a: 1
Decoded b: 2
```

## 2. 功能增强：文件 I/O 与控制流

### 修复内容
1.  **Builtin 映射**: 恢复了 `file_get_contents`, `file_put_contents`, `file_exists`, `unlink` 等函数在 `native_linker.zig` 中的映射（之前因回滚丢失）。
2.  **条件跳转 (`cond_br`)**: 修复了 `if (condition)` 生成逻辑。
    *   **问题**: `file_exists` 返回 `Value` 类型，但生成的 `if` 语句直接使用它作为条件 (`if (reg_6)`), 导致 Zig 编译错误 (`expected bool, found Value`)。
    *   **修复**: 在 `native_linker.zig` 的多个代码生成路径（`tryGenerateSimpleIfElse`, `generateTerminatorSimple`）中，加入类型检查。如果寄存器实际类型是 `Value`，则生成 `.toBool()` 调用。
    *   **难点**: 必须使用 `self.current_reg_types` 来获取寄存器的真实类型，而不是依赖 IR 指令中的类型标记（后者可能被标记为期望类型 `.bool`）。

### 验证结果
`tests/aot_verification/file_test.php` 验证通过：
- 文件写入 (`file_put_contents`)
- 文件存在检查 (`file_exists`, `cond_br` 正确工作)
- 文件读取 (`file_get_contents`)
- 文件删除 (`unlink`)

## 3. 下一步 (Phase 3 展望)

当前 AOT 编译器已经具备了处理 JSON 数据和文件操作的能力，且基础控制流（If-Else）工作正常。
接下来的重点可以放在：
1.  **内存管理**: 目前的测试显示存在内存泄漏 (`error(gpa): memory address ... leaked`)。需要完善 `release` 机制。
2.  **更复杂的控制流**: 循环 (`foreach`, `while`) 的深度验证。
3.  **函数调用与闭包**: 支持用户定义函数。

## 结论
Phase 2 成功解决了数据访问和基础 I/O 的阻塞性问题。AOT 编译器现在可以正确编译并运行包含数据处理和文件操作的 PHP 脚本。
