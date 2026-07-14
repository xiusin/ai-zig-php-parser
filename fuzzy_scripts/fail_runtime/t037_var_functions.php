<?php
// 动态函数调用：变量函数、call_user_func、可调用对象

function greet(string $name): string {
    return "Hello, $name!";
}

function shout(string $name): string {
    return strtoupper("Hey, $name!");
}

function whisper(string $name): string {
    return strtolower("psst, $name...");
}

function add(int $a, int $b): int {
    return $a + $b;
}

function multiply(int $a, int $b): int {
    return $a * $b;
}

class MathOps {
    public function add(int $a, int $b): int {
        return $a + $b;
    }

    public static function static_add(int $a, int $b): int {
        return $a + $b;
    }
}

// 测试变量函数调用
$func = 'strtoupper';
echo "var_func: " . $func('hello') . "\n";

$func = 'greet';
echo "var_greet: " . $func('World') . "\n";

// 测试动态选择函数
$mode = 'shout';
echo "dynamic_mode: " . $mode('Alice') . "\n";

$mode = 'whisper';
echo "dynamic_mode2: " . $mode('Bob') . "\n";

// 测试 call_user_func
echo "cuf_greet: " . call_user_func('greet', 'Charlie') . "\n";
echo "cuf_add: " . call_user_func('add', 3, 5) . "\n";

// 测试 call_user_func_array
echo "cufa_add: " . call_user_func_array('add', [10, 20]) . "\n";
echo "cufa_mul: " . call_user_func_array('multiply', [4, 6]) . "\n";

// 测试动态方法调用
$math = new MathOps();
echo "dynamic_method: " . $math->{'add'}(3, 5) . "\n";

// 测试静态方法动态调用
echo "static_method: " . call_user_func(['MathOps', 'static_add'], 7, 8) . "\n";

// 测试对象方法调用
echo "obj_method: " . call_user_func([$math, 'add'], 10, 5) . "\n";

// 测试闭包作为可调用
$closure = fn($a, $b) => $a - $b;
echo "closure_call: " . $closure(10, 3) . "\n";
echo "cuf_closure: " . call_user_func($closure, 20, 5) . "\n";

// 测试函数名数组
$functions = ['add', 'multiply'];
foreach ($functions as $fn) {
    echo "array_call: " . $fn(3, 4) . "\n";
}

// 测试 is_callable
echo "is_callable_func: " . (is_callable('greet') ? 'true' : 'false') . "\n";
echo "is_callable_closure: " . (is_callable($closure) ? 'true' : 'false') . "\n";
echo "is_callable_method: " . (is_callable([$math, 'add']) ? 'true' : 'false') . "\n";
echo "is_callable_invalid: " . (is_callable('nonexistent_func') ? 'true' : 'false') . "\n";
