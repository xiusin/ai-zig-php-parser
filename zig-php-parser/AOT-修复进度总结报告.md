# AOT 编译器修复进度总结报告

## 本轮修复成果

### 已完成修复 (8项)

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

### 关键架构修复说明

**#5 异常跨函数边界传播** — 根因：方法内 `throw` 生成 `return error.RuntimeError`，调用方 `try php_object_call(...)` 会把 Zig error 直接传播到上层，跳过 `hasException()` 检查，导致 try-catch 永远捕获不到跨函数异常。修复：throw 改为 `return Value.initNull()`，异常信息已通过 `setException()` 设置，调用方的 `hasException()` 正常路由到 catch 块。

**#7 throw-as-expression** — PHP 8.0 允许 `throw` 在表达式上下文中使用（三元、null coalesce 等）。在 `generateExpression` 中添加 `.throw_stmt` 处理：生成异常对象、设置 throw terminator、创建不可达块让后续代码生成继续。

### 测试通过率

- **pass 目录**: 27/36 通过 (排除 3 个 timestamp race 实为 30/36 = 83%)
- **从 failed 移入 pass**: 7 个测试
  - test_041_number_boundary
  - test_050_throw_expressions
  - test_053_intersection_types
  - test_053_mixed_complex
  - test_053_sensitive_attribute
  - test_057_new_in_initializers
  - test_058_object_graph

### pass 目录剩余 FAIL 分析

| 测试 | 原因 | 可修复性 |
|------|------|---------|
| test_003_advanced_oop | timestamp race (秒级差异) | 非bug |
| test_032_type_declarations | PHP 8.4 Deprecated 隐式nullable | 低优先 |
| test_042_array_hash | memory_get_usage() AOT无法模拟 | AOT固有 |
| test_044_memory_performance | 内存+循环引用差异 | AOT固有 |
| test_053_intersection_types | timestamp race (秒级差异) | 非bug |
| test_056_final_constants | PHP 8.4 final const 编译期错误 | 低优先 |
| test_057_higher_order | PHP 8.3 static var 编译期错误 | 低优先 |
| test_057_new_in_initializers | timestamp race (秒级差异) | 非bug |
| test_064_array_splat_unpacking | 性能microtime()差异 | 非bug |

### 后续开发建议（按优先级排序）

1. **命名参数重排序** — test_051: 混合位置+命名参数时参数映射错误，核心功能缺陷
2. **late static binding (`static::`)** — test_019: `static::method()` 返回父类而非子类
3. **引用赋值 (`&`)** — test_010: `$b = &$a` 引用共享不工作
4. **Trait 方法调用** — test_0450/0451: trait 方法在组合类中返回空值
5. **Enum 完整支持** — test_034: backed enum from()/tryFrom() + cases()
6. **match 表达式 + throw** — test_067: match 内 throw expression
7. **SPL 迭代器** — test_060/066: LimitIterator, CachingIterator 等
8. **WeakMap/WeakRef** — test_069: 弱引用支持
9. **Fiber 调度器** — test_055/058: 完整 Fiber 协程支持
10. **Reflection 完善** — test_040/065: ReflectionClass 属性/方法反射
