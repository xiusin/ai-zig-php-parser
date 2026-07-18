#!/usr/bin/env python3
import sys, re, subprocess, os

def normalize(s):
    lines = s.split("\n")
    filtered = []
    for line in lines:
        if re.match(r"^#\d+", line):
            continue
        if "thrown in" in line:
            continue
        line = re.sub(r"^PHP (Fatal error|Parse error|Warning|Notice|Deprecated)", r"\1", line)
        line = re.sub(r"  +", " ", line)
        line = re.sub(r"\s*in [^\s]+\.php:\d+", "", line)
        line = re.sub(r"\s*in [^\s]+\.php on line \d+", "", line)
        def truncate_float(m):
            s = m.group(1)
            dot_idx = s.index(".")
            return s[:dot_idx + 13]
        line = re.sub(r"(\d+\.\d{13,})", truncate_float, line)
        filtered.append(line)
    while filtered and filtered[-1] == "":
        filtered.pop()
    return "\n".join(filtered)

script = sys.argv[1]
php_file = f"fuzzy_scripts_73/{script}.php"
output_bin = f"fuzzy_scripts_73/{script}"
interpreter = "zig-out/bin/php-interpreter"

r = subprocess.run([interpreter, "--compile", "--no-debug-info", php_file],
                   capture_output=True, text=True, timeout=60)
if r.returncode != 0:
    print(f"COMPILE_FAIL")
    print(r.stderr[-500:] if r.stderr else r.stdout[-500:])
    sys.exit(1)

try:
    r_aot = subprocess.run([output_bin], capture_output=True, text=True, timeout=10)
    aot_out = r_aot.stdout + r_aot.stderr
    aot_rc = r_aot.returncode
except subprocess.TimeoutExpired:
    print("TIMEOUT")
    os.unlink(output_bin)
    sys.exit(0)

r_php = subprocess.run(["php", php_file], capture_output=True, text=True, timeout=10)
php_out = r_php.stdout + r_php.stderr

os.unlink(output_bin)

if aot_rc == 124:
    print("TIMEOUT")
elif aot_rc in (139, 134):
    print(f"SIGSEGV (rc={aot_rc})")
    print("--- AOT output ---")
    for line in aot_out.split("\n")[:20]:
        print(f"  {line}")
else:
    norm_aot = normalize(aot_out)
    norm_php = normalize(php_out)
    if norm_aot == norm_php:
        print("PASS")
    else:
        print(f"RUNTIME_DIFF (rc={aot_rc})")
        aot_lines = norm_aot.split("\n")
        php_lines = norm_php.split("\n")
        max_len = max(len(aot_lines), len(php_lines))
        shown = 0
        for i in range(max_len):
            a = aot_lines[i] if i < len(aot_lines) else "<missing>"
            p = php_lines[i] if i < len(php_lines) else "<missing>"
            if a != p:
                print(f"  Line {i+1}:")
                print(f"    AOT: {a}")
                print(f"    PHP: {p}")
                shown += 1
                if shown >= 10:
                    print("  ... (more differences)")
                    break
