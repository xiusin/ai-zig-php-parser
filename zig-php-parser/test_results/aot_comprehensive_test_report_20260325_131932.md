# AOT 全面测试报告

测试时间: 2026-03-25 13:19:32
测试耗时: 0:00:25.550751
测试文件总数: 246

## 测试统计摘要

| 类别 | 数量 | 百分比 |
|------|------|--------|
| ✅ 通过 | 0 | 0.0% |
| ❌ 输出不匹配 | 0 | 0.0% |
| 🔴 编译失败 | 203 | 82.5% |
| 💥 AOT 执行失败 | 5 | 2.0% |
| ⏱️ AOT 执行超时 | 0 | 0.0% |
| ⚠️ PHP 执行失败 | 38 | 15.4% |
| ⏱️ PHP 执行超时 | 0 | 0.0% |
| 🐛 其他错误 | 0 | 0.0% |

## 🔴 编译失败详细分析

### Other compilation error (198 个)

- `fuzzy_scripts_27/failed/test_009_serialization.php`
  - stderr: `main.zig:4867:14: error: expected ',' after field ime_allocator);              ^ Error: Compilation failed with 2 errors, 0 warnings [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit co...`
- `fuzzy_scripts_27/failed/test_013_regex.php`
  - stderr: `main.zig:4867:14: error: expected ',' after field ime_allocator);              ^ Error: Compilation failed with 2 errors, 0 warnings [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit co...`
- `fuzzy_scripts_27/failed/test_010_filesystem.php`
  - stderr: `main.zig:4867:14: error: expected ',' after field ime_allocator);              ^ Error: Compilation failed with 2 errors, 0 warnings [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit co...`
- `fuzzy_scripts_27/failed/test_008_datetime.php`
  - stderr: `main.zig:4867:14: error: expected ',' after field ime_allocator);              ^ Error: Compilation failed with 2 errors, 0 warnings [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit co...`
- `fuzzy_scripts_27/failed/test_007_enums.php`
  - stderr: `main.zig:4867:14: error: expected ',' after field ime_allocator);              ^ Error: Compilation failed with 2 errors, 1 warnings [1mtest_007_enums.php:88:29[0m: [33mwarning[0m: 未使用的变量: $$e_cat...`
- `fuzzy_scripts_27/failed/test_002_type_juggling.php`
  - stderr: `main.zig:4867:14: error: expected ',' after field ime_allocator);              ^ Error: Compilation failed with 2 errors, 0 warnings [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit co...`
- `fuzzy_scripts_27/failed/test_012_network.php`
  - stderr: `main.zig:4867:14: error: expected ',' after field ime_allocator);              ^ Error: Compilation failed with 2 errors, 0 warnings [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit co...`
- `fuzzy_scripts_27/failed/test_018_named_args.php`
  - stderr: `main.zig:7818:16: error: expected ',' after field ntime_allocator);                ^ Error: Compilation failed with 2 errors, 0 warnings [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exi...`
- `fuzzy_scripts_27/failed/test_019_match.php`
  - stderr: `main.zig:7818:16: error: expected ',' after field ntime_allocator);                ^ Error: Compilation failed with 2 errors, 1 warnings [1mtest_019_match.php:96:37[0m: [33mwarning[0m: 未使用的变量: $$e...`
- `fuzzy_scripts_27/failed/test_021_database.php`
  - stderr: `runtime_lib.zig:10160:76: error: expected ',' after switch prong                             'M' => if (in_time) i = @intFromFloat(num_val) else m = @intFromFloat(num_val),                            ...`
- ... 还有 188 个类似错误

### Syntax/Parsing error (3 个)

- `fuzzy_scripts_27/failed/test_006_exceptions.php`
  - stderr: `main.zig:4867:14: error: expected ',' after field ime_allocator);              ^ Error: Compilation failed with 2 errors, 5 warnings [1mtest_006_exceptions.php:53:26[0m: [33mwarning[0m: 未使用的变量: $$...`
- `fuzzy_scripts_27/failed/test_229_expression_parser.php`
  - stderr: `runtime_lib.zig:10160:76: error: expected ',' after switch prong                             'M' => if (in_time) i = @intFromFloat(num_val) else m = @intFromFloat(num_val),                            ...`
- `fuzzy_scripts_27/failed/test_228_ini_parser.php`
  - stderr: `/opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/start.zig:614:46: error: root source file struct 'main' has no member named 'main'     const ReturnType = @typeInfo(@TypeOf(root.main)).@"fn".return_type.?;...`

### Unknown compilation error (2 个)

- `fuzzy_scripts_27/failed/test_014_spl.php`
  - Compilation error: 'utf-8' codec can't decode byte 0xb8 in position 55: invalid start byte
- `fuzzy_scripts_27/failed/test_142_random.php`
  - Compilation error: 'utf-8' codec can't decode byte 0xb0 in position 63: invalid start byte

## 💥 AOT 执行失败详细分析

### Runtime error (code=0) (4 个)

- `fuzzy_scripts_27/failed/test_028_hooks.php`
- `fuzzy_scripts_27/failed/test_052_const_expr2.php`
- `fuzzy_scripts_27/failed/test_130_spread_method.php`
- `fuzzy_scripts_27/failed/test_147_logical_ops.php`

### Runtime error: PHP Parse error:  syntax error, unexpected "(", expecting "{" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_028_hooks.php on line 10
 (1 个)

- `fuzzy_scripts_27/failed/test_027_constants.php`
  - stderr: `PHP Parse error:  syntax error, unexpected "(", expecting "{" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_028_hooks.php on line 10 ...`

## 建议与后续行动

1. **优先修复编译问题**: 最普遍的编译错误类型是 'Other compilation error'
2. **运行时稳定性**: AOT 执行失败主要集中在段错误和断言失败，需要加强运行时检查
4. **测试覆盖率**: 建议增加边界条件和异常处理测试用例