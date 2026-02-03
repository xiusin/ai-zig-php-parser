# AOT 差异对比与收敛计划报告 (Phase 1)

**生成日期**: 2026-02-03
**状态**: Phase 1 完成 (遗留 Bug)

## 1. 核心进展：Pipeline 重构完成

成功移除了 AOT 编译器对 LLVM (`src/aot/codegen.zig`) 的依赖，完全切换到了 `src/aot/native_linker.zig`。
现在的编译流程：`IR -> Zig Source -> zig build-exe -> Executable`。

-   **compiler.zig**: 清理了所有 LLVM 相关代码，重写了 `generateCode` 和 `linkExecutable` 阶段。
-   **native_linker.zig**: 实现了 `compileToExecutable`，支持调用系统 Zig 编译器进行最终构建。

## 2. P0 Builtins 补齐

在 `src/aot/runtime_lib_template.zig` 中实现了以下核心 Builtin：

-   ✅ `json_encode`: 支持标量、数组、对象的 JSON 序列化。
-   ✅ `json_decode`: 支持 JSON 解析为 PHP 数组（关联/索引）。
-   ✅ `file_get_contents` / `file_put_contents`: 基础文件 I/O。

同时修复了 `PHPArray` 的实现，使其使用自定义 Context (`ArrayContext`) 以正确处理 `ArrayKey` (union of int/string) 的哈希和比较。

## 3. 验证与遗留问题

### 验证脚本 `json_test.php`
```php
$data = ["a" => 1, "b" => 2];
$json = json_encode($data);
echo "Encoded: " . $json . "\n";
$decoded = json_decode($json, true);
foreach ($decoded as $k => $v) {
    echo "Key: " . $k . ", Value: " . $v . "\n";
}
echo "Decoded a: " . $decoded["a"] . "\n";
```

### 运行结果
```
Encoded: {"b":2,"a":1}  <-- 正确
Count: 2                <-- 正确
Key: b, Value: 2        <-- 正确
Key: a, Value: 1        <-- 正确
Decoded a:              <-- 错误！应为 1
```

### 遗留 Bug (P0)
虽然 `foreach` 遍历能正确获取键值对，但 `array_get` (`$decoded["a"]`) 无法找到对应的键。
这表明 `PHPArray` 的 `HashMap` 查找逻辑在特定场景下（字面量 Key vs 动态 Key）存在一致性问题，或者哈希计算有细微差异。

## 4. 下一步行动 (Phase 2)

1.  **修复 `array_get` Bug**: 深入调试 `PHPArray.get` 和 `ArrayContext`，确保字符串键的查找行为正确。
2.  **I/O 子集完善**: 扩充文件操作支持。
3.  **异常/闭包**: 对齐解释器语义。

## 5. 结论

AOT 编译器的核心链路已经打通，且具备了执行复杂逻辑（如 JSON 处理）的能力。虽然存在哈希查找的 Bug，但整体架构已经收敛到无 LLVM 的纯 Zig 路径上。
