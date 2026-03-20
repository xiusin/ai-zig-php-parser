<?php
// Test 047: Class constant expressions, const expressions with operators
class ConstExpressions {
    public const SUM = 1 + 2 + 3;
    public const PRODUCT = 2 * 3 * 4;
    public const MIXED = (1 + 2) * (3 - 1);
    public const STRING_CONCAT = "Hello" . " " . "World";
    public const ARRAY_CONST = [1, 2, 3, 4, 5];
    public const ARRAY_EXPR = [1 + 1, 2 * 2, 3 ** 2];
    public const BOOL_AND = true && false;
    public const BOOL_OR = true || false;
    public const NULL_COALESCE = "default";
    public const NEGATIVE = -100;
    public const FLOAT_EXPR = 3.14 * 2;
    public const MODULO = 10 % 3;
    public const BITWISE = 0xFF & 0x0F;

    public const CONDITIONAL = true ? "yes" : "no";
    public const NULL_C = null ?? "nullish";

    public function getAll(): array {
        return [
            'SUM' => self::SUM,
            'PRODUCT' => self::PRODUCT,
            'MIXED' => self::MIXED,
            'STRING_CONCAT' => self::STRING_CONCAT,
            'ARRAY_CONST' => self::ARRAY_CONST,
            'ARRAY_EXPR' => self::ARRAY_EXPR,
            'BOOL_AND' => self::BOOL_AND,
            'BOOL_OR' => self::BOOL_OR,
            'NULL_COALESCE' => self::NULL_COALESCE,
            'NEGATIVE' => self::NEGATIVE,
            'FLOAT_EXPR' => self::FLOAT_EXPR,
            'MODULO' => self::MODULO,
            'BITWISE' => self::BITWISE,
            'CONDITIONAL' => self::CONDITIONAL,
            'NULL_C' => self::NULL_C,
        ];
    }
}

echo "=== Const Expressions ===\n";
$ce = new ConstExpressions();
foreach ($ce->getAll() as $name => $value) {
    $display = is_array($value) ? json_encode($value) : (is_bool($value) ? ($value ? 'true' : 'false') : $value);
    echo "$name: $display\n";
}

echo "\n=== Arithmetic in constants ===\n";
echo "SUM: " . ConstExpressions::SUM . "\n";
echo "PRODUCT: " . ConstExpressions::PRODUCT . "\n";
echo "MIXED ((1+2)*(3-1)): " . ConstExpressions::MIXED . "\n";

echo "\n=== Bitwise in constants ===\n";
echo "BITWISE (0xFF & 0x0F): " . ConstExpressions::BITWISE . "\n";

echo "\n=== Constant arrays ===\n";
echo "ARRAY_EXPR ([1+1, 2*2, 3**2]): " . json_encode(ConstExpressions::ARRAY_EXPR) . "\n";