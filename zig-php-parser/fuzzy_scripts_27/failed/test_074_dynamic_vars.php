<?php
// Test 074: Variable variables and dynamic names
class DynamicVars {
    public function process(): string {
        $out = "";

        $base = 'var';
        $$base = 'value_of_var';
        $out .= "\$\$base where base='var': $var\n";

        $prefix = 'dyn';
        ${$prefix . '_name'} = 'dynamic_value';
        $out .= "\${$prefix . '_name'}: $dyn_name\n";

        $obj = new stdClass();
        $obj->dynamic = 'object_property';
        $propName = 'dynamic';
        $out .= "\$obj->\$propName: " . $obj->$propName . "\n";

        return $out;
    }
}

$lab = new DynamicVars();
echo $lab->process();

echo "\n=== Dynamic function call ===\n";
$funcName = 'strtoupper';
echo "$funcName('hello'): " . $funcName('hello') . "\n";

echo "\n=== Dynamic class constant ===\n";
class DynamicConst {
    const VALUE = 'const_value';
}

$constName = 'VALUE';
echo "DynamicConst::\$constName: " . DynamicConst::$$constName . "\n";

echo "\n=== Dynamic property ===\n";
$obj = new stdClass();
$obj->prop1 = 'first';
$obj->prop2 = 'second';

foreach (['prop1', 'prop2'] as $name) {
    $dynamicProp = $obj->$name;
    echo "\$obj->$name: $dynamicProp\n";
}

echo "\n=== Array of dynamic variables ===\n";
$base = 'item';
${$base . '_1'} = 'one';
${$base . '_2'} = 'two';
${$base . '_3'} = 'three';

echo "item_1: $item_1\n";
echo "item_2: $item_2\n";
echo "item_3: $item_3\n";