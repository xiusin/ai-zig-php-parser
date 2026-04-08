<?php
// 反射API测试

// 反射类
class SampleClass {
    private $privateProp = 'private';
    protected $protectedProp = 'protected';
    public $publicProp = 'public';

    public function __construct($value = 'default') {
        $this->publicProp = $value;
    }

    public function publicMethod($param1, $param2 = 'default'): string {
        return "$param1 - $param2";
    }

    private function privateMethod(): void {}
}

$refClass = new ReflectionClass(SampleClass::class);
echo "Class name: " . $refClass->getName() . "\n";
echo "Is instantiable: " . var_export($refClass->isInstantiable(), true) . "\n";

// 反射属性
$refProps = $refClass->getProperties();
echo "Properties count: " . count($refProps) . "\n";
foreach ($refProps as $prop) {
    echo "  Property: " . $prop->getName() . " (" .
         ($prop->isPublic() ? 'public' : ($prop->isProtected() ? 'protected' : 'private')) . ")\n";
}

// 反射方法
$refMethods = $refClass->getMethods();
echo "Methods count: " . count($refMethods) . "\n";
foreach ($refMethods as $method) {
    echo "  Method: " . $method->getName() . "\n";
}

// 创建实例
$instance = $refClass->newInstance('custom value');
echo "Instance created: " . var_export($instance->publicProp, true) . "\n";

// 反射函数
$refFunc = new ReflectionFunction('strlen');
echo "Function name: " . $refFunc->getName() . "\n";
echo "Number of params: " . $refFunc->getNumberOfParameters() . "\n";

// 反射参数
$refMethod = $refClass->getMethod('publicMethod');
$refParams = $refMethod->getParameters();
foreach ($refParams as $param) {
    echo "Param: " . $param->getName();
    if ($param->isOptional()) {
        echo " (optional, default: " . var_export($param->getDefaultValue(), true) . ")";
    }
    echo "\n";
}

// 反射扩展
$refExt = new ReflectionExtension('core');
echo "Core extension functions: " . count($refExt->getFunctions()) . "\n";

// 反射常量
class ConstClass {
    const MY_CONST = 'constant value';
}
$refConst = new ReflectionClassConstant(ConstClass::class, 'MY_CONST');
echo "Constant value: " . $refConst->getValue() . "\n";

// 调用私有方法
$privateMethod = $refClass->getMethod('privateMethod');
$privateMethod->setAccessible(true);
$privateMethod->invoke($instance);
echo "Private method invoked\n";

// 获取/设置私有属性
$privateProp = $refClass->getProperty('privateProp');
$privateProp->setAccessible(true);
echo "Private prop value: " . $privateProp->getValue($instance) . "\n";
$privateProp->setValue($instance, 'modified private');
echo "Modified private prop: " . $privateProp->getValue($instance) . "\n";

// 反射类型
function typeTest(int $a, string $b, ?float $c = null): array {
    return [$a, $b, $c];
}
$refTypeFunc = new ReflectionFunction('typeTest');
foreach ($refTypeFunc->getParameters() as $p) {
    $type = $p->getType();
    if ($type) {
        echo "Param {$p->getName()} type: " . $type . "\n";
    }
}
$returnType = $refTypeFunc->getReturnType();
echo "Return type: " . ($returnType ? $returnType : 'none') . "\n";

echo "Reflection tests completed\n";
