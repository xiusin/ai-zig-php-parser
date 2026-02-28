import re

with open('fuzzy_test_report.md', 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines[3:], start=4):  # 跳过表头
    parts = line.split('|')
    if len(parts) < 8:
        continue
    
    test_num = parts[1].strip()
    test_file = parts[2].strip()
    php_result = parts[4].strip()
    interp_result = parts[5].strip()
    aot_result = parts[6].strip()
    status = parts[7].strip()
    error_msg = parts[8].strip() if len(parts) > 8 else ""
    
    # 跳过 PHP 语法错误
    if 'PHP_ERROR' in status:
        continue
    
    # 跳过只有 setTerminator 的（调试输出）
    if 'setTerminator' in error_msg and 'Compilation failed' not in error_msg and '.zig' not in error_msg:
        continue
    
    # 找真正的错误
    if 'AOT_COMPILE_ERROR' in status or 'INTERP_ERROR' in status:
        print(f"Test {test_num} ({test_file}):")
        print(f"  PHP: {php_result[:50]}")
        print(f"  Interp: {interp_result[:50]}")
        print(f"  AOT: {aot_result}")
        print(f"  Error: {error_msg[:100]}")
        print()
        
        if i > 50:  # 只看前50个
            break
