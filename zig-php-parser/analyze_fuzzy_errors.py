#!/usr/bin/env python3
import re
import os
from collections import Counter, defaultdict

# 读取测试报告
with open('iflow_scripts/fuzzy_test_report.md', 'r') as f:
    lines = f.readlines()

# 分类统计
categories = {
    'foreach_missing': [],
    'builtin_func_missing': [],
    'oop_not_supported': [],
    'syntax_errors': [],
    'real_bugs': [],
    'passed': []
}

builtin_funcs = Counter()
opcodes = Counter()

for i, line in enumerate(lines[3:], start=4):
    parts = line.split('|')
    if len(parts) < 7:
        continue
    
    test_num = parts[1].strip()
    test_file = parts[2].strip()
    category = parts[3].strip()
    php_result = parts[4].strip()
    interp_result = parts[5].strip()
    aot_result = parts[6].strip()
    status = parts[7].strip() if len(parts) > 7 else ""
    
    # 检查是否通过
    if '[编译错误]' not in aot_result and '[编译失败]' not in aot_result:
        # 可能通过了
        if php_result and interp_result and php_result.split('\n')[0] == interp_result.split('\n')[0]:
            categories['passed'].append((test_num, test_file))
            continue
    
    # PHP 语法错误
    if 'PHP Parse error' in php_result or 'PHP_ERROR' in status:
        categories['syntax_errors'].append((test_num, test_file))
        continue
    
    # foreach 未实现
    if 'InvalidOpcode' in interp_result and '0x7e' in interp_result:
        categories['foreach_missing'].append((test_num, test_file))
        match = re.search(r'opcode=0x[0-9a-f]+\((\w+)', interp_result)
        if match:
            opcodes[match.group(1)] += 1
        continue
    
    # 内置函数未实现
    if 'UndefinedFunc' in interp_result:
        categories['builtin_func_missing'].append((test_num, test_file))
        # 尝试找出是哪个函数
        test_path = f'iflow_scripts/{test_file}'
        if os.path.exists(test_path):
            with open(test_path, 'r') as tf:
                content = tf.read()
                # 查找函数调用
                funcs = re.findall(r'\b([a-z_]+)\s*\(', content)
                for func in funcs:
                    if func not in ['echo', 'if', 'for', 'while', 'foreach', 'function', 'return']:
                        builtin_funcs[func] += 1
        continue
    
    # OOP 相关
    if category == 'OOP' or 'class' in interp_result.lower():
        categories['oop_not_supported'].append((test_num, test_file))
        continue
    
    # 其他真正的 bug
    if 'AOT_COMPILE_ERROR' in status or 'INTERP_ERROR' in status:
        categories['real_bugs'].append((test_num, test_file, interp_result[:100]))

# 输出报告
print("=" * 80)
print("AOT 编译器模糊测试问题分析报告")
print("=" * 80)
print()

print(f"总测试数: {len(lines) - 3}")
print(f"通过: {len(categories['passed'])}")
print(f"失败: {len(lines) - 3 - len(categories['passed'])}")
print()

print("=" * 80)
print("问题分类")
print("=" * 80)
print()

print(f"1. PHP 语法错误（测试生成器问题）: {len(categories['syntax_errors'])}")
print(f"   - 这些是测试生成器生成了无效的 PHP 代码")
print()

print(f"2. foreach 未实现: {len(categories['foreach_missing'])}")
print(f"   - 需要实现 foreach 循环支持")
print(f"   - 涉及的 opcodes: {dict(opcodes)}")
print()

print(f"3. 内置函数未实现: {len(categories['builtin_func_missing'])}")
print(f"   - 需要实现的函数（前20个）:")
for func, count in builtin_funcs.most_common(20):
    print(f"     {func}: {count} 次")
print()

print(f"4. OOP 不支持: {len(categories['oop_not_supported'])}")
print(f"   - 类、对象、方法等面向对象特性")
print()

print(f"5. 真正的 bug: {len(categories['real_bugs'])}")
if categories['real_bugs']:
    print("   前10个:")
    for test_num, test_file, error in categories['real_bugs'][:10]:
        print(f"     Test {test_num} ({test_file}): {error}")
print()

print("=" * 80)
print("优先级建议")
print("=" * 80)
print()
print("P0 (必须修复):")
print("  - foreach 循环支持")
print()
print("P1 (重要):")
print("  - 常用内置函数 (printf, sprintf, array_*, str_*)")
print()
print("P2 (可选):")
print("  - OOP 支持")
print("  - 其他内置函数")
print()
