<?php
// 变量高级操作测试

// 变量变量
$name = 'hello';
$$name = 'world';
echo "hello: $hello\n";

// 多层变量变量
$level1 = 'level2';
$level2 = 'level3';
$level3 = 'final value';
echo "level1: $$level1\n";
echo "level2: $$$level1\n";

// 动态变量名
for ($i = 1; $i <= 3; $i++) {
    ${"var$i"} = "value$i";
}
echo "var1: $var1, var2: $var2, var3: $var3\n";

// isset多变量检查
$a = 1;
$b = null;
$c = 'exists';
echo "isset single: " . var_export(isset($a), true) . "\n";
echo "isset null: " . var_export(isset($b), true) . "\n";
echo "isset multi: " . var_export(isset($a, $c), true) . "\n";

// empty检查
echo "empty '': " . var_export(empty($b), true) . "\n";
echo "empty 0: " . var_export(empty(0), true) . "\n";
echo "empty '0': " . var_export(empty('0'), true) . "\n";
echo "empty []: " . var_export(empty([]), true) . "\n";

// 变量类型检查
$values = [
    42,
    3.14,
    "string",
    true,
    null,
    [1, 2, 3],
    new stdClass(),
    fopen('php://memory', 'r')
];

foreach ($values as $i => $val) {
    $types = [];
    if (is_int($val)) $types[] = 'int';
    if (is_float($val)) $types[] = 'float';
    if (is_string($val)) $types[] = 'string';
    if (is_bool($val)) $types[] = 'bool';
    if (is_null($val)) $types[] = 'null';
    if (is_array($val)) $types[] = 'array';
    if (is_object($val)) $types[] = 'object';
    if (is_resource($val)) $types[] = 'resource';
    echo "value $i types: " . implode(', ', $types) . "\n";
}

// 变量销毁
$toDelete = 'will be deleted';
echo "before unset: " . var_export(isset($toDelete), true) . "\n";
unset($toDelete);
echo "after unset: " . var_export(isset($toDelete), true) . "\n";

// 引用变量
$original = 'original value';
$reference = &$original;
$reference = 'modified via reference';
echo "original after reference: $original\n";

// 引用传递
function modifyByReference(&$var) {
    $var = 'modified';
}

$passedByRef = 'original';
modifyByReference($passedByRef);
echo "after pass by reference: $passedByRef\n";

// 引用返回
function &returnReference(&$var) {
    return $var;
}

$container = ['key' => 'value'];
returnReference($container['key']) = 'new value';
echo "after return reference: " . $container['key'] . "\n";

// 变量导出
$export = ['a' => 1, 'b' => 'string', 'c' => true];
echo "var_export:\n" . var_export($export, true) . "\n";

// 变量序列化比较
$serialized = serialize($export);
$unserialized = unserialize($serialized);
echo "serialize equals: " . var_export($export == $unserialized, true) . "\n";

// debug_zval_dump (引用计数)
$val = 'test';
$ref = &$val;
echo "debug_zval_dump output available\n";

// gettype和settype
$mixed = '42';
echo "gettype: " . gettype($mixed) . "\n";
settype($mixed, 'integer');
echo "after settype: " . gettype($mixed) . ", value: $mixed\n";

// 变量存在检查
function checkVar($name) {
    global $$name;
    return isset($$name);
}

$testVar = 'exists';
echo "checkVar testVar: " . var_export(checkVar('testVar'), true) . "\n";
