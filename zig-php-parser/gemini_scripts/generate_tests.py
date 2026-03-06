import random
import os

NUM_TESTS = 1050
OUTPUT_DIR = "gemini_scripts"

def get_var():
    return f"$v{random.randint(0, 5)}"

def get_val():
    if random.random() < 0.2:
        return str(random.randint(-100, 100))
    elif random.random() < 0.4:
        return f"'{random.choice(['foo', 'bar', 'baz', 'qux'])}'"
    elif random.random() < 0.6:
        return get_var()
    elif random.random() < 0.8:
        return random.choice(["true", "false", "null"])
    else:
        return f"[{random.randint(0, 10)}, {random.randint(0, 10)}]"

def gen_expr(depth=0):
    if depth > 2:
        return get_val()
    
    op = random.choice(['+', '-', '*', '.', '===', '!==', '<', '>', '<=', '>='])
    # For dot operator (concatenation), ensure we don't just generate random nonsense that crashes PHP fatally if strict
    return f"({gen_expr(depth+1)} {op} {gen_expr(depth+1)})"

def gen_assign():
    return f"{get_var()} = {gen_expr()};"

def gen_block(depth):
    stmts = []
    # Avoid too deep recursion
    limit = 2 if depth > 3 else 4
    for _ in range(random.randint(1, limit)):
        r = random.random()
        if r < 0.4: 
            stmts.append(gen_assign())
        elif r < 0.5: 
            stmts.append(f"echo {get_var()} . \"\\n\";")
        elif r < 0.7: 
            stmts.append(gen_if(depth))
        elif r < 0.8: 
            stmts.append(gen_while(depth))
        elif r < 0.9: 
            stmts.append(gen_foreach(depth))
        else: 
            stmts.append(gen_try_catch(depth))
    return "\n".join(stmts)

def gen_if(depth):
    if depth > 3: return gen_assign()
    return f"""
    if ({gen_expr()}) {{
        {gen_block(depth+1)}
    }} else {{
        {gen_block(depth+1)}
    }}
    """

def gen_while(depth):
    if depth > 3: return gen_assign()
    counter_var = f"$cnt{depth}"
    return f"""
    {counter_var} = 0;
    while ({counter_var} < 5 && ({gen_expr()})) {{
        {gen_block(depth+1)}
        {counter_var}++;
    }}
    """

def gen_foreach(depth):
    if depth > 3: return gen_assign()
    return f"""
    $arr{depth} = [{random.randint(1,5)}, {random.randint(6,10)}, {random.randint(11,15)}];
    foreach ($arr{depth} as $k => $v) {{
        echo "$k:$v\\n";
        {gen_block(depth+1)}
    }}
    """

def gen_try_catch(depth):
    if depth > 3: return gen_assign()
    return f"""
    try {{
        if ({random.choice(['true', 'false'])}) {{
            throw new Exception("random error");
        }}
        {gen_block(depth+1)}
    }} catch (Exception $e) {{
        echo "Caught: " . $e->getMessage() . "\\n";
    }} finally {{
        echo "Finally\\n";
    }}
    """

def gen_function_def(idx):
    return f"""
    function func_{idx}($a, $b) {{
        if ($a > $b) return $a;
        return $b;
    }}
    """

def gen_class_def(idx):
    return f"""
    class Class_{idx} {{
        public $prop = {idx};
        public function method($x) {{
            return $this->prop + $x;
        }}
        public function __toString() {{
            return "Class_{idx}:" . $this->prop;
        }}
    }}
    """

def generate_script(index):
    content = ["<?php"]
    
    # Init vars
    for i in range(6):
        content.append(f"$v{i} = {i};")

    if random.random() < 0.3:
        content.append(gen_function_def(index))
        content.append(f"echo func_{index}($v0, $v1) . \"\\n\";")
    
    if random.random() < 0.3:
        content.append(gen_class_def(index))
        content.append(f"$obj = new Class_{index}();")
        content.append(f"echo $obj->method(5) . \"\\n\";")
        content.append(f"echo $obj . \"\\n\";")

    content.append(gen_block(0))
    
    content.append("echo 'Done' . \"\\n\";")
    
    return "\n".join(content)

if __name__ == "__main__":
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
        
    for i in range(NUM_TESTS):
        filename = os.path.join(OUTPUT_DIR, f"test_{i:04d}.php")
        with open(filename, "w") as f:
            f.write(generate_script(i))
    
    print(f"Generated {NUM_TESTS} test scripts in {OUTPUT_DIR}")
