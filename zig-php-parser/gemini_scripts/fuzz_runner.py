import os
import sys
import subprocess
import random
import string
import shutil
import time

# Configuration
# Suppress PHP errors to match likely AOT behavior and avoid noise
PHP_CMD = ["php", "-d", "error_reporting=0", "-d", "display_errors=0"]
AOT_COMPILER = "./zig-out/bin/php-interpreter"
OUTPUT_DIR = "gemini_scripts/temp_tests"
NUM_TESTS = 300
TIMEOUT_EXEC = 3
TIMEOUT_COMPILE = 5

# Ensure output directory exists
if os.path.exists(OUTPUT_DIR):
    shutil.rmtree(OUTPUT_DIR)
os.makedirs(OUTPUT_DIR)

def generate_random_string(length=5):
    return '"' + ''.join(random.choices(string.ascii_letters + string.digits, k=length)) + '"'

def generate_expression(depth=0):
    if depth > 3:
        return str(random.randint(-100, 100))
    
    ops = ['+', '-', '*', '.', '&', '|', '^', '%']
    choice = random.random()
    if choice < 0.3:
        return str(random.randint(-100, 100))
    elif choice < 0.5:
        return generate_random_string()
    elif choice < 0.6:
        # Boolean
        return random.choice(['true', 'false', 'null'])
    elif choice < 0.7:
        # Array
        return f"[{generate_expression(depth+1)}, {generate_expression(depth+1)}]"
    else:
        op = random.choice(ops)
        return f"({generate_expression(depth+1)} {op} {generate_expression(depth+1)})"

def generate_statement(depth=0):
    if depth > 3:
        return f"echo {generate_expression()} . \"\\n\";"
    
    choice = random.random()
    if choice < 0.3:
        # Assignment
        var = f"$v{random.randint(0, 5)}"
        return f"{var} = {generate_expression(depth)};"
    elif choice < 0.5:
        # Echo
        return f"echo {generate_expression(depth)} . \"\\n\";"
    elif choice < 0.6:
        # If
        return f"if ({generate_expression(depth)}) {{ {generate_statement(depth+1)} }} else {{ {generate_statement(depth+1)} }}"
    elif choice < 0.7:
        # While (bounded to avoid infinite loops)
        var = f"$i{depth}"
        return f"{var} = 0; while ({var} < 5) {{ {var}++; {generate_statement(depth+1)} }}"
    elif choice < 0.8:
        # For
        var = f"$j{depth}"
        return f"for ({var} = 0; {var} < 5; {var}++) {{ {generate_statement(depth+1)} }}"
    elif choice < 0.85:
        # Ternary
        return f"echo ({generate_expression(depth)} ? {generate_expression(depth)} : {generate_expression(depth)}) . \"\\n\";"
    elif choice < 0.9:
        # Try-Catch
        return f"try {{ {generate_statement(depth+1)} }} catch (Exception $e) {{ echo 'Caught'; }}"
    elif choice < 0.95:
         # Function call (simple) - definitions are handled in main body
        func_name = f"f{random.randint(0, 2)}" # Use fewer functions to ensure they exist
        return f"echo {func_name}({generate_expression(depth)}) . \"\\n\";"
    else:
        # Switch (simple)
        return f"switch ({generate_expression(depth)}) {{ case 0: echo '0'; break; default: echo 'D'; }}"

def generate_php_script(seed):
    random.seed(seed)
    headers = ["<?php"]
    
    # Pre-define some functions
    functions = [
        "function f0($a) { return $a; }",
        "function f1($a) { return is_numeric($a) ? $a + 1 : $a . 'x'; }",
        "function f2($a) { return $a; }",
    ]
    
    body = []
    
    for _ in range(random.randint(5, 15)):
        body.append(generate_statement())
        
    # Add a class sometimes
    if random.random() < 0.5:
        class_code = """
        class TestClass {
            public $p = 1;
            function __construct($v) { $this->p = $v; }
            function get() { return $this->p; }
            function __toString() { return "TestClass:" . $this->p; }
        }
        $obj = new TestClass(10);
        echo $obj->get() . "\\n";
        echo $obj . "\\n";
        """
        body.append(class_code)

    wrapped_body = "try {\n" + "\n".join(body) + "\n} catch (Throwable $t) { echo \"caught\\n\"; }"
    
    return "\n".join(headers + functions + [wrapped_body])

print(f"| ID | Script Content (Snippet) | PHP Result | AOT Result/Error |")
print(f"|---|---|---|---|")

for i in range(NUM_TESTS):
    script_content = generate_php_script(i)
    script_name = f"test_{i}"
    script_path = os.path.join(OUTPUT_DIR, f"{script_name}.php")
    
    with open(script_path, "w") as f:
        f.write(script_content)
        
    # Run PHP
    try:
        # Use subprocess list args properly
        cmd = PHP_CMD + [script_path]
        php_proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            errors='replace',
            timeout=TIMEOUT_EXEC
        )
        php_out = php_proc.stdout
        php_err = php_proc.stderr
        php_exit = php_proc.returncode
    except subprocess.TimeoutExpired:
        php_out = "TIMEOUT"
        php_err = "TIMEOUT"
        php_exit = -1
    except Exception as e:
        php_out = ""
        php_err = str(e)
        php_exit = -1

    # Compile AOT
    binary_name = os.path.join(OUTPUT_DIR, f"{script_name}")
    compile_cmd = [
        AOT_COMPILER,
        "--compile",
        f"--output={binary_name}",
        script_path
    ]
    
    try:
        compile_proc = subprocess.run(
            compile_cmd,
            capture_output=True,
            text=True,
            errors='replace',
            timeout=TIMEOUT_COMPILE
        )
        compile_out = compile_proc.stdout
        compile_err = compile_proc.stderr
        compile_exit = compile_proc.returncode
    except subprocess.TimeoutExpired:
        compile_exit = -1
        compile_err = "Compilation Timeout"

    aot_out = ""
    aot_err = ""
    aot_exit = 0
    leak_info = ""

    if compile_exit == 0 and os.path.exists(binary_name):
        # Run AOT Binary
        try:
            aot_proc = subprocess.run(
                [binary_name],
                capture_output=True,
                text=True,
                errors='replace',
                timeout=TIMEOUT_EXEC
            )
            aot_out = aot_proc.stdout
            aot_err = aot_proc.stderr
            aot_exit = aot_proc.returncode
            
            if "Leak" in aot_err or "leak" in aot_err:
                 leak_info = " [LEAK DETECTED]"
            
        except subprocess.TimeoutExpired:
            aot_out = "TIMEOUT"
            aot_err = "TIMEOUT"
            aot_exit = -1
    else:
        aot_out = "COMPILATION_FAILED"
        aot_err = compile_err

    php_out_clean = php_out.strip()
    aot_out_clean = aot_out.strip()
    
    match = (php_out_clean == aot_out_clean) and (php_exit == aot_exit)
    
    if php_exit == 0:
        if not match or leak_info:
            snippet = script_content.replace("\n", " ")[:50] + "..."
            php_res = f"Exit: {php_exit}, Out: {php_out_clean[:50]}"
            aot_res = f"Exit: {aot_exit}, Out: {aot_out_clean[:50]}, Err: {aot_err[:100]}{leak_info}"
            print(f"| {i} | `{snippet}` | `{php_res}` | `{aot_res}` |")
        else:
            if os.path.exists(script_path):
                os.remove(script_path)
    
    if os.path.exists(binary_name):
        os.remove(binary_name)
    if os.path.exists(binary_name + ".o"):
        os.remove(binary_name + ".o")

if os.path.exists(OUTPUT_DIR) and not os.listdir(OUTPUT_DIR):
    os.rmdir(OUTPUT_DIR)
