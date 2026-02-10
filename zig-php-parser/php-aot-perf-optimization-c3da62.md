# PHP AOT 编译器深度性能优化方案（Zig Comptime 增强版）

全面利用 Zig 编译时计算特性 + Runtime 优化，目标：所有测试项性能超越 PHP-CLI。

---

## 📊 当前基线 vs 目标

| 测试项 | 当前倍数 | 目标倍数 | 核心优化手段 |
|--------|----------|----------|-------------|
| 简单循环 | 5.0x 慢 | ≤1.0x | comptime 类型特化 → 原生 i64 循环 |
| 嵌套循环 | 4.8x 慢 | ≤1.0x | comptime 循环展开 + 零开销抽象 |
| 算术运算 | 3.6x 慢 | ≤1.0x | comptime 运算符特化 → 原生算术 |
| 数组求和 | 20.4x 慢 | ≤1.5x | LICM + comptime @Vector SIMD |
| 字符串拼接 | 1084x 慢 | ≤2.0x | comptime 常量折叠 + LICM |
| **总计** | **14.3x** | **≤1.5x** | |

---

## 🔴 P0-1: 字符串操作优化（1084x → ≤2x）

### 根因
```php
for ($i = 0; $i < 1000; $i++) {
    $str = "Hello" . " " . "World";  // 纯常量，应编译期折叠
}
```
每次循环调用 `php_concat` 两次 → alloc + memcpy + PHPString 对象创建。

### 1.1 IR 层常量字符串折叠
- **文件**: `optimizer.zig` → `propagateConstantsInFunction`
- 当 `concat` 两个操作数都是 `const_string` → 编译期合并为单个 `const_string`
- **效果**: 1084x → ~5x

### 1.2 comptime 静态字符串池（Zig 编译时特性）
- **文件**: `native_linker.zig` 代码生成层
- **做法**: 对所有 PHP 字面量字符串，生成 Zig `comptime` 静态常量：
  ```zig
  // 生成代码中嵌入编译期字符串常量
  const str_pool = struct {
      const s0 = comptimeStaticString("Hello World");
      const s1 = comptimeStaticString("Hello");
      // ...
  };
  ```
- **Runtime 配合**: 新增 `comptimeStaticString` 函数，返回 `*PHPString`，`ref_count = MAX`（永不释放），`is_static = true`
- 利用 Zig 的 `comptime` 在编译期完成字符串哈希、长度计算、内存布局
- **效果**: 字面量字符串零运行时分配，零 GC 压力

### 1.3 comptime 多段拼接融合
- **文件**: `native_linker.zig`
- 对 `"A" . "B" . "C"` 链式拼接，代码生成时检测并生成：
  ```zig
  // 替代两次 php_concat 调用
  const result = try php_concat_slices(
      &[_][]const u8{ "Hello", " ", "World" },
      allocator
  );
  ```
- **Runtime**: 新增 `php_concat_slices` — 一次计算总长度、一次分配、一次拷贝
- **效果**: N 段拼接从 N-1 次分配 → 1 次分配

### 1.4 PHPString COW（Copy-On-Write）就地复用
- **文件**: `runtime_lib_template.zig` → `PHPString.concat`
- 当 `self.ref_count == 1` 且 `!self.is_static` → `realloc` 扩展，避免新建对象
- **效果**: `$str .= "abc"` 累加模式减少 50% 分配

### 1.5 comptime 生成的 StringBuilder
- **文件**: `runtime_lib_template.zig`
- 利用 Zig comptime 泛型生成不同容量级别的 StringBuilder：
  ```zig
  fn StringBuilderFor(comptime initial_cap: usize) type {
      return struct {
          buf: [initial_cap]u8 = undefined,  // 栈上缓冲
          len: usize = 0,
          overflow: ?[]u8 = null,  // 溢出时堆分配
          // ...
      };
  }
  ```
- 编译器检测 `$str .= X` 循环模式 → 自动使用 `StringBuilderFor(256)`
- **效果**: 累加型 O(n²) → O(n)

---

## 🔴 P0-2: 修复 LICM + DCE 安全性

### 2.1 LICM Bug 修复
- **文件**: `optimizer.zig:692-926`
- `getOrCreatePreHeader` 后完整重建 CFG
- `isLoopInvariant` 扩展：`concat`（纯常量操作数）、`const_string` 可提升
- 循环完整性验证：LICM 后检查归纳变量递增仍存在

### 2.2 DCE 保守策略
- 标记循环归纳变量为"活跃"
- DCE 不删除被循环终止条件依赖的指令链
- 新增 `isLoopInductionVariable` 检测

### 2.3 在 `releaseSafe` 中安全启用 LICM
- 修复后将 `PassConfig.releaseSafe().licm` 改为 `true`

---

## 🟡 P1-1: 数组操作优化（20.4x → ≤1.5x）

### 3.1 comptime @Vector SIMD 求和
- **文件**: `runtime_lib_template.zig` → `php_array_sum`
- 利用 Zig 的 `@Vector` 类型实现编译期 SIMD 向量化：
  ```zig
  fn fastIntSum(values: []const Value) i64 {
      const vec_len = comptime std.simd.suggestVectorLength(i64) orelse 4;
      const V = @Vector(vec_len, i64);
      var accum: V = @splat(0);
      // 主循环：向量化累加
      var i: usize = 0;
      while (i + vec_len <= values.len) : (i += vec_len) {
          // 批量提取 NaN-boxed int → 原生 i64
          var batch: V = undefined;
          inline for (0..vec_len) |j| {
              batch[j] = values[i + j].asInt();
          }
          accum += batch;
      }
      // 水平归约
      return @reduce(.Add, accum) + scalarTail(values[i..]);
  }
  ```
- `comptime` 自动选择最优向量宽度（AVX2=4, AVX512=8）
- **效果**: 纯整数数组求和 3-5x 提升

### 3.2 LICM 纯函数白名单
- `isLoopInvariant` 添加纯函数识别：
  ```zig
  const pure_functions = comptime std.StaticStringMap(void).initComptime(.{
      .{ "array_sum", {} }, .{ "count", {} },
      .{ "strlen", {} },   .{ "array_count", {} },
  });
  ```
- 当 `call` 的函数名在白名单中且参数为循环不变量 → 可提升
- **效果**: `array_sum($arr)` 循环内 10000 次 → 1 次

### 3.3 comptime 数组字面量预分配
- 对 `[1,2,3,4,5]` 等编译期已知数组，生成代码时：
  ```zig
  // 替代逐个 push
  const arr = try PHPArray.initWithCapacity(allocator, 5);
  // 或更激进：comptime 生成静态数组数据
  ```

---

## 🟡 P1-2: 循环深度优化（5x → ≤1x）

### 4.1 comptime 运算符特化代码生成
- **文件**: `native_linker.zig` 代码生成
- 当类型推断确定循环变量为 `i64` 时，生成特化代码：
  ```zig
  // 替代：reg_0 = try runtime.php_add(reg_0, reg_1);
  // 生成：reg_0 += reg_1;  // 原生 i64 加法
  ```
- 利用 Zig comptime 泛型生成类型特化的运算函数：
  ```zig
  fn TypedOp(comptime T: type) type {
      return struct {
          inline fn add(a: T, b: T) T { return a + b; }
          inline fn lt(a: T, b: T) bool { return a < b; }
      };
  }
  ```
- **效果**: 消除 NaN boxing/unboxing 开销，循环性能接近原生 C

### 4.2 comptime 循环展开因子自动选择
- 根据循环体指令数 comptime 计算最优展开因子：
  ```zig
  const unroll_factor = comptime blk: {
      const body_size = @sizeOf(LoopBody);
      if (body_size <= 64) break :blk 8;
      if (body_size <= 256) break :blk 4;
      break :blk 2;
  };
  ```
- 已有展开逻辑（`generateStandardForLoop`），增强为 comptime 驱动

### 4.3 comptime 生成的 NaN Boxing 快速路径
- **文件**: `runtime_lib_template.zig` → `Value` 结构
- 对高频操作（`isInt`, `asInt`, `initInt`）确保 `inline` + 零分支：
  ```zig
  pub inline fn isInt(self: Value) bool {
      return (self.bits & TAG_INT_MARKER) == TAG_INT_MARKER;
  }
  pub inline fn asInt(self: Value) i64 {
      // comptime 验证位操作正确性
      comptime std.debug.assert(TAG_INT_MARKER == 0xFFFC000000000000);
      return nanbox_abi.decodeInt(self.bits);
  }
  ```
- 在生成代码中对已知类型的运算添加 `@branchHint(.likely)`

---

## 🔵 P2-1: comptime 驱动的标准库高性能实现

### 5.1 comptime 查找表生成
- `strtoupper`/`strtolower` 使用 comptime 生成 256 字节查找表：
  ```zig
  const upper_table = comptime blk: {
      var table: [256]u8 = undefined;
      for (&table, 0..) |*c, i| {
          c.* = if (i >= 'a' and i <= 'z')
              @intCast(i - 32)
          else
              @intCast(i);
      }
      break :blk table;
  };
  ```
- 运行时单次查表替代分支判断，配合 `@Vector` 可 SIMD 化

### 5.2 comptime 函数分派表
- 已有 `StaticStringMap` 用于内置函数查找，扩展为 comptime 生成的完美哈希：
  ```zig
  const dispatch = comptime PerfectHash(BuiltinFn).init(.{
      .{ "strlen", php_strlen },
      .{ "count", php_count },
      // ...
  });
  ```
- 函数调用从 HashMap 查找 → comptime 完美哈希 O(1)

### 5.3 comptime 内联展开高频函数
- 对 `strlen`、`count`、`intval` 等简单函数，代码生成时直接内联：
  ```zig
  // 替代：reg_5 = try runtime.php_strlen(reg_3);
  // 生成：reg_5 = Value.initInt(@intCast(reg_3.asString().length));
  ```
- 在 `native_linker.zig` 的 `generateInstruction` 中对已知函数名做特殊处理

---

## 🔵 P2-2: comptime 类型推断 + 特化

### 6.1 编译期类型流分析
- 从赋值链推断：`$i = 0` → int，`$i++` → int，`$i < 100000` → int 比较
- 在 IR 层标记寄存器类型，代码生成时跳过类型检查

### 6.2 comptime 泛型运算符
- 生成代码中使用 comptime 泛型消除运行时类型分派：
  ```zig
  // 当编译器确定两个操作数都是 int 时
  inline fn addTyped(comptime T: type, a: T, b: T) T {
      return a +% b;  // 溢出安全的原生加法
  }
  ```

### 6.3 comptime 生成的 Inline Cache
- 对多态调用点，comptime 生成单态/双态缓存结构：
  ```zig
  fn MonomorphicIC(comptime expected_type: ValueType) type {
      return struct {
          inline fn dispatch(val: Value) i64 {
              if (comptime expected_type == .int) {
                  return val.asInt();  // 零分支快速路径
              }
              return val.toInt();  // fallback
          }
      };
  }
  ```

---

## 🔵 P2-3: OOP comptime 优化

### 7.1 comptime 属性偏移表
- 对已知类定义，comptime 生成固定偏移量：
  ```zig
  const MyClassLayout = comptime struct {
      const prop_x_offset = 0;
      const prop_y_offset = 1;
      // 替代 HashMap 查找
  };
  ```

### 7.2 comptime 方法虚表
- 非虚方法（final class）comptime 直接绑定函数指针
- 虚方法使用 comptime 生成的 vtable 数组替代 HashMap

### 7.3 comptime Escape Analysis 标记
- 编译期标记对象是否逃逸，未逃逸 → 栈分配：
  ```zig
  // comptime 分析后生成
  var obj_storage: [ObjectSize]u8 align(@alignOf(PHPObject)) = undefined;
  var obj = @ptrCast(*PHPObject, &obj_storage);  // 栈上
  ```

---

## 📋 实施步骤

| # | 任务 | 预期提升 | Zig comptime 特性 | 影响文件 |
|---|------|---------|-------------------|---------|
| 1 | IR 常量字符串折叠 | 1084x→5x | — | optimizer.zig |
| 2 | comptime 静态字符串池 | 5x→3x | `comptime` 常量 | native_linker.zig, runtime |
| 3 | 修复 LICM + 启用 release-safe | 3x→2x | `comptime` 纯函数白名单 | optimizer.zig |
| 4 | DCE 安全性修复 | 解锁优化 | — | optimizer.zig |
| 5 | comptime @Vector SIMD 数组求和 | 20x→5x | `@Vector`, `@reduce` | runtime_lib_template.zig |
| 6 | LICM 纯函数识别 | 5x→1.5x | `StaticStringMap.initComptime` | optimizer.zig |
| 7 | comptime 运算符特化代码生成 | 循环 5x→1.5x | `inline fn`, 泛型 | native_linker.zig |
| 8 | PHPString COW + StringBuilder | 累加场景 | comptime 泛型容量 | runtime_lib_template.zig |
| 9 | comptime 查找表（upper/lower） | 标准库 2x | comptime 数组初始化 | runtime_lib_template.zig |
| 10 | comptime 函数内联展开 | 全局 1.2x | — | native_linker.zig |
| 11 | 多段拼接融合 | 字符串 1.5x | — | native_linker.zig, runtime |
| 12 | OOP comptime 属性偏移 | OOP 场景 | comptime struct | runtime, native_linker |
| 13 | 最终基准测试验证 | 确认 ≤1.5x | — | benchmark_performance.php |

---

## ⚠️ 风险控制

- 每步完成后立即编译 + 运行 benchmark 验证
- LICM 修复后先用小用例测试
- 所有 comptime 代码确保不引入编译期膨胀（生成代码体积监控）
- 内存操作确保 `errdefer` 正确释放
- 编译超时 30s，运行超时 5s

## 🧬 Zig Comptime 特性利用总结

| Zig 特性 | 应用场景 | 性能收益 |
|----------|---------|---------|
| `comptime` 常量求值 | 字符串池、查找表、哈希 | 零运行时开销 |
| `@Vector` + `@reduce` | 数组 SIMD 求和 | 4-8x 向量化 |
| `inline fn` | NaN boxing 操作、运算符 | 零函数调用开销 |
| `comptime` 泛型 | StringBuilder、TypedOp | 类型特化零分派 |
| `@branchHint` | 快速路径标记 | 分支预测优化 |
| `StaticStringMap.initComptime` | 函数分派、纯函数白名单 | O(1) 查找 |
| `comptime` struct 布局 | OOP 属性偏移 | 替代 HashMap |
| `std.simd.suggestVectorLength` | 自适应 SIMD 宽度 | 跨平台最优 |
