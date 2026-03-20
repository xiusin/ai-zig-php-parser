<?php
// Test 168: Interface with constants
interface WithConst {
    public const CONST_VALUE = 100;
    public function getConst(): int;
}

class UseConst implements WithConst {
    public function getConst(): int {
        return self::CONST_VALUE;
    }
}

echo "Interface const: " . WithConst::CONST_VALUE . "\n";
echo "Class via interface const: " . UseConst::CONST_VALUE . "\n";
echo "getConst: " . UseConst::getConst() . "\n";