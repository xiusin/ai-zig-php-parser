<?php
// 测试9: 命名空间与use语句
namespace TestNamespace\SubNamespace {
    class Helper {
        public static function greet(string $name): string {
            return "Hello, $name!";
        }
    }
    
    const PI = 3.14159;
    
    function helper(): string {
        return "Helper function";
    }
}

namespace AnotherNamespace {
    use TestNamespace\SubNamespace\Helper;
    use const TestNamespace\SubNamespace\PI;
    use function TestNamespace\SubNamespace\helper;
    
    class Consumer {
        public function useHelper(): string {
            return Helper::greet("World") . " - " . helper() . " - PI=" . PI;
        }
    }
}

namespace {
    use AnotherNamespace\Consumer;
    
    $consumer = new Consumer();
    echo $consumer->useHelper() . "\n";
    echo \TestNamespace\SubNamespace\Helper::greet("PHP") . "\n";
    echo "PI constant: " . \TestNamespace\SubNamespace\PI . "\n";
    echo "Helper function: " . \TestNamespace\SubNamespace\helper() . "\n";
}
?>
