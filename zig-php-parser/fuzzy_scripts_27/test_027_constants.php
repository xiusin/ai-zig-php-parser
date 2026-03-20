<?php
// Test 027: Final constants, PHP 8.3 improvements, and typed class constants
interface ConstantsInterface {
    const INTERFACE_CONST = 'interface';
}

trait ConstantsTrait {
    const TRAIT_CONST = 'trait';
}

class BaseConstants {
    const BASE_VALUE = 100;
}

class ConstantsLab extends BaseConstants implements ConstantsInterface {
    use ConstantsTrait;

    final const FINAL_STRING = 'final_string';
    final const FINAL_INT = 42;
    final const FINAL_ARRAY = ['a', 'b', 'c'];

    public const PUBLIC_NUM = 1;
    private const PRIVATE_NUM = 2;
    protected const PROTECTED_NUM = 3;

    public const TYPED_INT = 100;
    public const TYPED_STRING = 'hello';
    public const TYPED_ARRAY = [1, 2, 3];
    public const TYPED_FLOAT = 3.14;
    public const TYPED_BOOL = true;
    public const TYPED_NULL = null;
    public const TYPED_MIXED = 'mixed_value';

    public const WITH_DEFAULT = 'default';
    public const COMPUTABLE = 1 + 2 + 3;

    public static function getPrivate(): int {
        return self::PRIVATE_NUM;
    }

    public static function getProtected(): int {
        return self::PROTECTED_NUM;
    }
}

class ChildConstants extends ConstantsLab {
    public const CHILD_VALUE = 'child';

    public function testInheritance(): string {
        return self::FINAL_STRING . ' ' . parent::BASE_VALUE;
    }
}

echo "=== Final constants ===\n";
echo "ConstantsLab::FINAL_STRING: " . ConstantsLab::FINAL_STRING . "\n";
echo "ConstantsLab::FINAL_INT: " . ConstantsLab::FINAL_INT . "\n";
echo "ConstantsLab::FINAL_ARRAY: " . implode(',', ConstantsLab::FINAL_ARRAY) . "\n";

echo "\n=== Typed constants ===\n";
echo "TYPED_INT: " . ConstantsLab::TYPED_INT . "\n";
echo "TYPED_STRING: " . ConstantsLab::TYPED_STRING . "\n";
echo "TYPED_FLOAT: " . ConstantsLab::TYPED_FLOAT . "\n";
echo "TYPED_BOOL: " . (ConstantsLab::TYPED_BOOL ? 'true' : 'false') . "\n";
echo "TYPED_MIXED: " . ConstantsLab::TYPED_MIXED . "\n";
echo "COMPUTABLE: " . ConstantsLab::COMPUTABLE . "\n";

echo "\n=== Access control ===\n";
echo "PUBLIC_NUM: " . ConstantsLab::PUBLIC_NUM . "\n";
echo "getPrivate(): " . ConstantsLab::getPrivate() . "\n";
echo "getProtected(): " . ConstantsLab::getProtected() . "\n";

echo "\n=== Inheritance ===\n";
$child = new ChildConstants();
echo "ChildConstants::CHILD_VALUE: " . ChildConstants::CHILD_VALUE . "\n";
echo "ChildConstants inherits BASE_VALUE: " . ChildConstants::BASE_VALUE . "\n";
echo "Child testInheritance: " . $child->testInheritance() . "\n";

echo "\n=== Interface and trait constants ===\n";
echo "INTERFACE_CONST: " . ConstantsLab::INTERFACE_CONST . "\n";
echo "TRAIT_CONST: " . ConstantsLab::TRAIT_CONST . "\n";

echo "\n=== Class constant reflection ===\n";
$rc = new ReflectionClass(ConstantsLab::class);
foreach ($rc->getConstants() as $name => $value) {
    $type = $rc->getConstant($name);
    echo "  $name: " . (is_array($value) ? json_encode($value) : $value) . "\n";
}