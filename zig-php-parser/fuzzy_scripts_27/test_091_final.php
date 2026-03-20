<?php
// Test 091: Final classes and methods
final class FinalClass {
    public const CONST_VAL = 'final_const';

    public function method(): string {
        return "final_method";
    }

    final public function finalMethod(): string {
        return "final_only_method";
    }
}

class ExtendFinal {
    public function test(): string {
        return "extending_test";
    }
}

echo "=== Final class ===\n";
$obj = new FinalClass();
echo "CONST_VAL: " . FinalClass::CONST_VAL . "\n";
echo "method: " . $obj->method() . "\n";
echo "finalMethod: " . $obj->finalMethod() . "\n";

echo "\n=== Final method in non-final class ===\n";
class ParentWithFinal {
    final public function cannotOverride(): string {
        return "parent_final";
    }
}

class ChildWithFinal extends ParentWithFinal {
    public function override(): string {
        return "child_override";
    }
}

$child = new ChildWithFinal();
echo "cannotOverride: " . $child->cannotOverride() . "\n";
echo "override: " . $child->override() . "\n";

echo "\n=== Final with inheritance ===\n";
final class CannotExtend {
    public string $value = 'cannot_extend';
}

class TryExtend {
    public function getValue(): string {
        $obj = new CannotExtend();
        return $obj->value;
    }
}

$try = new TryExtend();
echo "getValue: " . $try->getValue() . "\n";