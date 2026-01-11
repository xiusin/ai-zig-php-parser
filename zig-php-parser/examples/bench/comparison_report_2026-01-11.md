# Zig-PHP 与原生 PHP 性能对比报告

**生成时间**: 2026-01-11 09:29:22

## 测试环境

- Zig-PHP 解释器: ./zig-out/bin/php-interpreter
- PHP 版本: 8.5.0
- 迭代次数: 100,000
- 单函数最大测试时间: 10秒

## 性能对比 (OPS/s)

| 函数 | Zig-PHP | PHP 原生 | 性能比 |
|------|---------|----------|--------|
| strtr | 102,203 | 23,369,200 | 0.00x |
| http_build_query | 6,428 | 5,490,861 | 0.00x |
| get_loaded_extensions | 9,858 | 683,135 | 0.01x |
| extension_loaded | 22,786 | 18,429,696 | 0.00x |

## 执行时间对比 (秒)

| 函数 | Zig-PHP | PHP 原生 | 差异 |
|------|---------|----------|------|
| strtr | 0.9784 | 0.0043 | +0.9742 |
| http_build_query | 15.5572 | 0.0182 | +15.5390 |
| get_loaded_extensions | 10.1437 | 0.1464 | +9.9973 |
| extension_loaded | 4.3886 | 0.0271 | +4.3615 |

## 内存使用对比

| 函数 | Zig-PHP | PHP 原生 | 差异 |
|------|---------|----------|------|
| strtr | N/A | +86.12 MB | -86.12 MB |
| http_build_query | N/A | +86.12 MB | -86.12 MB |
| get_loaded_extensions | N/A | +86.12 MB | -86.12 MB |
| extension_loaded | N/A | +86.12 MB | -86.12 MB |

## 内存泄漏检测

⚠️ **警告**: 检测到 1800072 处可能的内存泄漏

| 函数 | 泄漏地址数 | 严重程度 |
|------|-----------|----------|
| func_num_args | 12 | 中等 |
| func_get_arg | 12 | 中等 |
| func_get_args | 12 | 中等 |
| strtr | 0 | 轻微 |
| http_build_query | 12 | 中等 |
| get_loaded_extensions | 1800012 | 严重 |
| extension_loaded | 12 | 中等 |

**建议**: 需要修复内存管理代码，确保所有分配的内存被正确释放。

## 分析结论

- 总体性能比: 0.00x (Zig-PHP / PHP)
- ⚠️ Zig-PHP 性能低于原生 PHP，建议优化
