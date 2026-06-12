<?php

// ============================================================================
// Test 1: ReflectionMethod getModifiers()
// ============================================================================
class ModifierTestClass {
    public function pubMethod(): void {}
    protected function protMethod(): void {}
    private function privMethod(): void {}
    public static function staticMethod(): void {}
    final public function finalMethod(): void {}
}

$rc = new ReflectionClass('ModifierTestClass');

$m1 = $rc->getMethod('pubMethod');
echo "pubMethod modifiers: " . $m1->getModifiers() . "\n"; // 1 (IS_PUBLIC)

$m2 = $rc->getMethod('protMethod');
echo "protMethod modifiers: " . $m2->getModifiers() . "\n"; // 2 (IS_PROTECTED)

$m3 = $rc->getMethod('privMethod');
echo "privMethod modifiers: " . $m3->getModifiers() . "\n"; // 4 (IS_PRIVATE)

$m4 = $rc->getMethod('staticMethod');
$mods4 = $m4->getModifiers();
echo "staticMethod isPublic: " . ($mods4 & 1 ? 'true' : 'false') . "\n"; // true
echo "staticMethod isStatic: " . ($mods4 & 16 ? 'true' : 'false') . "\n"; // true

$m5 = $rc->getMethod('finalMethod');
$mods5 = $m5->getModifiers();
echo "finalMethod isFinal: " . ($mods5 & 32 ? 'true' : 'false') . "\n"; // true

// ============================================================================
// Test 2: ReflectionClass getConstructor()
// ============================================================================
class WithCtor {
    public function __construct(int $x) {}
}

class NoCtor {
}

$rc1 = new ReflectionClass('WithCtor');
$ctor = $rc1->getConstructor();
echo "WithCtor has constructor: " . ($ctor !== null ? 'true' : 'false') . "\n"; // true
echo "Constructor name: " . $ctor->getName() . "\n"; // __construct
echo "Constructor isConstructor: " . ($ctor->isConstructor() ? 'true' : 'false') . "\n"; // true

$rc2 = new ReflectionClass('NoCtor');
$ctor2 = $rc2->getConstructor();
echo "NoCtor has constructor: " . ($ctor2 !== null ? 'true' : 'false') . "\n"; // false

// ============================================================================
// Test 3: ReflectionProperty basics
// ============================================================================
class PropTestClass {
    public string $name = 'hello';
    protected int $age = 0;
    private bool $active = true;
    public static string $label = 'test';
}

$rc = new ReflectionClass('PropTestClass');
$props = $rc->getProperties();
echo "Properties count: " . count($props) . "\n";

// getProperty
$nameProp = $rc->getProperty('name');
echo "Property name: " . $nameProp->getName() . "\n"; // name
echo "name isPublic: " . ($nameProp->isPublic() ? 'true' : 'false') . "\n"; // true
echo "name isDefault: " . ($nameProp->isDefault() ? 'true' : 'false') . "\n"; // true
echo "name hasDefaultValue: " . ($nameProp->hasDefaultValue() ? 'true' : 'false') . "\n"; // true

// ============================================================================
// Test 4: ReflectionMethod hasReturnType/getReturnType
// ============================================================================
class TypedClass {
    public function typedMethod(): string { return ''; }
    public function untypedMethod() { return null; }
}

$rc = new ReflectionClass('TypedClass');
$tm = $rc->getMethod('typedMethod');
echo "typedMethod hasReturnType: " . ($tm->hasReturnType() ? 'true' : 'false') . "\n"; // true

$rt = $tm->getReturnType();
if ($rt !== null) {
    echo "typedMethod returnType getName: " . $rt->getName() . "\n"; // string
    echo "typedMethod returnType isBuiltin: " . ($rt->isBuiltin() ? 'true' : 'false') . "\n"; // true
}

$um = $rc->getMethod('untypedMethod');
echo "untypedMethod hasReturnType: " . ($um->hasReturnType() ? 'true' : 'false') . "\n"; // false

// ============================================================================
// Test 5: ReflectionParameter getType
// ============================================================================
class ParamTypeClass {
    public function doSomething(int $count, string $label = 'default'): void {}
}

$rc = new ReflectionClass('ParamTypeClass');
$method = $rc->getMethod('doSomething');
$params = $method->getParameters();

echo "Param count: " . count($params) . "\n"; // 2

$p0 = $params[0];
echo "Param 0 name: " . $p0->getName() . "\n"; // count
echo "Param 0 hasType: " . ($p0->hasType() ? 'true' : 'false') . "\n"; // true

$p1 = $params[1];
echo "Param 1 name: " . $p1->getName() . "\n"; // label

// ============================================================================
// Test 6: ReflectionProperty hasType/getType
// ============================================================================
class TypedPropClass {
    public string $typed = '';
    public $untyped = null;
}

$rc = new ReflectionClass('TypedPropClass');
$tp = $rc->getProperty('typed');
echo "typed hasType: " . ($tp->hasType() ? 'true' : 'false') . "\n"; // true

$type = $tp->getType();
if ($type !== null) {
    echo "typed type name: " . $type->getName() . "\n"; // string
}

$up = $rc->getProperty('untyped');
echo "untyped hasType: " . ($up->hasType() ? 'true' : 'false') . "\n"; // false

echo "ALL TESTS PASSED\n";
