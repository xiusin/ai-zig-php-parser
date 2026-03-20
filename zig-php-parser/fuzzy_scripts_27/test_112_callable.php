<?php
// Test 112: call_user_func and callable invocation
function add(int $a, int $b): int {
    return $a + $b;
}

function greet(string $name, string $greeting = 'Hello'): string {
    return "$greeting, $name!";
}

class CallableObj {
    public function __invoke(int $x): int {
        return $x * 2;
    }
}

echo "=== call_user_func ===\n";
echo "call_user_func('add', 5, 3): " . call_user_func('add', 5, 3) . "\n";
echo "call_user_func('greet', 'World'): " . call_user_func('greet', 'World') . "\n";
echo "call_user_func('greet', 'PHP', 'Hi'): " . call_user_func('greet', 'PHP', 'Hi') . "\n";

echo "\n=== call_user_func_array ===\n";
echo "call_user_func_array('add', [10, 20]): " . call_user_func_array('add', [10, 20]) . "\n";
echo "call_user_func_array('greet', ['Alice']): " . call_user_func_array('greet', ['Alice']) . "\n";

echo "\n=== __invoke ===\n";
$obj = new CallableObj();
echo "call_user_func(\$obj, 21): " . call_user_func($obj, 21) . "\n";

echo "\n=== is_callable ===\n";
echo "is_callable('add'): " . (is_callable('add') ? 'yes' : 'no') . "\n";
echo "is_callable(\$obj): " . (is_callable($obj) ? 'yes' : 'no') . "\n";
echo "is_callable('non_existent'): " . (is_callable('non_existent') ? 'yes' : 'no') . "\n";