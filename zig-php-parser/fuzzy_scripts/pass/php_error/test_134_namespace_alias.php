<?php
// Test 134: Namespace aliasing
namespace Test\Outer\Inner\Deep {
    class DeepClass {
        public function greet(): string {
            return "Hello from deep namespace";
        }
    }

    const DEEP_CONST = 'deep_constant';
}

namespace {
    use Test\Outer\Inner\Deep\DeepClass;
    use Test\Outer\Inner\Deep\DEEP_CONST;
    use Test\Outer\Inner\Deep\DeepClass as Deep;

    echo "=== Namespace aliasing ===\n";
    $obj = new DeepClass();
    echo "DeepClass: " . $obj->greet() . "\n";
    echo "DEEP_CONST: " . DEEP_CONST . "\n";

    $alias = new Deep();
    echo "Alias Deep: " . $alias->greet() . "\n";

    echo "\n=== Fully qualified ===\n";
    $fq = new \Test\Outer\Inner\Deep\DeepClass();
    echo "Fully qualified: " . $fq->greet() . "\n";
    echo "Fully qualified const: " . \Test\Outer\Inner\Deep\DEEP_CONST . "\n";
}