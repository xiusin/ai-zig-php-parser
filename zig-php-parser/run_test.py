import subprocess
import os

os.chdir('/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser')

result = subprocess.run(
    ['./zig-out/bin/php-interpreter', '--aot', 'test_mbstring.php'],
    capture_output=True,
    text=True,
    timeout=60
)

with open('/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/aot_test_output.txt', 'w') as f:
    f.write("=== STDOUT ===\n")
    f.write(result.stdout)
    f.write("\n=== STDERR ===\n")
    f.write(result.stderr)

print("Output written to aot_test_output.txt")
print("Return code:", result.returncode)
