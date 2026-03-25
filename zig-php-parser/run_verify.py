#!/usr/bin/env python3
import subprocess
import os

os.chdir('/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser')

output_file = open('/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/verify_result.txt', 'w')

# Test with PHP
output_file.write("=== PHP 原生输出 ===\n")
result = subprocess.run(['php', 'verify_functions.php'], capture_output=True, text=True, timeout=30)
output_file.write(result.stdout)
if result.stderr:
    output_file.write("STDERR: " + result.stderr + "\n")

output_file.write("\n=== AOT 编译输出 ===\n")
# Test with AOT --compile
result = subprocess.run(['./zig-out/bin/php-interpreter', '--compile', 'verify_functions.php'], capture_output=True, text=True, timeout=60)
output_file.write(result.stdout)
if result.stderr:
    output_file.write("STDERR: " + result.stderr + "\n")

output_file.write("\n=== 返回码 ===\n")
php_result = subprocess.run(['php', 'verify_functions.php'], capture_output=True, text=True, timeout=30)
aot_result = subprocess.run(['./zig-out/bin/php-interpreter', '--compile', 'verify_functions.php'], capture_output=True, text=True, timeout=60)
output_file.write("PHP 返回码: " + str(php_result.returncode) + "\n")
output_file.write("AOT 返回码: " + str(aot_result.returncode) + "\n")

output_file.close()
print("结果已写入 verify_result.txt")
