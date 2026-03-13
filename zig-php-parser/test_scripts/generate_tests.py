#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PHP AOT 模糊测试脚本生成器
生成1000+条随机复杂的PHP测试脚本，覆盖各种特性
"""

import os
import random
import hashlib
import string

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT_COUNT = 0

# 测试脚本编号
def next_id():
    global SCRIPT_COUNT
    SCRIPT_COUNT += 1
    return SCRIPT_COUNT

def write_script(name, content):
    """写入测试脚本"""
    path = os.path.join(BASE_DIR, name)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    return path

# ==================== 基础类型和运算测试 ====================

def gen_type_basic():
    """基础类型测试"""
    tests = []
    
    # 整数运算
    ops = ['+', '-', '*', '/', '%', '**', '<=>', '<<', '>>', '&', '|', '^']
    for i in range(50):
        a, b = random.randint(-1000, 1000), random.randint(1, 1000)
        op = random.choice(ops)
        tests.append(f"""<?php
// 整数运算测试 {i}
$a = {a};
$b = {b};
echo $a {op} $b;
echo "\n";
?>""")
    
    # 浮点运算
    for i in range(30):
        a = random.uniform(-100.5, 100.5)
        b = random.uniform(0.1, 50.5)
        op = random.choice(['+', '-', '*', '/'])
        tests.append(f"""<?php
// 浮点运算测试 {i}
$a = {a:.6f};
$b = {b:.6f};
echo round($a {op} $b, 4);
echo "\n";
?>""")
    
    # 字符串基础
    strings = ['"hello"', "'world'", '"测试中文"', '"\\n\t"', '"\\x41\\x42"', '"$var"']
    for i in range(30):
        s1 = random.choice(strings)
        s2 = random.choice(strings)
        tests.append(f"""<?php
// 字符串测试 {i}
$a = {s1};
$b = {s2};
echo strlen($a . $b);
echo "\n";
?>""")
    
    # 布尔运算
    for i in range(20):
        a = random.choice(['true', 'false', '1', '0', '""', '"0"', '[]', '[1]'])
        b = random.choice(['true', 'false', '1', '0', '""', '"0"', '[]', '[1]'])
        op = random.choice(['&&', '||', 'and', 'or', 'xor'])
        tests.append(f"""<?php
// 布尔运算测试 {i}
$a = {a};
$b = {b};
echo (int)($a {op} $b);
echo "\n";
?>""")
    
    # NULL测试
    for i in range(20):
        tests.append(f"""<?php
// NULL测试 {i}
$a = null;
$b = {random.choice([0, 'null', '""', 'false', '[]'])};
echo (int)($a === $b);
echo "\n";
?>""")
    
    # 类型转换
    types = ['int', 'float', 'bool', 'string', 'array', 'object']
    for i in range(50):
        val = random.choice([random.randint(-100, 100), random.uniform(-10, 10), 
                           random.choice(['true', 'false']), 
                           '"' + ''.join(random.choices(string.ascii_letters, k=random.randint(1,10))) + '"'])
        t = random.choice(types[:4])  # 只用基础类型
        tests.append(f"""<?php
// 类型转换测试 {i}
$val = {val};
echo var_export(({t})$val, true);
echo "\n";
?>""")
    
    return tests

def gen_control_flow():
    """控制流测试"""
    tests = []
    
    # if-else
    for i in range(30):
        conditions = [
            f"$x > {random.randint(0, 50)}",
            f"$x < {random.randint(50, 100)}",
            f"$x == {random.randint(0, 100)}",
            f"$x != {random.randint(0, 100)}",
            f"$x >= {random.randint(0, 50)}",
            f"$x <= {random.randint(50, 100)}",
        ]
        cond = random.choice(conditions)
        tests.append(f"""<?php
// if-else测试 {i}
$x = {random.randint(0, 100)};
if ({cond}) {{
    echo "A";
}} elseif ($x > 50) {{
    echo "B";
}} else {{
    echo "C";
}}
echo "\n";
?>""")
    
    # 三元运算符
    for i in range(20):
        a, b = random.randint(0, 100), random.randint(0, 100)
        tests.append(f"""<?php
// 三元运算符测试 {i}
$a = {a};
$b = {b};
echo $a > $b ? "A大" : ($a < $b ? "B大" : "相等");
echo "\n";
?>""")
    
    # switch-case
    for i in range(20):
        val = random.randint(1, 5)
        tests.append(f"""<?php
// switch测试 {i}
$x = {val};
switch ($x) {{
    case 1: echo "一"; break;
    case 2: echo "二"; break;
    case 3: echo "三"; break;
    case 4: echo "四"; break;
    default: echo "其他"; break;
}}
echo "\n";
?>""")
    
    # for循环
    for i in range(20):
        start = random.randint(0, 5)
        end = start + random.randint(3, 10)
        step = random.randint(1, 3)
        tests.append(f"""<?php
// for循环测试 {i}
$sum = 0;
for ($i = {start}; $i < {end}; $i += {step}) {{
    $sum += $i;
}}
echo $sum;
echo "\n";
?>""")
    
    # while循环
    for i in range(15):
        start = random.randint(0, 10)
        limit = start + random.randint(3, 8)
        tests.append(f"""<?php
// while循环测试 {i}
$i = {start};
$count = 0;
while ($i < {limit}) {{
    $count++;
    $i++;
}}
echo $count;
echo "\n";
?>""")
    
    # do-while循环
    for i in range(15):
        start = random.randint(0, 5)
        tests.append(f"""<?php
// do-while测试 {i}
$i = {start};
$result = "";
do {{
    $result .= $i;
    $i++;
}} while ($i < {start + random.randint(2, 5)});
echo $result;
echo "\n";
?>""")
    
    # foreach循环
    for i in range(25):
        arr = "[" + ", ".join([str(random.randint(1, 20)) for _ in range(random.randint(3, 6))]) + "]"
        tests.append(f"""<?php
// foreach测试 {i}
$arr = {arr};
$sum = 0;
foreach ($arr as $v) {{
    $sum += $v;
}}
echo $sum;
echo "\n";
?>""")
    
    # break/continue
    for i in range(10):
        tests.append(f"""<?php
// break/continue测试 {i}
$sum = 0;
for ($i = 0; $i < 20; $i++) {{
    if ($i % 2 == 0) continue;
    if ($i > 10) break;
    $sum += $i;
}}
echo $sum;
echo "\n";
?>""")
    
    # 嵌套控制流
    for i in range(10):
        tests.append(f"""<?php
// 嵌套控制流测试 {i}
$result = "";
for ($i = 0; $i < 3; $i++) {{
    for ($j = 0; $j < 3; $j++) {{
        if ($i == $j) continue 2;
        $result .= "$i$j";
    }}
}}
echo $result;
echo "\n";
?>""")
    
    # match表达式 (PHP 8.0+)
    for i in range(10):
        val = random.randint(1, 4)
        tests.append(f"""<?php
// match测试 {i}
$x = {val};
echo match($x) {{
    1 => "一",
    2 => "二",
    3 => "三",
    default => "其他",
}};
echo "\n";
?>""")
    
    return tests

def gen_array_operations():
    """数组操作测试"""
    tests = []
    
    # 数组创建
    for i in range(30):
        arr = "[" + ", ".join([str(random.randint(1, 50)) for _ in range(random.randint(3, 8))]) + "]"
        tests.append(f"""<?php
// 数组创建测试 {i}
$arr = {arr};
echo count($arr);
echo "\n";
?>""")
    
    # 关联数组
    for i in range(20):
        tests.append(f"""<?php
// 关联数组测试 {i}
$arr = [
    "name" => "test{i}",
    "value" => {random.randint(1, 100)},
    "active" => {random.choice(['true', 'false'])}
];
echo $arr["name"] . ":" . $arr["value"];
echo "\n";
?>""")
    
    # 数组访问
    for i in range(20):
        arr = "[" + ", ".join([f'"{c}"' for c in random.choices(string.ascii_lowercase, k=5)]) + "]"
        idx = random.randint(0, 4)
        tests.append(f"""<?php
// 数组访问测试 {i}
$arr = {arr};
echo $arr[{idx}];
echo "\n";
?>""")
    
    # 数组函数
    array_funcs = [
        ('array_push', '$arr = [1, 2]; array_push($arr, 3, 4); echo count($arr);'),
        ('array_pop', '$arr = [1, 2, 3]; echo array_pop($arr);'),
        ('array_shift', '$arr = [1, 2, 3]; echo array_shift($arr);'),
        ('array_unshift', '$arr = [1, 2]; array_unshift($arr, 0); echo $arr[0];'),
        ('array_merge', '$a = [1, 2]; $b = [3, 4]; echo count(array_merge($a, $b));'),
        ('array_slice', '$arr = [1, 2, 3, 4, 5]; echo array_slice($arr, 1, 3)[0];'),
        ('array_reverse', '$arr = [1, 2, 3]; echo array_reverse($arr)[0];'),
        ('in_array', '$arr = [1, 2, 3]; echo in_array(2, $arr) ? "yes" : "no";'),
        ('array_key_exists', '$arr = ["a" => 1]; echo array_key_exists("a", $arr) ? "yes" : "no";'),
        ('array_keys', '$arr = ["a" => 1, "b" => 2]; echo implode(",", array_keys($arr));'),
        ('array_values', '$arr = ["a" => 1, "b" => 2]; echo array_values($arr)[0];'),
        ('array_flip', '$arr = [1 => "a", 2 => "b"]; echo array_flip($arr)["a"];'),
        ('array_unique', '$arr = [1, 1, 2, 2, 3]; echo count(array_unique($arr));'),
        ('array_sum', '$arr = [1, 2, 3, 4]; echo array_sum($arr);'),
        ('array_product', '$arr = [2, 3, 4]; echo array_product($arr);'),
        ('array_map', '$arr = [1, 2, 3]; echo array_map(fn($x) => $x * 2, $arr)[1];'),
        ('array_filter', '$arr = [1, 2, 3, 4]; echo count(array_filter($arr, fn($x) => $x > 2));'),
        ('array_reduce', '$arr = [1, 2, 3]; echo array_reduce($arr, fn($c, $x) => $c + $x, 0);'),
        ('array_search', '$arr = [1, 2, 3]; echo array_search(2, $arr);'),
        ('sort', '$arr = [3, 1, 2]; sort($arr); echo implode(",", $arr);'),
        ('rsort', '$arr = [1, 2, 3]; rsort($arr); echo $arr[0];'),
        ('asort', '$arr = ["b" => 2, "a" => 1]; asort($arr); echo array_key_first($arr);'),
        ('ksort', '$arr = ["b" => 1, "a" => 2]; ksort($arr); echo array_key_first($arr);'),
    ]
    
    for i, (name, code) in enumerate(array_funcs * 3):
        tests.append(f"""<?php
// {name}测试 {i}
{code}
echo "\n";
?>""")
    
    # 多维数组
    for i in range(15):
        tests.append(f"""<?php
// 多维数组测试 {i}
$arr = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];
echo $arr[{random.randint(0, 2)}][{random.randint(0, 2)}];
echo "\n";
?>""")
    
    # 数组解构
    for i in range(10):
        tests.append(f"""<?php
// 数组解构测试 {i}
[$a, $b, $c] = [1, 2, 3];
echo $a + $b + $c;
echo "\n";
?>""")
    
    return tests

def gen_string_operations():
    """字符串操作测试"""
    tests = []
    
    # 字符串连接
    for i in range(20):
        parts = ['"' + ''.join(random.choices(string.ascii_letters, k=random.randint(3,8))) + '"' 
                 for _ in range(random.randint(2, 4))]
        tests.append(f"""<?php
// 字符串连接测试 {i}
$result = {' . '.join(parts)};
echo strlen($result);
echo "\n";
?>""")
    
    # 字符串函数
    string_funcs = [
        ('strlen', 'echo strlen("hello world");'),
        ('strpos', 'echo strpos("hello world", "world");'),
        ('substr', 'echo substr("hello world", 0, 5);'),
        ('str_replace', 'echo str_replace("world", "PHP", "hello world");'),
        ('strtolower', 'echo strtolower("HELLO");'),
        ('strtoupper', 'echo strtoupper("hello");'),
        ('ucfirst', 'echo ucfirst("hello");'),
        ('lcfirst', 'echo lcfirst("Hello");'),
        ('ucwords', 'echo ucwords("hello world");'),
        ('trim', 'echo trim("  hello  ");'),
        ('ltrim', 'echo ltrim("  hello");'),
        ('rtrim', 'echo rtrim("hello  ");'),
        ('str_repeat', 'echo str_repeat("ab", 3);'),
        ('strrev', 'echo strrev("hello");'),
        ('str_shuffle', 'echo strlen(str_shuffle("hello"));'),
        ('str_split', 'echo implode(",", str_split("abc", 1));'),
        ('chunk_split', 'echo strlen(chunk_split("hello", 2, "-"));'),
        ('explode', 'echo count(explode(",", "a,b,c"));'),
        ('implode', 'echo implode("-", [1, 2, 3]);'),
        ('sprintf', 'echo sprintf("%s-%d", "test", 123);'),
        ('printf_capture', 'ob_start(); printf("%d", 123); echo ob_get_clean();'),
        ('number_format', 'echo number_format(1234.567, 2);'),
        ('wordwrap', 'echo strlen(wordwrap("hello world test", 5));'),
        ('chr', 'echo chr(65);'),
        ('ord', 'echo ord("A");'),
        ('bin2hex', 'echo bin2hex("AB");'),
        ('hex2bin', 'echo hex2bin("4142");'),
        ('base64_encode', 'echo base64_encode("hello");'),
        ('base64_decode', 'echo base64_decode(base64_encode("test"));'),
        ('md5', 'echo strlen(md5("test"));'),
        ('sha1', 'echo strlen(sha1("test"));'),
    ]
    
    for i, (name, code) in enumerate(string_funcs * 2):
        tests.append(f"""<?php
// {name}测试 {i}
{code}
echo "\n";
?>""")
    
    # 字符串比较
    for i in range(15):
        a = '"' + ''.join(random.choices(string.ascii_lowercase, k=5)) + '"'
        b = '"' + ''.join(random.choices(string.ascii_lowercase, k=5)) + '"'
        tests.append(f"""<?php
// 字符串比较测试 {i}
$a = {a};
$b = {b};
echo strcmp($a, $b) <=> 0;
echo "\n";
?>""")
    
    # 正则表达式 (preg)
    for i in range(15):
        tests.append(f"""<?php
// 正则测试 {i}
$pattern = '/[0-9]+/';
$subject = "abc123def";
echo preg_match($pattern, $subject) ? "match" : "no match";
echo "\n";
?>""")
    
    return tests

def gen_oop_tests():
    """OOP面向对象测试"""
    tests = []
    
    # 基础类
    for i in range(20):
        tests.append(f"""<?php
// 基础类测试 {i}
class Test{i} {{
    private $value = {random.randint(1, 100)};
    
    public function getValue() {{
        return $this->value;
    }}
    
    public function setValue($v) {{
        $this->value = $v;
    }}
}}
$obj = new Test{i}();
echo $obj->getValue();
$obj->setValue(999);
echo $obj->getValue();
echo "\n";
?>""")
    
    # 构造函数
    for i in range(15):
        tests.append(f"""<?php
// 构造函数测试 {i}
class Person{i} {{
    public $name;
    public $age;
    
    public function __construct($name, $age) {{
        $this->name = $name;
        $this->age = $age;
    }}
    
    public function introduce() {{
        return $this->name . " is " . $this->age;
    }}
}}
$p = new Person{i}("John", {random.randint(20, 50)});
echo $p->introduce();
echo "\n";
?>""")
    
    # 继承
    for i in range(15):
        tests.append(f"""<?php
// 继承测试 {i}
class Animal {{
    public $name;
    public function __construct($name) {{ $this->name = $name; }}
    public function speak() {{ return "sound"; }}
}}
class Cat{i} extends Animal {{
    public function speak() {{ return "meow"; }}
}}
$cat = new Cat{i}("Kitty");
echo $cat->name . ":" . $cat->speak();
echo "\n";
?>""")
    
    # 接口
    for i in range(10):
        tests.append(f"""<?php
// 接口测试 {i}
interface Shape {{
    public function area();
}}
class Rectangle{i} implements Shape {{
    private $w;
    private $h;
    public function __construct($w, $h) {{ $this->w = $w; $this->h = $h; }}
    public function area() {{ return $this->w * $this->h; }}
}}
$rect = new Rectangle{i}({random.randint(2, 10)}, {random.randint(2, 10)});
echo $rect->area();
echo "\n";
?>""")
    
    # 抽象类
    for i in range(10):
        tests.append(f"""<?php
// 抽象类测试 {i}
abstract class Vehicle {{
    abstract public function wheels();
    public function info() {{ return "wheels:" . $this->wheels(); }}
}}
class Car{i} extends Vehicle {{
    public function wheels() {{ return 4; }}
}}
$car = new Car{i}();
echo $car->info();
echo "\n";
?>""")
    
    # Trait
    for i in range(10):
        tests.append(f"""<?php
// Trait测试 {i}
trait Logger {{
    public function log($msg) {{ return "[LOG] " . $msg; }}
}}
class Service{i} {{
    use Logger;
    public function run() {{ return $this->log("running"); }}
}}
$s = new Service{i}();
echo $s->run();
echo "\n";
?>""")
    
    # 静态成员
    for i in range(10):
        tests.append(f"""<?php
// 静态成员测试 {i}
class Counter{i} {{
    private static $count = 0;
    
    public static function increment() {{
        self::$count++;
    }}
    
    public static function get() {{
        return self::$count;
    }}
}}
Counter{i}::increment();
Counter{i}::increment();
echo Counter{i}::get();
echo "\n";
?>""")
    
    # 魔法方法
    magic_methods = [
        ('__toString', '''
class Magic{i} {
    public function __toString() {
        return "magic{i}";
    }
}
$obj = new Magic{i}();
echo (string)$obj;'''),
        ('__get/__set', '''
class Magic{i} {
    private $data = [];
    public function __get($key) { return $this->data[$key] ?? "none"; }
    public function __set($key, $val) { $this->data[$key] = $val; }
}
$obj = new Magic{i}();
$obj->test = "value";
echo $obj->test;'''),
        ('__call', '''
class Magic{i} {
    public function __call($name, $args) {
        return $name . ":" . count($args);
    }
}
$obj = new Magic{i}();
echo $obj->doSomething(1, 2, 3);'''),
        ('__invoke', '''
class Magic{i} {
    public function __invoke($x) {
        return $x * 2;
    }
}
$obj = new Magic{i}();
echo $obj(5);'''),
        ('__clone', '''
class Magic{i} {
    public $count = 0;
    public function __clone() {
        $this->count = 1;
    }
}
$a = new Magic{i}();
$b = clone $a;
echo $b->count;'''),
    ]
    
    for i, (name, code) in enumerate(magic_methods * 2):
        tests.append(f"""<?php
// {name}测试 {i}
{code}
echo "\n";
?>""")
    
    # 命名空间
    for i in range(10):
        tests.append(f"""<?php
// 命名空间测试 {i}
namespace Test\\NS{i};

class Helper {{
    public static function id($x) {{ return $x; }}
}}
echo \\Test\\NS{i}\\Helper::id({random.randint(1, 100)});
echo "\n";
?>""")
    
    # 匿名类
    for i in range(10):
        tests.append(f"""<?php
// 匿名类测试 {i}
$obj = new class {{
    public function get() {{ return {random.randint(1, 100)}; }}
}};
echo $obj->get();
echo "\n";
?>""")
    
    # 常量
    for i in range(10):
        tests.append(f"""<?php
// 类常量测试 {i}
class Config{i} {{
    const VERSION = "1.{i}";
    const MAX_SIZE = {random.randint(100, 1000)};
}}
echo Config{i}::VERSION . ":" . Config{i}::MAX_SIZE;
echo "\n";
?>""")
    
    return tests

def gen_builtin_functions():
    """内置函数测试"""
    tests = []
    
    # 数学函数
    math_funcs = [
        ('abs', 'echo abs(-5);'),
        ('ceil', 'echo ceil(4.3);'),
        ('floor', 'echo floor(4.7);'),
        ('round', 'echo round(4.5);'),
        ('max', 'echo max(1, 5, 3, 2);'),
        ('min', 'echo min(1, 5, 3, 2);'),
        ('sqrt', 'echo sqrt(16);'),
        ('pow', 'echo pow(2, 3);'),
        ('log', 'echo round(log(M_E), 2);'),
        ('log10', 'echo log10(100);'),
        ('exp', 'echo round(exp(1), 2);'),
        ('sin', 'echo round(sin(M_PI/2), 2);'),
        ('cos', 'echo round(cos(0), 2);'),
        ('tan', 'echo round(tan(M_PI/4), 2);'),
        ('asin', 'echo round(asin(1), 2);'),
        ('acos', 'echo round(acos(0), 2);'),
        ('atan', 'echo round(atan(1), 2);'),
        ('deg2rad', 'echo round(deg2rad(180), 2);'),
        ('rad2deg', 'echo round(rad2deg(M_PI), 2);'),
        ('pi', 'echo round(pi(), 2);'),
        ('fmod', 'echo fmod(5.7, 1.3);'),
        ('hypot', 'echo hypot(3, 4);'),
        ('is_nan', 'echo is_nan(NAN) ? 1 : 0;'),
        ('is_finite', 'echo is_finite(1.0) ? 1 : 0;'),
        ('is_infinite', 'echo is_infinite(log(0)) ? 1 : 0;'),
    ]
    
    for i, (name, code) in enumerate(math_funcs * 2):
        tests.append(f"""<?php
// 数学函数{name}测试 {i}
{code}
echo "\n";
?>""")
    
    # 日期时间函数
    date_funcs = [
        ('time', 'echo time() > 0 ? "ok" : "fail";'),
        ('date_default', 'echo strlen(date("Y-m-d"));'),
        ('strtotime', 'echo strtotime("2024-01-01") > 0 ? "ok" : "fail";'),
        ('checkdate', 'echo checkdate(2, 29, 2024) ? 1 : 0;'),
        ('mktime', 'echo mktime(0,0,0,1,1,2024) > 0 ? 1 : 0;'),
        ('getdate', 'echo getdate()["year"] >= 2024 ? 1 : 0;'),
    ]
    
    for i, (name, code) in enumerate(date_funcs * 3):
        tests.append(f"""<?php
// 日期函数{name}测试 {i}
{code}
echo "\n";
?>""")
    
    # 变量函数
    var_funcs = [
        ('isset', '$a = 1; echo isset($a) ? 1 : 0;'),
        ('empty', '$a = 0; echo empty($a) ? 1 : 0;'),
        ('is_null', '$a = null; echo is_null($a) ? 1 : 0;'),
        ('is_int', 'echo is_int(42) ? 1 : 0;'),
        ('is_float', 'echo is_float(3.14) ? 1 : 0;'),
        ('is_string', 'echo is_string("hello") ? 1 : 0;'),
        ('is_array', 'echo is_array([]) ? 1 : 0;'),
        ('is_object', 'echo is_object(new stdClass) ? 1 : 0;'),
        ('is_bool', 'echo is_bool(true) ? 1 : 0;'),
        ('is_callable', 'echo is_callable("strlen") ? 1 : 0;'),
        ('is_numeric', 'echo is_numeric("123") ? 1 : 0;'),
        ('is_scalar', 'echo is_scalar(1) ? 1 : 0;'),
        ('gettype', 'echo gettype(42);'),
        ('gettype_array', 'echo gettype([]);'),
        ('var_export', 'echo var_export([1,2,3], true);'),
        ('print_r', 'echo strlen(print_r([1], true));'),
        ('serialize', 'echo strlen(serialize([1,2,3]));'),
        ('unserialize', '$a = serialize([1,2]); echo count(unserialize($a));'),
        ('count', 'echo count([1,2,3,4,5]);'),
        ('sizeof', 'echo sizeof([1,2,3]);'),
    ]
    
    for i, (name, code) in enumerate(var_funcs * 2):
        tests.append(f"""<?php
// 变量函数{name}测试 {i}
{code}
echo "\n";
?>""")
    
    # 数组函数补充
    more_array_funcs = [
        ('array_fill', 'echo count(array_fill(0, 5, "x"));'),
        ('array_fill_keys', 'echo count(array_fill_keys(["a","b"], 1));'),
        ('array_combine', 'echo array_combine(["a","b"], [1,2])["a"];'),
        ('array_diff', 'echo count(array_diff([1,2,3], [2,3]));'),
        ('array_diff_key', 'echo count(array_diff_key(["a"=>1,"b"=>2], ["a"=>0]));'),
        ('array_diff_assoc', 'echo count(array_diff_assoc(["a"=>1], ["a"=>2]));'),
        ('array_intersect', 'echo count(array_intersect([1,2,3], [2,3,4]));'),
        ('array_intersect_key', 'echo count(array_intersect_key(["a"=>1], ["a"=>2]));'),
        ('array_column', 'echo array_column([["id"=>1],["id"=>2]], "id")[0];'),
        ('array_chunk', 'echo count(array_chunk([1,2,3,4], 2));'),
        ('array_pad', 'echo count(array_pad([1], 3, 0));'),
        ('array_splice', '$a=[1,2,3,4]; array_splice($a,1,2); echo $a[1];'),
        ('array_rand', 'echo in_array(array_rand([1,2,3]), [0,1,2]) ? 1 : 0;'),
        ('shuffle', '$a=[1,2,3]; shuffle($a); echo count($a);'),
        ('range', 'echo count(range(1, 5));'),
        ('compact', '$a=1;$b=2; echo count(compact("a","b"));'),
        ('extract', '$arr=["x"=>5]; extract($arr); echo $x;'),
    ]
    
    for i, (name, code) in enumerate(more_array_funcs * 2):
        tests.append(f"""<?php
// 数组函数{name}测试 {i}
{code}
echo "\n";
?>""")
    
    # 字符串函数补充
    more_string_funcs = [
        ('str_pad', 'echo strlen(str_pad("x", 5, "-", STR_PAD_BOTH));'),
        ('str_word_count', 'echo str_word_count("hello world");'),
        ('str_contains', 'echo str_contains("hello", "ell") ? 1 : 0;'),
        ('str_starts_with', 'echo str_starts_with("hello", "hel") ? 1 : 0;'),
        ('str_ends_with', 'echo str_ends_with("hello", "llo") ? 1 : 0;'),
        ('strchr', 'echo strchr("hello@world", "@");'),
        ('strstr', 'echo strstr("hello@world", "@");'),
        ('stristr', 'echo stristr("HELLO@world", "@");'),
        ('strrchr', 'echo strrchr("a@b@c", "@");'),
        ('strpbrk', 'echo strpbrk("hello", "oe");'),
        ('strpos_offset', 'echo strpos("hello", "l", 3);'),
        ('strrpos', 'echo strrpos("hello", "l");'),
        ('stripos', 'echo stripos("HELLO", "l");'),
        ('strripos', 'echo strripos("HELLO", "l");'),
        ('substr_count', 'echo substr_count("hello", "l");'),
        ('substr_replace', 'echo substr_replace("hello", "X", 1, 1);'),
        ('str_replace_count', 'echo str_replace("a", "b", "aaa", $c); echo $c;'),
        ('str_rot13', 'echo str_rot13("hello");'),
        ('addslashes', 'echo addslashes("test\'s");'),
        ('stripslashes', 'echo stripslashes("test\\\'s");'),
        ('htmlspecialchars', 'echo strlen(htmlspecialchars("<a>"));'),
        ('htmlentities', 'echo strlen(htmlentities("<>&"));'),
        ('nl2br', 'echo strlen(nl2br("a\nb"));'),
        ('strip_tags', 'echo strip_tags("<p>hello</p>");'),
        ('quotemeta', 'echo quotemeta("a.b*c?");'),
    ]
    
    for i, (name, code) in enumerate(more_string_funcs * 2):
        tests.append(f"""<?php
// 字符串函数{name}测试 {i}
{code}
echo "\n";
?>""")
    
    return tests

def gen_edge_cases():
    """边界条件和异常场景测试"""
    tests = []
    
    # 空值处理
    for i in range(15):
        tests.append(f"""<?php
// 空值处理测试 {i}
$arr = [];
echo count($arr);
echo isset($arr[0]) ? "set" : "notset";
echo empty($arr) ? "empty" : "notempty";
echo "\n";
?>""")
    
    # 类型强制转换边界
    for i in range(15):
        tests.append(f"""<?php
// 类型边界测试 {i}
echo (int)"123abc";
echo (int)"abc123";
echo (float)"3.14abc";
echo (bool)"";
echo (bool)"0";
echo "\n";
?>""")
    
    # 数值溢出
    for i in range(10):
        tests.append(f"""<?php
// 数值溢出测试 {i}
$big = PHP_INT_MAX;
echo $big > 0 ? "positive" : "negative";
echo "\n";
?>""")
    
    # 字符串边界
    for i in range(10):
        tests.append(f"""<?php
// 字符串边界测试 {i}
$s = "";
echo strlen($s);
$s[0] = "a";
echo strlen($s);
echo "\n";
?>""")
    
    # 数组边界
    for i in range(10):
        tests.append(f"""<?php
// 数组边界测试 {i}
$arr = [1 => "a", 3 => "b"];
echo array_key_exists(2, $arr) ? "exists" : "notexists";
echo array_key_exists(3, $arr) ? "exists" : "notexists";
echo "\n";
?>""")
    
    # 递归引用
    for i in range(5):
        tests.append(f"""<?php
// 递归引用测试 {i}
$a = [];
$a[] = &$a;
echo isset($a[0]) ? "ref" : "noreg";
echo "\n";
?>""")
    
    # 深度嵌套
    for i in range(5):
        tests.append(f"""<?php
// 深度嵌套测试 {i}
$arr = [];
for ($j = 0; $j < 10; $j++) {{
    $arr = [$arr];
}}
echo count($arr);
echo "\n";
?>""")
    
    # NULL安全
    for i in range(10):
        tests.append(f"""<?php
// NULL安全测试 {i}
$obj = null;
echo $obj?->value ?? "nullsafe";
echo "\n";
?>""")
    
    # 错误抑制
    for i in range(5):
        tests.append(f"""<?php
// 错误抑制测试 {i}
$result = @file_get_contents("/nonexistent/path/file{i}.txt");
echo $result === false ? "suppressed" : "ok";
echo "\n";
?>""")
    
    # 混合类型比较
    for i in range(15):
        tests.append(f"""<?php
// 混合类型比较测试 {i}
$values = [0, "0", "", false, null, []];
$a = $values[{random.randint(0, 5)}];
$b = $values[{random.randint(0, 5)}];
echo ($a == $b) ? "equal" : "notequal";
echo ($a === $b) ? "identical" : "notidentical";
echo "\n";
?>""")
    
    # 极端浮点
    for i in range(5):
        tests.append(f"""<?php
// 极端浮点测试 {i}
echo is_nan(NAN) ? "nan" : "normal";
echo is_infinite(INF) ? "inf" : "finite";
echo "\n";
?>""")
    
    return tests

def gen_complex_mixed():
    """混合复杂场景测试"""
    tests = []
    
    # 类+数组+循环
    for i in range(20):
        tests.append(f"""<?php
// 混合复杂测试 {i}
class Item {{
    public $id;
    public $data;
    public function __construct($id, $data) {{
        $this->id = $id;
        $this->data = $data;
    }}
}}

$items = [];
for ($j = 0; $j < 5; $j++) {{
    $items[] = new Item($j, range(1, $j + 1));
}}

$sum = 0;
foreach ($items as $item) {{
    $sum += array_sum($item->data);
}}
echo $sum;
echo "\n";
?>""")
    
    # 闭包+数组
    for i in range(15):
        tests.append(f"""<?php
// 闭包数组测试 {i}
$funcs = [];
for ($j = 0; $j < 5; $j++) {{
    $funcs[] = fn($x) => $x * $j;
}}

$result = 0;
foreach ($funcs as $f) {{
    $result += $f(2);
}}
echo $result;
echo "\n";
?>""")
    
    # 字符串处理链
    for i in range(15):
        tests.append(f"""<?php
// 字符串处理链测试 {i}
$str = "  Hello World Test  ";
$result = strtolower(trim($str));
$result = str_replace(" ", "-", $result);
$result = substr($result, 0, 10);
echo $result;
echo "\n";
?>""")
    
    # 多层嵌套控制流
    for i in range(15):
        tests.append(f"""<?php
// 多层嵌套测试 {i}
$result = [];
for ($a = 0; $a < 3; $a++) {{
    for ($b = 0; $b < 3; $b++) {{
        if ($a + $b > 2) {{
            $result[] = $a * 10 + $b;
        }}
    }}
}}
echo implode(",", $result);
echo "\n";
?>""")
    
    # 数组+字符串+数学
    for i in range(15):
        tests.append(f"""<?php
// 综合运算测试 {i}
$nums = [1, 2, 3, 4, 5];
$doubled = array_map(fn($x) => $x * 2, $nums);
$filtered = array_filter($doubled, fn($x) => $x > 4);
$sum = array_sum($filtered);
$str = implode("-", $filtered);
echo $str . ":" . $sum;
echo "\n";
?>""")
    
    # 递归函数
    for i in range(10):
        tests.append(f"""<?php
// 递归函数测试 {i}
function fib($n) {{
    return $n <= 1 ? $n : fib($n - 1) + fib($n - 2);
}}
echo fib({random.randint(5, 10)});
echo "\n";
?>""")
    
    # 引用传递
    for i in range(10):
        tests.append(f"""<?php
// 引用传递测试 {i}
function increment(&$val) {{
    $val++;
}}
$x = {random.randint(1, 10)};
increment($x);
echo $x;
echo "\n";
?>""")
    
    # 变量变量
    for i in range(10):
        tests.append(f"""<?php
// 变量变量测试 {i}
$name = "var{i}";
${{name}} = "value{i}";
echo $var{i};
echo "\n";
?>""")
    
    # 回调函数
    for i in range(10):
        tests.append(f"""<?php
// 回调函数测试 {i}
function apply($arr, $callback) {{
    $result = [];
    foreach ($arr as $item) {{
        $result[] = $callback($item);
    }}
    return $result;
}}
$arr = [1, 2, 3, 4, 5];
$result = apply($arr, fn($x) => $x * $x);
echo implode(",", $result);
echo "\n";
?>""")
    
    # 类型声明
    for i in range(10):
        tests.append(f"""<?php
// 类型声明测试 {i}
function add(int $a, int $b): int {{
    return $a + $b;
}}
echo add({random.randint(1, 50)}, {random.randint(1, 50)});
echo "\n";
?>""")
    
    return tests

def gen_closure_tests():
    """闭包和箭头函数测试"""
    tests = []
    
    # 基础闭包
    for i in range(20):
        tests.append(f"""<?php
// 闭包测试 {i}
$factor = {random.randint(2, 5)};
$multiply = function($x) use ($factor) {{
    return $x * $factor;
}};
echo $multiply({random.randint(1, 10)});
echo "\n";
?>""")
    
    # 箭头函数
    for i in range(20):
        tests.append(f"""<?php
// 箭头函数测试 {i}
$a = {random.randint(1, 10)};
$b = {random.randint(1, 10)};
$sum = fn($x, $y) => $x + $y;
echo $sum($a, $b);
echo "\n";
?>""")
    
    # 闭包作为回调
    for i in range(15):
        tests.append(f"""<?php
// 闭包回调测试 {i}
$arr = [1, 2, 3, 4, 5];
$result = array_map(fn($x) => $x * {random.randint(2, 5)}, $arr);
echo implode(",", $result);
echo "\n";
?>""")
    
    # use引用
    for i in range(10):
        tests.append(f"""<?php
// use引用测试 {i}
$total = 0;
$adder = function($x) use (&$total) {{
    $total += $x;
}};
$adder(1);
$adder(2);
$adder(3);
echo $total;
echo "\n";
?>""")
    
    # 闭包返回闭包
    for i in range(10):
        tests.append(f"""<?php
// 闭包返回闭包测试 {i}
function multiplier($n) {{
    return function($x) use ($n) {{
        return $x * $n;
    }};
}}
$double = multiplier(2);
$triple = multiplier(3);
echo $double(5) + $triple(5);
echo "\n";
?>""")
    
    return tests

def main():
    """主函数 - 生成所有测试脚本"""
    all_tests = []
    
    print("生成基础类型和运算测试...")
    all_tests.extend(gen_type_basic())
    
    print("生成控制流测试...")
    all_tests.extend(gen_control_flow())
    
    print("生成数组操作测试...")
    all_tests.extend(gen_array_operations())
    
    print("生成字符串操作测试...")
    all_tests.extend(gen_string_operations())
    
    print("生成OOP测试...")
    all_tests.extend(gen_oop_tests())
    
    print("生成内置函数测试...")
    all_tests.extend(gen_builtin_functions())
    
    print("生成边界条件测试...")
    all_tests.extend(gen_edge_cases())
    
    print("生成混合复杂场景测试...")
    all_tests.extend(gen_complex_mixed())
    
    print("生成闭包测试...")
    all_tests.extend(gen_closure_tests())
    
    # 写入所有测试脚本
    print(f"\n总共生成 {len(all_tests)} 个测试脚本")
    
    for idx, content in enumerate(all_tests, 1):
        name = f"test_{idx:04d}.php"
        write_script(name, content)
        
        if idx % 100 == 0:
            print(f"已生成 {idx} 个脚本...")
    
    print(f"\n完成！共生成 {len(all_tests)} 个测试脚本到 {BASE_DIR}")
    return len(all_tests)

if __name__ == "__main__":
    main()