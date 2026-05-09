# FunctionRegistry 重构 — 会话交接文档

> 日期: 2026-05-09  
> 状态: P2 default_args 已完成, P2 runtime模块化进行中, P3 native_linker部分完成

---

## 1. 高层摘要 (TL;DR)

本次会话完成了 FunctionRegistry 重构的第二阶段：
- **P2-完成**: `FunctionMeta.default_args` 声明式参数补齐，用 ~115 行泛型循环替代了 ~320 行手工 switch 
- **P3-部分完成**: `native_linker.zig` 中 `byref_funcs` 预扫描和 `error_suppress` 检查已迁移到 FunctionId
- **P2-进行中**: `runtime_lib_template.zig` 模块化拆分（PCRE 提取方案已设计，未执行）

---

## 2. 已完成的变更

### 2.1 `src/aot/function_registry.zig`

#### 新增 `DefaultArgValue` 类型 (约第51行)
```zig
pub const DefaultArgValue = union(enum) {
    none: void,       // 位置已被用户提供，不需要填充
    int_val: i64,     // 默认整数值
    null_val: void,   // 默认 null
    bool_val: bool,   // 默认布尔值
    string_val: []const u8, // 默认字符串（编译期常量）
    missing: void,    // 特殊：const_missing 标记
};
```

#### `FunctionMeta` 新增字段
```zig
default_args: []const DefaultArgValue = &[_]DefaultArgValue{},
```

#### 已填充 `default_args` 的函数列表
| 函数 | default_args |
|------|-------------|
| print_r | `{.none, .{.bool_val = false}}` |
| var_export | `{.none, .{.bool_val = false}}` |
| strpos/stripos/strrpos/strripos | `{.none, .none, .{.int_val = 0}}` |
| substr | `{.none, .none, .null_val}` |
| trim/ltrim/rtrim | `{.none, .null_val}` |
| str_replace/str_ireplace | `{.none, .none, .none, .null_val}` |
| ucwords | `{.none, .null_val}` |
| explode | `{.none, .none, .null_val}` |
| str_split | `{.none, .{.int_val = 1}}` |
| str_pad | `{.none, .none, .{.string_val = " "}, .{.int_val = 1}}` |
| chunk_split | `{.none, .{.int_val = 76}, .{.string_val = "\r\n"}}` |
| wordwrap | `{.none, .{.int_val = 75}, .{.string_val = "\n"}, .{.bool_val = false}}` |
| nl2br | `{.none, .{.bool_val = true}}` |
| strip_tags | `{.none, .null_val}` |
| htmlspecialchars/htmlentities | `{.none, .{.int_val = 0}, .{.string_val = "UTF-8"}, .{.bool_val = true}}` |
| htmlspecialchars_decode | `{.none, .{.int_val = 0}}` |
| number_format | `{.none, .{.int_val = 0}, .{.string_val = "."}, .{.string_val = ","}}` |
| md5/sha1/base64_decode | `{.none, .{.bool_val = false}}` |
| uniqid | `{.{.string_val = ""}, .{.bool_val = false}}` |
| json_decode | `{.none, .{.bool_val = false}}` |
| array_walk/array_walk_recursive | `{.none, .none, .null_val}` |
| array_splice | `{.none, .{.int_val = 0}, .null_val, .null_val}` |
| iterator_to_array | `{.none, .missing}` |
| preg_grep | `{.none, .none, .{.int_val = 0}}` |
| preg_quote | `{.none, .null_val}` |

#### 新增 Registry 条目
```zig
.{ .php_name = "php_error_suppress_push", .runtime_name = "php_error_suppress_push", .category = .internal, .may_raise = false },
.{ .php_name = "php_error_suppress_pop", .runtime_name = "php_error_suppress_pop", .category = .internal, .may_raise = false },
```

#### `getMeta` 函数（已存在）
```zig
pub fn getMeta(id: FunctionId) FunctionMeta {
    return registry[id];
}
```

---

### 2.2 `src/aot/ir_generator.zig`

#### 声明式自动参数补齐 (约第5914-6029行)
**之前**: ~320行 switch(pad_fid) 手工逐函数补齐  
**之后**: ~115行泛型循环 + 3个特殊 switch arm

核心逻辑:
```zig
if (pad_fid != 0) {
    const pad_meta = FunctionRegistry.getMeta(pad_fid);
    const defs = pad_meta.default_args;
    
    // 通用自动补齐
    if (defs.len > 0 and args.len < defs.len) {
        const padded = try self.allocator.alloc(Register, defs.len);
        for (padded, 0..) |*slot, i| {
            if (i < args.len) {
                slot.* = args[i];
            } else {
                slot.* = switch (defs[i]) {
                    .none => args[i],
                    .int_val => |v| try self.emitWithResult(.{ .const_int = v }, .i64),
                    .null_val => try self.emitWithResult(.{ .const_null = {} }, .php_value),
                    .bool_val => |v| try self.emitWithResult(.{ .const_bool = v }, .bool),
                    .string_val => |s| blk: {
                        const sid = try self.module.?.internString(s);
                        break :blk try self.emitWithResult(.{ .const_string = sid }, .php_value);
                    },
                    .missing => try self.emitWithResult(.{ .const_missing = {} }, .php_value),
                };
            }
        }
        args = padded;
    }
    
    // 特殊处理（仅3个arm保留）
    switch (pad_fid) {
        comptimeLookup("preg_match") => { /* alloca + func_name改写 */ },
        comptimeLookup("preg_match_all") => { /* alloca逻辑 */ },
        comptimeLookup("password_hash") => { /* 截断到2参数 */ },
        else => {},
    }
}
```

#### error_suppress 设置 function_id (约第5072行)
```zig
.function_id = FunctionRegistry.comptimeLookup("php_error_suppress_push"),
.function_id = FunctionRegistry.comptimeLookup("php_error_suppress_pop"),
```

---

### 2.3 `src/aot/native_linker.zig`

#### byref_funcs 预扫描 — FunctionId switch (约第3545行)
**之前**: 12个字符串的内循环比较 O(12n)  
**之后**: FunctionId switch O(1) jump table

```zig
const is_byref_first = if (call_op.function_id != 0) switch (call_op.function_id) {
    FunctionRegistry.comptimeLookup("array_push"),
    FunctionRegistry.comptimeLookup("array_pop"),
    // ... 共12个
    => true,
    else => false,
} else false;
```

#### error_suppress 检查 — FunctionId (约第7810行和15156行)
**之前**: `std.mem.eql(u8, op.func_name, "php_error_suppress_push")`  
**之后**: `op.function_id == FunctionRegistry.comptimeLookup("php_error_suppress_push")`

---

## 3. 验证状态

| 验证项 | 结果 |
|--------|------|
| `zig build` | ✅ 通过 |
| function_registry 单元测试 (6/6) | ✅ 通过 |
| 回归测试 25样本 | 22/25 pass (3 pre-existing) |
| 参数补齐专项测试 | ✅ 全部通过（wordwrap尾部空格是pre-existing runtime bug） |
| 0编译失败 | ✅ |

---

## 4. 未完成的任务

### 4.1 P2: runtime_lib_template 模块化拆分 (进行中)

#### 设计方案
- **目标文件**: `src/aot/runtime_pcre.zig` (首个拆分目标)
- **提取范围**: 原文件第 8343-9067 行 (PCRE2 正则表达式支持, ~725行)
- **架构**: 互相导入模式（Zig允许非循环依赖的互相导入）

```
runtime_lib.zig (主模板)
├── @import("runtime_pcre.zig")  → re-export pub fn preg_*
├── @import("concurrency_runtime.zig")  (已有)
├── @import("array_ops_shared.zig")     (已有)
├── @import("nanbox_abi.zig")           (已有)
└── @import("function_registry.zig")    (已有)

runtime_pcre.zig (新建)
├── @import("runtime_lib.zig")  → 获取 Value, PHPArray, PHPString
├── 自包含: pcre2 extern, regex_cache, ParsedPattern
└── pub fn: preg_match, preg_match_all, preg_match_with_matches,
            preg_replace, preg_filter, preg_split, preg_grep,
            preg_quote, preg_last_error
```

#### 实施步骤
1. **创建 `src/aot/runtime_pcre.zig`**:
   ```zig
   const std = @import("std");
   const Allocator = std.mem.Allocator;
   const runtime = @import("runtime_lib.zig");
   const Value = runtime.Value;
   const PHPArray = runtime.PHPArray;
   const PHPString = runtime.PHPString;
   
   // [粘贴第8346-9067行的内容]
   ```

2. **修改 `runtime_lib_template.zig`**:
   - 删除第 8343-9067 行（PCRE 区段）
   - 在文件顶部 imports 区添加:
     ```zig
     const pcre = @import("runtime_pcre.zig");
     ```
   - 在删除位置添加 re-exports:
     ```zig
     pub const preg_match = pcre.preg_match;
     pub const preg_match_all = pcre.preg_match_all;
     pub const preg_match_with_matches = pcre.preg_match_with_matches;
     pub const preg_replace = pcre.preg_replace;
     pub const preg_filter = pcre.preg_filter;
     pub const preg_split = pcre.preg_split;
     pub const preg_grep = pcre.preg_grep;
     pub const preg_quote = pcre.preg_quote;
     pub const preg_last_error = pcre.preg_last_error;
     ```

3. **修改 `native_linker.zig` 第15818行** — 添加到 `copyOtherRuntimeFiles`:
   ```zig
   .{ .src = "src/aot/runtime_pcre.zig", .dst = "runtime_pcre.zig" },
   ```

4. **验证**:
   - `zig build` 编译通过
   - 回归测试无新增失败
   - 运行包含 preg_match 的测试脚本

#### PCRE 模块依赖分析
| 依赖项 | 来源 | 类型 |
|--------|------|------|
| Value | runtime_lib.zig | 类型（struct + methods） |
| PHPArray | runtime_lib.zig | 类型（arr.push, arr.set, arr.elements） |
| PHPString | runtime_lib.zig | 类型（PHPString.init） |
| Allocator | std.mem | 标准库 |
| pcre2_* | extern C | PCRE2 库 |
| regex_cache | 自包含全局 | 可随PCRE迁移 |

#### 后续拆分候选（按优先级）
| 模块 | 行范围 | 行数 | 依赖复杂度 | 风险 |
|------|--------|------|------------|------|
| runtime_pcre.zig | 8343-9067 | 725 | 低 | 低 |
| runtime_time.zig | 17113-17390 | 280 | 低 | 低 |
| runtime_random.zig | 17390-17557 | 167 | 极低(MT19937自包含) | 极低 |
| runtime_math.zig | 9968-10405 | 440 | 中(Value转换) | 中 |
| runtime_spl.zig | 6697-7801 | 1100 | 高(PHPObject) | 高 |

---

### 4.2 P3: native_linker 剩余字符串特判 (部分完成)

#### 已完成
- ✅ `byref_funcs` 预扫描 → FunctionId switch
- ✅ `error_suppress_push/pop` → FunctionId 比较
- ✅ 注册 `php_error_suppress_push/pop` 到 FunctionRegistry

#### 未完成 — 主要 `.call` 代码生成 if/else 链
位置: `native_linker.zig` 约第 7845-8460 行

**当前状况**: ~40个 `std.mem.eql(u8, runtime_name, "...")` 串联比较

**推荐方案**: 分阶段转换
1. **Phase A** (安全): 将 `throwThrowable`, `preg_match` 家族转为 `op.function_id` switch
2. **Phase B** (中风险): 将 `needs_allocator` 分支内的特判转为 FunctionId
3. **Phase C** (可选): 为常见的"需要补齐可选参数"的函数添加 `default_args`，让 IR 层补齐，从而简化 native_linker

**关键约束**: 
- `op.function_id` 在 is_builtin 时必定 != 0
- `runtime_name` 仍需保留（用于生成 `runtime.{s}(` 调用代码）
- 特殊调用约定（variadic array, first-arg-then-array）无法用 default_args 自动化

**具体待转换的 runtime_name 检查** (按复杂度排序):

| runtime_name | 特殊性 | 转换难度 |
|--------------|--------|----------|
| throwThrowable | 参数转 []const u8 | 简单 |
| php_max / php_min | writeValueArgsArray | 简单 |
| php_in_array | 可选第3参数 | 简单 |
| php_sprintf / php_printf | 格式串+可变数组 | 中等 |
| php_array_push / php_array_unshift | first-arg+array | 中等 |
| php_call_user_func | 全参数数组切片 | 中等 |
| php_isset / php_unset | 全参数数组切片 | 中等 |
| 大量 `needs_allocator` 内特判 | 各种可选参数 | 高（可用default_args减少） |

---

## 5. 当前 TODO 状态

```
[x] Phase 1-4 完成 (FunctionRegistry + IR FunctionId + native_linker fast-path + switch jump table)
[x] P2: FunctionMeta 增加 default_args → 自动化参数补齐
[ ] P2: runtime_lib_template 模块化拆分 (方案已设计)
[~] P3: native_linker 剩余字符串特判迁移到 FunctionId (byref+error_suppress已完成)
```

---

## 6. 关键技术注意事项

### Zig 0.15.2 互相导入
- Zig 允许文件 A import B 同时 B import A，只要不形成**编译期求值**循环
- `runtime_pcre.zig` import `runtime_lib.zig` 获取 Value 类型是安全的（Value 不依赖 PCRE）

### `comptimeLookup` 性能
- 使用 `@setEvalBranchQuota(100000)` + `inline for (0..REGISTRY_SIZE)`
- Registry 当前约 570 条目，编译期展开无问题
- 每个新增 registry 条目会略微增加编译时间（线性关系，可忽略）

### `default_args` 设计决策
- `.none` 表示该位置参数由用户提供，不填充
- 当 `args.len >= defs.len` 时，不触发补齐（用户提供了所有参数）
- `preg_match`/`preg_match_all` 保留手工逻辑（需要 alloca + func_name 修改）
- `password_hash` 保留截断逻辑（runtime 只接受2参数）

### native_linker 文件复制
- `copyOtherRuntimeFiles` 列表位于约第 15818 行
- 新增模块文件**必须**添加到此列表，否则运行时编译缺少文件

---

## 7. 文件修改清单

| 文件 | 修改类型 | 行范围 |
|------|----------|--------|
| `src/aot/function_registry.zig` | 新增类型+字段+条目 | 51-92, 115-360, 552-553 |
| `src/aot/ir_generator.zig` | 替换switch为泛型循环 | 5914-6029; 5072-5084 |
| `src/aot/native_linker.zig` | byref FunctionId + error_suppress | 3545-3578; 7809-7813; 15155-15159 |

---

## 8. 后续开发建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|----------|
| P0 | 完成 runtime_pcre.zig 提取 | 可维护性，编译时间 | 1-2h |
| P1 | native_linker `.call` top-5 特判迁移 FunctionId | 性能+可维护 | 2-3h |
| P1 | 为 native_linker 中补参数的函数也加 default_args（count, round, array_chunk等） | 消除重复逻辑 | 2h |
| P2 | 提取 runtime_time.zig + runtime_random.zig | 可维护性 | 1h each |
| P2 | 添加 `CallingConvention` 枚举到 FunctionMeta | 消除 native_linker 大量特判 | 4h |
| P3 | 对 native_linker `.call` 全链条做 FunctionId switch 重构 | 性能 | 8h+ |

---

## 9. 回归测试命令

```bash
# 编译
timeout 120 zig build

# 单元测试
timeout 60 zig test src/aot/function_registry.zig

# 回归测试 (25样本)
cd zig-php-parser
PASS=0; FAIL=0; COMP_FAIL=0
for f in $(ls fuzzy_scripts/test_*.php | head -25); do
  base=$(basename "$f" .php)
  expected=$(timeout 10 php "$f" 2>&1 || true)
  if timeout 60 ./zig-out/bin/php-interpreter --compile "$f" --output="/tmp/${base}" 2>/dev/null; then
    actual=$(timeout 10 "/tmp/${base}" 2>&1 || true)
    rm -f "/tmp/${base}"
    [ "$expected" = "$actual" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
  else
    COMP_FAIL=$((COMP_FAIL+1))
  fi
done
echo "Pass=$PASS Fail=$FAIL CompFail=$COMP_FAIL"
# 预期: Pass=22 Fail=3 CompFail=0

# 参数补齐专项
cat > /tmp/test_pad.php << 'EOF'
<?php
echo strpos("hello", "lo") . "\n";          // 3
echo substr("hello", 1) . "\n";             // ello
echo trim("  x  ") . "\n";                  // x
echo str_replace("o","0","foo") . "\n";      // f00
echo json_decode('{"a":1}', true)["a"] . "\n"; // 1
echo "OK\n";
EOF
# 编译并对比 php 输出
```
