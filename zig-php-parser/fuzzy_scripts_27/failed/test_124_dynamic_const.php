<?php
// Test 124: Dynamic class constant access
class DynamicConst {
    public const VALUE = 'const_value';
    public const NUM = 42;
}

echo "=== Dynamic constant access ===\n";
$constName = 'VALUE';
echo "DynamicConst::\$constName where constName='VALUE': " . DynamicConst::$$constName . "\n";

$constNum = 'NUM';
echo "DynamicConst::\$constNum: " . DynamicConst::$$constNum . "\n";

echo "\n=== Reflection on constants ===\n";
$rc = new ReflectionClass(DynamicConst::class);
$consts = $rc->getConstants();
echo "Constants via reflection: " . json_encode($consts) . "\n";

echo "\n=== Constant expression with dynamic ===\n";
$prefix = 'DYN_';
const PREFIXED = 100;
echo "Constant with prefix: " . PREFIXED . "\n";