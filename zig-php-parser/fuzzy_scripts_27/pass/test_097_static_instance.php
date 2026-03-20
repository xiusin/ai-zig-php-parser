<?php
// Test 097: Static vs instance method calls
class StaticVsInstance {
    public string $value = 'instance';

    public function getValue(): string {
        return $this->value;
    }

    public static function getStaticValue(): string {
        return 'static';
    }

    public function getViaStatic(): string {
        return static::getStaticValue();
    }
}

class StaticChild extends StaticVsInstance {
    public string $value = 'child_instance';

    public static function getStaticValue(): string {
        return 'child_static';
    }
}

echo "=== Static vs instance ===\n";
$obj = new StaticVsInstance();
echo "getValue: " . $obj->getValue() . "\n";
echo "getStaticValue: " . StaticVsInstance::getStaticValue() . "\n";

echo "\n=== Static late binding ===\n";
echo "StaticChild::getStaticValue: " . StaticChild::getStaticValue() . "\n";

$child = new StaticChild();
echo "child->getValue: " . $child->getValue() . "\n";

echo "\n=== getViaStatic ===\n";
echo "obj->getViaStatic: " . $obj->getViaStatic() . "\n";
$childObj = new StaticChild();
echo "childObj->getViaStatic: " . $childObj->getViaStatic() . "\n";

echo "\n=== Static property ===\n";
class StaticProp {
    public static string $static = 'static_value';
    public string $instance = 'instance_value';
}

$staticProp = new StaticProp();
echo "StaticProp::\$static: " . StaticProp::$static . "\n";
echo "\$staticProp->instance: " . $staticProp->instance . "\n";