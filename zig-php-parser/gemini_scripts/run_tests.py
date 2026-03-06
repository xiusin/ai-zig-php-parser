import glob
import subprocess
import os
import sys
import shutil

# Config
PHP_CMD = "php"
AOT_CMD = "./zig-out/bin/php-interpreter"
SCRIPTS_DIR = "gemini_scripts"
BIN_DIR = os.path.join(SCRIPTS_DIR, "bin")

if not os.path.exists(BIN_DIR):
    os.makedirs(BIN_DIR)

files = sorted(glob.glob(os.path.join(SCRIPTS_DIR, "*.php")))
results = []
memory_leaks = []

print(f"Found {len(files)} scripts. Starting execution...")

for i, f in enumerate(files):
    if i % 50 == 0:
        print(f"Processing {i}/{len(files)}...")
        
    base_name = os.path.basename(f).replace(".php", "")
    bin_path = os.path.join(BIN_DIR, base_name)
    
    # 1. Run PHP
    try:
        php_proc = subprocess.run([PHP_CMD, f], capture_output=True, text=True, timeout=3)
        php_out = php_proc.stdout
        php_err = php_proc.stderr
    except subprocess.TimeoutExpired:
        print(f"Skipping {f}: PHP timeout")
        continue
    except Exception as e:
        print(f"Skipping {f}: PHP error {e}")
        continue

    # 2. Compile AOT
    try:
        cmd = [AOT_CMD, "--compile", "--output=" + bin_path, f]
        compile_proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        
        if compile_proc.returncode != 0:
            # Handle failure
            err_msg = compile_proc.stderr[:100].replace("\n", "\\n")
            results.append({
                "script": f,
                "php_out": php_out[:100].replace("\n", "\\n"),
                "aot_out": f"Compilation Failed: {err_msg}"
            })
            continue
            
    except Exception as e:
        results.append({
            "script": f,
            "php_out": php_out[:100].replace("\n", "\\n"),
            "aot_out": f"Compilation Exception: {str(e)}"
        })
        continue

    # 3. Run AOT Binary
    try:
        aot_proc = subprocess.run([bin_path], capture_output=True, text=True, timeout=3)
        aot_out = aot_proc.stdout
        aot_err = aot_proc.stderr
        
        if "leak" in aot_err.lower() or "GeneralPurposeAllocator" in aot_err:
             memory_leaks.append(f"Leak in {os.path.basename(f)}: {aot_err[:200].replace('\n', ' ')}")

        # Compare
        if php_out != aot_out:
            aot_err_msg = aot_err[:50].replace("\n", " ") if aot_err else ""
            results.append({
                "script": f,
                "php_out": php_out[:200].replace("\n", "\\n"),
                "aot_out": aot_out[:200].replace("\n", "\\n") + (f" [Stderr: {aot_err_msg}]" if aot_err else "")
            })
        else:
            os.remove(f)
            
    except subprocess.TimeoutExpired:
         results.append({
            "script": f,
            "php_out": php_out[:100].replace("\n", "\\n"),
            "aot_out": "AOT Timeout"
        })
    except Exception as e:
         results.append({
            "script": f,
            "php_out": php_out[:100].replace("\n", "\\n"),
            "aot_out": f"AOT Execution Error: {str(e)}"
        })
    finally:
        if os.path.exists(bin_path):
            try:
                os.remove(bin_path)
            except:
                pass

# Report
print("\n# Test Results\n")
if results:
    print("| Script Content (Snippet) | PHP Result | AOT Result/Error |")
    print("|---|---|---|")
    for r in results:
        content = "File deleted or unreadable"
        try:
            if os.path.exists(r['script']):
                with open(r['script'], 'r') as f:
                    content = f.read(50).replace("\n", " ") + "..."
            else:
                content = r['script']
        except:
            pass
            
        print(f"| {content} | {r['php_out']} | {r['aot_out']} |")
else:
    print("All tests passed!")

print("\n# Memory Leak Report\n")
if memory_leaks:
    print(f"Total Leaks Detected: {len(memory_leaks)}")
    for m in memory_leaks[:50]:
        print(f"- {m}")
    if len(memory_leaks) > 50:
        print(f"... and {len(memory_leaks) - 50} more.")
else:
    print("No obvious memory leaks detected in stderr.")

try:
    shutil.rmtree(BIN_DIR)
except:
    pass
