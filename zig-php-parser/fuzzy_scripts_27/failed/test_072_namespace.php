<?php
// Test 072: Namespaced functions and constants
namespace Test\Space {
    const NS_CONST = 'namespace_const';

    function nsFunc(): string {
        return "namespace_function";
    }

    class NsClass {
        public function greet(): string {
            return "Hello from namespace";
        }
    }
}

namespace {
    use Test\Space\NS_CONST;
    use function Test\Space\nsFunc;
    use Test\Space\NsClass;

    echo "=== Namespace functions ===\n";
    echo "NS_CONST: " . NS_CONST . "\n";
    echo "nsFunc(): " . nsFunc() . "\n";

    $obj = new NsClass();
    echo "NsClass->greet(): " . $obj->greet() . "\n";

    echo "\n=== Global namespace ===\n";
    echo "\Test\Space\NS_CONST: " . \Test\Space\NS_CONST . "\n";
    echo "\Test\Space\nsFunc(): " . \Test\Space\nsFunc() . "\n";

    $direct = new \Test\Space\NsClass();
    echo "Direct class: " . $direct->greet() . "\n";
}