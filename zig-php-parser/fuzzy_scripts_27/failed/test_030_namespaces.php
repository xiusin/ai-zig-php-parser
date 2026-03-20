<?php
// Test 030: Namespaces, use statements, and group use
namespace Test\Outer\Inner {
    class NamespaceClass {
        public function greet(): string {
            return "Hello from namespace";
        }
    }

    const NAMESPACE_CONST = 42;

    function namespaceFunction(): string {
        return "namespace function";
    }
}

namespace {
    use Test\Outer\Inner\NamespaceClass;
    use Test\Outer\Inner\NAMESPACE_CONST;
    use Test\Outer\Inner\namespaceFunction;

    use function Test\Outer\Inner\namespaceFunction as nsFunc;
    use const Test\Outer\Inner\NAMESPACE_CONST as NS_CONST;

    class MainClass {
        public function test(): string {
            $obj = new NamespaceClass();
            return $obj->greet();
        }

        public function useConst(): int {
            return NAMESPACE_CONST + NS_CONST;
        }

        public function useFunc(): string {
            return nsFunc();
        }
    }

    echo "=== Namespace tests ===\n";
    $main = new MainClass();
    echo "NamespaceClass greeting: " . $main->test() . "\n";
    echo "NamespaceConst sum: " . $main->useConst() . "\n";
    echo "NamespaceFunc alias: " . $main->useFunc() . "\n";

    echo "\n=== Direct namespace access ===\n";
    $nsObj = new \Test\Outer\Inner\NamespaceClass();
    echo "Direct access: " . $nsObj->greet() . "\n";
    echo "Direct const: " . \Test\Outer\Inner\NAMESPACE_CONST . "\n";
    echo "Direct function: " . \Test\Outer\Inner\namespaceFunction() . "\n";
}

namespace Another\Space {
    class AnotherClass {
        public string $value = "another";
    }
}

namespace {
    use Another\Space\AnotherClass;

    echo "\n=== Multiple namespaces ===\n";
    $another = new AnotherClass();
    echo "AnotherClass value: " . $another->value . "\n";

    echo "\n=== Namespace and class name resolution ===\n";
    echo "__NAMESPACE__: " . (defined('__NAMESPACE__') ? __NAMESPACE__ : 'global') . "\n";
}