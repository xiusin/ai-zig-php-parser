import re
from collections import Counter

errors = Counter()
interp_errors = Counter()

with open('fuzzy_test_report.md', 'r') as f:
    for line in f:
        if 'AOT_COMPILE_ERROR' in line:
            # 这些实际上不是错误，只是调试输出
            if 'setTerminator' in line and 'Compilation failed' not in line:
                errors['DEBUG_OUTPUT'] += 1
            elif 'Compilation failed' in line:
                errors['REAL_COMPILE_ERROR'] += 1
            else:
                errors['UNKNOWN_AOT_ERROR'] += 1
        elif 'INTERP_ERROR' in line:
            if 'InvalidOpcode' in line:
                match = re.search(r'opcode=0x[0-9a-f]+\((\w+)', line)
                if match:
                    interp_errors[f'InvalidOpcode:{match.group(1)}'] += 1
                else:
                    interp_errors['InvalidOpcode:unknown'] += 1
            else:
                interp_errors['OTHER'] += 1
        elif 'PHP_ERROR' in line:
            errors['PHP_SYNTAX_ERROR'] += 1

print("=== 错误分类 ===\n")
print("AOT 编译器错误:")
for err, count in errors.most_common():
    print(f"  {err}: {count}")

print("\n解释器错误:")
for err, count in interp_errors.most_common():
    print(f"  {err}: {count}")
