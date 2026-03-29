<?php
// Test 052: Class constant expressions with various operators
class ConstExpr2 {
    public const ARITH = 10 + 5 * 2;
    public const COMPARE = (5 > 3) ? 'yes' : 'no';
    public const SPACESHIP = 5 <=> 10;
    public const ARRAY_LITERAL = [1, 2, 3];
    public const ASSOC_ARRAY = ['a' => 1, 'b' => 2];
    public const NESTED_ARRAY = [['x' => 1], ['y' => 2]];
    public const BOOLEAN = true and false;
    public const LOGICAL_OR = true || false;
    public const LOGICAL_AND = true && false;
    public const BITwise_OR = 0x0F | 0xF0;
    public const BITwise_AND = 0xFF & 0x0F;
    public const BITwise_XOR = 0xAA ^ 0x55;
    public const SHIFT_LEFT = 1 << 3;
    public const SHIFT_RIGHT = 8 >> 1;
}

echo "=== Const Expressions 2 ===\n";
echo "ARITH (10 + 5 * 2): " . ConstExpr2::ARITH . "\n";
echo "COMPARE: " . ConstExpr2::COMPARE . "\n";
echo "SPACESHIP (5 <=> 10): " . ConstExpr2::SPACESHIP . "\n";
echo "ARRAY_LITERAL: " . json_encode(ConstExpr2::ARRAY_LITERAL) . "\n";
echo "ASSOC_ARRAY: " . json_encode(ConstExpr2::ASSOC_ARRAY) . "\n";
echo "NESTED_ARRAY: " . json_encode(ConstExpr2::NESTED_ARRAY) . "\n";
echo "BOOLEAN (true and false): " . (ConstExpr2::BOOLEAN ? 'true' : 'false') . "\n";
echo "LOGICAL_OR: " . (ConstExpr2::LOGICAL_OR ? 'true' : 'false') . "\n";
echo "LOGICAL_AND: " . (ConstExpr2::LOGICAL_AND ? 'true' : 'false') . "\n";
echo "BITwise_OR (0x0F | 0xF0): " . ConstExpr2::BITwise_OR . "\n";
echo "BITwise_AND (0xFF & 0x0F): " . ConstExpr2::BITwise_AND . "\n";
echo "BITwise_XOR (0xAA ^ 0x55): " . ConstExpr2::BITwise_XOR . "\n";
echo "SHIFT_LEFT (1 << 3): " . ConstExpr2::SHIFT_LEFT . "\n";
echo "SHIFT_RIGHT (8 >> 1): " . ConstExpr2::SHIFT_RIGHT . "\n";

echo "\n=== Class constant as array key ===\n";
$arr = [ConstExpr2::ARITH => 'value'];
echo "Array with const as key: " . json_encode($arr) . "\n";