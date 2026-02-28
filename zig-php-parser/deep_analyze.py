#!/usr/bin/env python3
import re
import os
from collections import Counter

# 读取测试报告
with open('iflow_scripts/fuzzy_test_report.md', 'r') as f:
    lines = f.readlines()

# 统计错误类型
error_types = Counter()
compile_errors = []

for i, line in enumerate(lines[3:], start=4):
    parts = line.split('|')
    if len(parts) < 7:
        continue
    
    test_num = parts[1].strip()
    test_file = parts[2].strip()
    interp_result = parts[5].strip()
    aot_result = parts[6].strip()
    status = parts[7].strip() if len(parts) > 7 else ""
    error_msg = parts[8].strip() if len(parts) > 8 else ""
    
    # 跳过 PHP 语法错误
    if 'PHP Parse error' in parts[4]:
        continue
    
    # 分析 AOT 编译错误
    if 'AOT_COMPILE_ERROR' in status:
        # 检查是否是真正的编译错误
        if 'Compilation failed' in error_msg and '.zig' in error_msg:
            error_types['zig_compile_error'] += 1
            compile_errors.append((test_num, test_file, error_msg[:200]))
        elif 'setTerminator' in error_msg and 'Compilation failed' not in error_msg:
            # 只是调试输出，实际可能成功了
            error_types['debug_output_only'] += 1
        else:
            error_types['unknown_aot_error'] += 1
    
    # 分析解释器错误
    if 'Bytecode execution failed' in interp_result:
        if 'StackUnderflow' in interp_result:
            error_types['stack_underflow'] += 1
        elif 'UndefinedFunc' in interp_result:
            error_types['undefined_func'] += 1
        elif 'TypeMismatch' in interp_result:
            error_types['type_mismatch'] += 1
        else:
            error_types['other_bytecode_error'] += 1
    
    if 'InvalidOpcode' in interp_result:
        match = re.search(r'opcode=0x([0-9a-f]+)', interp_result)
        if match:
            opcode = match.group(1)
            error_types[f'invalid_opcode_0x{opcode}'] += 1

print("=" * 80)
print("详细错误分析")
print("=" * 80)
print()

print("错误类型统计:")
for err_type, count in error_types.most_common():
    print(f"  {err_type}: {count}")
print()

if compile_errors:
    print("=" * 80)
    print("Zig 编译错误（前10个）:")
    print("=" * 80)
    for test_num, test_file, error in compile_errors[:10]:
        print(f"\nTest {test_num} ({test_file}):")
        print(f"  {error}")
