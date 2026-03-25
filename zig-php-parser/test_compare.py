#!/usr/bin/env python3
"""比较 PHP 和 AOT 输出"""
import subprocess
import os
import tempfile

os.chdir('/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser')

php_file = 'verify_functions.php'
interpreter = './zig-out/bin/php-interpreter'

# 创建临时目录
tmp_dir = tempfile.mkdtemp()
bin_path = os.path.join(tmp_dir, 'aot_bin')
php_out = os.path.join(tmp_dir, 'php.out')
aot_out = os.path.join(tmp_dir, 'aot.out')

print(f"[RUN] {php_file}")

# 1. AOT 编译
print("  编译中...")
result = subprocess.run(
    [interpreter, '--compile', '--output=' + bin_path, php_file],
    capture_output=True, text=True, timeout=60
)
if result.returncode != 0:
    print(f"  -> COMPILE_FAIL (code={result.returncode})")
    print("STDERR:", result.stderr)
    exit(1)

# 2. PHP 执行
print("  PHP 执行中...")
result = subprocess.run(['php', php_file], capture_output=True, text=True, timeout=30)
if result.returncode != 0:
    print(f"  -> PHP_FAIL (code={result.returncode})")
    print("STDERR:", result.stderr)
    exit(1)
php_output = result.stdout
with open(php_out, 'w') as f:
    f.write(php_output)

# 3. AOT 执行
print("  AOT 执行中...")
result = subprocess.run([bin_path], capture_output=True, text=True, timeout=30)
if result.returncode != 0:
    print(f"  -> AOT_FAIL (code={result.returncode})")
    print("STDERR:", result.stderr)
    exit(1)
aot_output = result.stdout
with open(aot_out, 'w') as f:
    f.write(aot_output)

# 4. 比较
if php_output == aot_output:
    print("  -> PASS")
else:
    print("  -> MISMATCH")
    print("\n--- PHP output ---")
    print(php_output)
    print("\n--- AOT output ---")
    print(aot_output)

# 清理
import shutil
shutil.rmtree(tmp_dir)
