# AOT 编译器修复进度总结报告

## 本轮修复成果

### 已完成修复 (14项)

| # | 修复内容 | 影响测试 | 文件 |
|---|---------|---------|------|
| 1 | 引用参数带默认值 `&$ref = null` | test_058_object_graph | native_linker.zig |
| 2 | PHP_INT_MAX/MIN BigInt堆装箱 + 科学计数法 | test_041_number_boundary | runtime_lib_template.zig |
| 3 | `??` 操作符不触发 undefined variable 警告 | test_011, test_048 | native_linker.zig |
| 4 | stderr/stdout 输出顺序匹配 PHP (所有emitter) | test_077, test_041, test_057 | runtime_lib_template.zig |
| 5 | **异常跨函数边界传播** (throw返回null而非error) | test_053 x3 | native_linker.zig |
| 6 | sprintf `%.Nf` 精度支持 (formatFloatPrecision) | 通用 | runtime_lib_template.zig |
| 7 | **PHP 8.0 throw-as-expression** (三元/coalesce) | test_050_throw_expressions | ir_generator.zig |
| 8 | 第三throw handler路径error.PHPException修复 | 通用 | native_linker.zig |
| 9 | **命名参数重排序** (module-based fallback) | test_003, test_051 | ir_generator.zig |
| 10 | **load指令类型转换bug** (bool→asInt()=0) | test_0450/0451, 全局 | native_linker.zig |
| 11 | **return语句类型转换bug** (同load) | test_0450/0451 trait | native_linker.zig |
| 12 | **self::class/parent::class解析** | 通用 | ir_generator.zig |
| 13 | **instanceof Stringable** (magic_toString检查) | test_059 | runtime_lib_template.zig |
| 14 | **throw-expression parser precedence** (避免match arm逗号消费) | test_056 | parser.zig |

### 关键架构修复说明

**#5 异常跨函数边界传播** — 根因：方法内 `throw` 生成 `return error.RuntimeError`，调用方 `try php_object_call(...)` 会把 Zig error 直接传播到上层，跳过 `hasException()` 检查，导致 try-catch 永远捕获不到跨函数异常。修复：throw 改为 `return Value.initNull()`，异常信息已通过 `setException()` 设置，调用方的 `hasException()` 正常路由到 catch 块。

**#7 throw-as-expression** — PHP 8.0 允许 `throw` 在表达式上下文中使用（三元、null coalesce 等）。在 `generateExpression` 中添加 `.throw_stmt` 处理：生成异常对象、设置 throw terminator、创建不可达块让后续代码生成继续。

### 测试通过率

- **pass 目录**: 33/39 通过 (84.6%，含timestamp race约 82.1%)
- **从 failed 移入 pass**: 10 个测试
  - test_041_number_boundary
  - test_050_throw_expressions
  - test_053_intersection_types
  - test_053_mixed_complex
  - test_053_sensitive_attribute
  - test_057_new_in_initializers
  - test_058_object_graph
  - test_0450_Trait组合
  - test_0451_Trait组合
  - test_059_stringable_interface

### pass 目录剩余 FAIL 分析

| 测试 | 原因 | 可修复性 |
|------|------|---------|
| test_032_type_declarations | PHP 8.4 Deprecated 隐式nullable | 低优先 |
| test_042_array_hash | memory_get_usage() AOT无法模拟 | AOT固有 |
| test_044_memory_performance | 内存+循环引用差异 | AOT固有 |
| test_056_final_constants | PHP 8.4 final const 编译期错误 | 低优先 |
| test_057_higher_order | PHP 8.3 static var 编译期错误 | 低优先 |
| test_057_new_in_initializers | timestamp race (秒级差异) | 非bug |
| test_064_array_splat_unpacking | 性能microtime()差异 | 非bug |

**#9 命名参数重排序** — 原因：当 symbol_table 没有函数元数据时，命名参数不会根据参数名重新排序到正确位置。修复：添加 IR module 函数参数列表作为 fallback，让 `createOrder('Keyboard', 3, express: true, currency: 'EUR')` 等混合位置+命名参数调用正确映射。

### 后续开发建议（按优先级排序）

1. **late static binding (`static::`)** — test_019: `static::class` 需要运行时传递调用类名（架构变更：ctx参数携带调用类信息）
2. **match(true) 复杂条件** — test_056: `match(true) { $x > 0 && $x < 100 => 'A' }` 解析器不支持
3. **引用赋值 (`&`)** — test_010: `$b = &$a` 引用共享不工作
4. **named variadic args** — test_051: `func(...$context)` 中 `context: [...]` 需要关联数组
5. **Enum 完整支持** — test_034/061: backed enum from()/tryFrom()/cases()
6. **SPL 迭代器** — test_060/066: LimitIterator, CachingIterator 等
7. **WeakMap/WeakRef** — test_069: 弱引用支持
8. **Reflection 完善** — test_040/065: ReflectionClass 属性/方法反射
9. **load/return 类型推断安全性** — 当前已禁用类型特化 load/return，可考虑精确化推断后重新启用以提升性能
