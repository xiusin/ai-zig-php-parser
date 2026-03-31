<?php
// Test 015: Variable variables, dynamic code, and evaluation
class DynamicLab {
    public function process(): string {
        $out = "";

        // Variable variables
        $var = 'dynamic';
        $$var = 'value_of_dynamic';
        $out .= "Variable variable \$\$var where var='dynamic': " . $dynamic . "\n";

        // Nested variable variables
        $prefix = 'outer';
        $$prefix = 'inner_value';
        $outer = 'final_value';
        $out .= "\$prefix = '$prefix', \$\$prefix = '" . $outer . "'\n";

        // Variable property access
        $obj = new stdClass();
        $obj->dynamicProp = 'prop_value';
        $propName = 'dynamicProp';
        $out .= "\$obj->\$propName: " . $obj->$propName . "\n";

        // Dynamic function call
        $funcName = 'strtoupper';
        $out .= "\$funcName(): " . $funcName('hello') . "\n";

        // Array of variable variables
        $base = 'item';
        foreach (['a', 'b', 'c'] as $suffix) {
            ${$base . $suffix} = "value_$suffix";
        }
        $out .= "\nVariable variables itema, itemb, itemc:\n";
        $out .= "  itema: $itema, itemb: $itemb, itemc: $itemc\n";

        // Extract from array
        $data = ['x' => 1, 'y' => 2, 'z' => 3];
        extract($data);
        $out .= "\nextract() result: x=$x, y=$y, z=$z\n";

        // Compact
        $a = 'first';
        $b = 'second';
        $compact = compact('a', 'b');
        $out .= "compact('a','b'): " . json_encode($compact) . "\n";

        // Get defined variables
        $vars = get_defined_vars();
        $out .= "\nget_defined_vars() keys (first 10): " . implode(', ', array_slice(array_keys($vars), 0, 10)) . "\n";

        // Get defined constants
        $consts = get_defined_constants(true);
        $out .= "get_defined_constants() user: " . (isset($consts['user']) ? count($consts['user']) : 0) . " constants\n";

        return $out;
    }

    public function dynamicClassCreation(): string {
        $out = "";

        // Create anonymous class
        $DynamicAnon = new class {
            public string $value = 'anonymous';
            public function getValue(): string {
                return $this->value;
            }
        };
        $out .= "Anonymous class getValue: " . $DynamicAnon->getValue() . "\n";

        // Dynamic property assignment
        $DynamicAnon->newProp = 'added_later';
        $out .= "DynamicAnon->newProp: " . $DynamicAnon->newProp . "\n";

        return $out;
    }
}

class DynamicTestClass {
    const VALUE = 42;
    public function getType(): string {
        return 'DynamicTestClass';
    }
}

$lab = new DynamicLab();
echo $lab->process();
echo "\n";
echo $lab->dynamicClassCreation();

// Variable class constant access
$constName = 'VALUE';
$out = DynamicTestClass::class;
echo "\nDynamicTestClass::\$constName where constName='VALUE': " . DynamicTestClass::$$constName . "\n";

// Variable method call
$methodName = 'getType';
$obj2 = new DynamicTestClass();
echo "\$obj->\$methodName(): " . $obj2->$methodName() . "\n";