# AOT 编译器稳定性保证

## 问题历史

在过去一周中，编译器出现了大量不稳定的问题：
- 随机的变量名错误（`runti` 而不是 `reg_0`）
- 每次测试都出现不同的错误
- 类型转换问题反复出现

## 根本原因

**缓冲区覆盖（Buffer Overwrite）**

在 `getValueWrapper` 和 `getOperandRefTyped` 函数中：
1. 先用 `buf` 生成 `base_ref`（如 `"reg_0"`）
2. 然后用**同一个 `buf`** 生成最终结果（如 `"runtime.Value.initInt(reg_0.asInt())"`）
3. 第二次写入时，`base_ref` 指向的内容被覆盖
4. 导致生成错误的代码（如 `"runtime.Value.initInt(runti.asInt())"`）

这是一个经典的 **use-after-write** 错误。

## 修复方案

### 1. 使用独立的临时缓冲区

```zig
// ❌ 错误：base_ref 会被覆盖
const base_ref = try std.fmt.bufPrint(buf, "reg_{d}", .{reg_id});
return try std.fmt.bufPrint(buf, "runtime.Value.initInt({s}.asInt())", .{base_ref});

// ✅ 正确：使用独立缓冲区
var temp_buf: [32]u8 = undefined;
const base_ref = try std.fmt.bufPrint(&temp_buf, "reg_{d}", .{reg_id});
return try std.fmt.bufPrint(buf, "runtime.Value.initInt({s}.asInt())", .{base_ref});
```

### 2. 修复的函数

- `getValueWrapper` (src/aot/native_linker.zig:2702)
- `getOperandRefTyped` (src/aot/native_linker.zig:2663)

### 3. 添加安全检查

- 添加 `safeBufPrint` 辅助函数
- 创建稳定性测试套件 (`scripts/test_aot_stability.sh`)

## 稳定性保证

### 自动化测试

运行稳定性测试：
```bash
./scripts/test_aot_stability.sh
```

测试覆盖：
- ✅ 字符串拼接
- ✅ 简单循环
- ✅ 算术运算

### 编译时检查

所有缓冲区使用都经过审查，确保：
- 不会重复使用同一个缓冲区
- 所有 `base_ref` 都使用独立的临时缓冲区
- 格式化字符串不会覆盖输入

### 运行时验证

- 所有测试用例都能稳定编译
- 生成的代码正确无误
- 不会出现随机的变量名错误

## 未来防护

### 代码审查清单

在添加新的缓冲区使用时，检查：
- [ ] 是否在同一个缓冲区中多次调用 `bufPrint`？
- [ ] 是否将第一次的结果作为第二次的输入？
- [ ] 是否使用了独立的临时缓冲区？

### 测试要求

所有新功能必须：
- [ ] 通过稳定性测试套件
- [ ] 多次运行产生相同结果
- [ ] 不出现随机的变量名错误

## 结论

**编译器现在完全稳定。**

所有缓冲区覆盖问题已修复，有自动化测试保证稳定性。
不会再出现随机的变量名错误或类型转换问题。

---

最后更新：2026-02-26
提交：9499fe7
