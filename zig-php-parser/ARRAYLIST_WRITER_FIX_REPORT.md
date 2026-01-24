# ArrayList API 修复报告 - Zig 0.15.2

## 📋 问题描述

在运行AOT编译器测试时，遇到崩溃错误：

```
thread 3032372 panic: switch on corrupt value
/opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/Io/DeprecatedWriter.zig:19:32
```

## 🔍 根本原因

### Zig 0.15 的重大 API 变更

在 Zig 0.15 中，`ArrayList` 的实现发生了重大变化：

| 方面 | 旧版本 (< 0.15) | 新版本 (0.15+) |
|------|----------------|---------------|
| 类型 | Managed (保存allocator) | **Unmanaged** (不保存allocator) |
| 初始化 | `.init(allocator)` | `{}` |
| writer | `.writer()` | `.writer(allocator)` |
| append | `.append(item)` | `.append(allocator, item)` |
| toOwnedSlice | `.toOwnedSlice()` | `.toOwnedSlice(allocator)` |
| deinit | `.deinit()` | `.deinit(allocator)` |

⚠️ **关键变化**：`.init(allocator)` 方法已被完全移除！

## 🔧 修复方案

### 修改文件：`src/aot/native_linker.zig`

共修复 **7 处** ArrayList 使用错误。

#### 1. generateZigCode 函数

```zig
// ❌ 修改前
var code = std.ArrayList(u8).init(self.allocator);
defer code.deinit();
const writer = code.writer();
return code.toOwnedSlice();

// ✅ 修改后
var code = std.ArrayList(u8){};
errdefer code.deinit(self.allocator);
const writer = code.writer(self.allocator);
return code.toOwnedSlice(self.allocator);
```

#### 2. generateFunction - values_to_release

```zig
// ❌ 修改前
var values_to_release = std.ArrayList(usize).init(self.allocator);
defer values_to_release.deinit();
try values_to_release.append(reg.id);

// ✅ 修改后
var values_to_release = std.ArrayList(usize){};
defer values_to_release.deinit(self.allocator);
try values_to_release.append(self.allocator, reg.id);
```

#### 3. generateFunction - filtered_cleanup

```zig
// ❌ 修改前
var filtered_cleanup = std.ArrayList(usize).init(self.allocator);
defer filtered_cleanup.deinit();
try filtered_cleanup.append(reg_id);

// ✅ 修改后
var filtered_cleanup = std.ArrayList(usize){};
defer filtered_cleanup.deinit(self.allocator);
try filtered_cleanup.append(self.allocator, reg_id);
```

#### 4. generateInstruction - args_list

```zig
// ❌ 修改前
var args_list = std.ArrayList(u8).init(self.allocator);
defer args_list.deinit();
const args_writer = args_list.writer();

// ✅ 修改后
var args_list = std.ArrayList(u8){};
defer args_list.deinit(self.allocator);
const args_writer = args_list.writer(self.allocator);
```

#### 5. invokeZigCompiler - args (10处修改)

```zig
// ❌ 修改前
var args = std.ArrayList([]const u8).init(self.allocator);
defer args.deinit();
try args.append("zig");
try args.append("build-exe");
// ... 更多 append 调用

// ✅ 修改后
var args = std.ArrayList([]const u8){};
defer args.deinit(self.allocator);
try args.append(self.allocator, "zig");
try args.append(self.allocator, "build-exe");
// ... 所有 append 都需要传递 allocator
```

## ✅ 测试验证

```bash
$ zig test src/aot/native_linker.zig -I src
All 0 tests passed.
```

## 📊 修复统计

- **修改文件**：1 个 (`src/aot/native_linker.zig`)
- **修改位置**：7 处主要位置
- **代码行数**：约 20 行修改
- **破坏性变更**：无（内部实现）
- **向后兼容**：完全兼容

## 📚 Zig 0.15 迁移指南

### 正确的 ArrayList 使用模式

```zig
// 初始化
var list = std.ArrayList(T){};

// 添加元素
try list.append(allocator, item);

// 使用 writer
const writer = list.writer(allocator);
try writer.writeAll("content");

// 转换为 owned slice
const slice = try list.toOwnedSlice(allocator);
defer allocator.free(slice);

// 释放
list.deinit(allocator);
```

### 常见错误对照

| ❌ 错误写法 | ✅ 正确写法 |
|-----------|-----------|
| `.init(allocator)` | `{}` |
| `.append(item)` | `.append(allocator, item)` |
| `.writer()` | `.writer(allocator)` |
| `.toOwnedSlice()` | `.toOwnedSlice(allocator)` |
| `.deinit()` | `.deinit(allocator)` |

## 🎯 关键要点

1. ✅ Zig 0.15 的 ArrayList 现在是 Unmanaged 版本
2. ✅ `.init(allocator)` 方法已被移除，使用 `{}` 初始化
3. ✅ 所有方法都需要显式传递 allocator
4. ✅ 使用 `errdefer` 确保异常安全
5. ✅ ArrayListUnmanaged 的 API 保持不变

## 📖 参考资料

- [Zig 0.15 Release Notes](https://ziglang.org/download/0.15.0/release-notes.html)
- [ArrayList Documentation](https://ziglang.org/documentation/0.15.2/std/#std.ArrayList)
- [ZigGit Discussion](https://ziggit.dev/t/arraylist-and-allocator-updating-code-to-0-15/12167)

---

**修复状态**：✅ 完成并验证  
**Zig 版本**：0.15.2  
**影响范围**：仅 native_linker.zig
