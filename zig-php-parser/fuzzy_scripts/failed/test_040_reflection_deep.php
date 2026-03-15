<?php
// 测试40: 反射API深度测试
class ReflectedClass {
    private string $privateProp = "private";
    protected int $protectedProp = 42;
    public array $publicProp = [];
    
    private function privateMethod(): string {
        return "private";
    }
    
    protected function protectedMethod(): int {
        return 42;
    }
    
    public function publicMethod(string $arg): string {
        return "Result: $arg";
    }
    
    public static function staticMethod(): string {
        return "static";
    }
}

$ref = new ReflectionClass("ReflectedClass");

echo "Class name: " . $ref->getName() . "\n";
echo "Is instantiable: " . ($ref->isInstantiable() ? "yes" : "no") . "\n";
echo "Is final: " . ($ref->isFinal() ? "yes" : "no") . "\n";

// 属性
$props = $ref->getProperties();
echo "\nProperties (" . count($props) . "):\n";
foreach ($props as $prop) {
    echo "  " . $prop->getName() . " - " . ($prop->isPrivate() ? "private" : ($prop->isProtected() ? "protected" : "public")) . "\n";
}

// 方法
$methods = $ref->getMethods();
echo "\nMethods (" . count($methods) . "):\n";
foreach ($methods as $method) {
    echo "  " . $method->getName() . "()\n";
}

// 创建实例并访问私有属性
$instance = $ref->newInstance();
$privateProp = $ref->getProperty("privateProp");
$privateProp->setAccessible(true);
echo "\nPrivate property value: " . $privateProp->getValue($instance) . "\n";

// 调用私有方法
$privateMethod = $ref->getMethod("privateMethod");
$privateMethod->setAccessible(true);
echo "Private method result: " . $privateMethod->invoke($instance) . "\n";

// 检查参数
$publicMethod = $ref->getMethod("publicMethod");
$params = $publicMethod->getParameters();
echo "\nParameters of publicMethod:\n";
foreach ($params as $param) {
    echo "  " . $param->getName() . " - type: " . ($param->getType() ? $param->getType()->getName() : "none") . "\n";
}

// 反射函数
function testFunction(int $a, string $b = "default"): bool {
    return $a > 0;
}

$funcRef = new ReflectionFunction("testFunction");
echo "\nFunction: " . $funcRef->getName() . "\n";
echo "Parameters count: " . $funcRef->getNumberOfParameters() . "\n";
echo "Required parameters: " . $funcRef->getNumberOfRequiredParameters() . "\n";

// 调用
$result = $funcRef->invoke(10, "test");
echo "Invoke result: " . ($result ? "true" : "false") . "\n";
?>
