<?php
// Test 071: Class constant expressions
class ConstExpressions {
    public const SIMPLE = 100;
    public const WITH_EXPRESSION = 10 + 20 * 2;
    public const WITH_PARENS = (10 + 20) * 2;
    public const STRING = "Hello" . " " . "World";
    public const BOOLEAN = true && false;
    public const NULL = null;
    public const ARRAY = [1, 2, 3];
    public const ASSOC = ['a' => 1, 'b' => 2];

    public function getAll(): array {
        return [
            'SIMPLE' => self::SIMPLE,
            'WITH_EXPRESSION' => self::WITH_EXPRESSION,
            'WITH_PARENS' => self::WITH_PARENS,
            'STRING' => self::STRING,
            'BOOLEAN' => self::BOOLEAN,
            'NULL' => self::NULL,
            'ARRAY' => self::ARRAY,
            'ASSOC' => self::ASSOC,
        ];
    }
}

class ChildConst extends ConstExpressions {
    public const CHILD_ONLY = 999;
    public const OVERRIDE = "child_override";

    public function getChild(): array {
        return [
            'CHILD_ONLY' => self::CHILD_ONLY,
            'OVERRIDE' => self::OVERRIDE,
            'PARENT_SIMPLE' => parent::SIMPLE,
            'PARENT_EXPR' => parent::WITH_EXPRESSION,
        ];
    }
}

echo "=== Constant expressions ===\n";
$ce = new ConstExpressions();
foreach ($ce->getAll() as $name => $value) {
    $display = is_array($value) ? json_encode($value) : (is_bool($value) ? ($value ? 'true' : 'false') : (is_null($value) ? 'null' : $value));
    echo "$name: $display\n";
}

echo "\n=== Child class constants ===\n";
$child = new ChildConst();
foreach ($child->getChild() as $name => $value) {
    $display = is_array($value) ? json_encode($value) : $value;
    echo "$name: $display\n";
}

echo "\n=== Interface constants ===\n";
interface IConst {
    const INTERFACE_VAL = 100;
    const COMPUTED = 50 * 2;
}

class ImplConst implements IConst {}

echo "IConst::INTERFACE_VAL: " . IConst::INTERFACE_VAL . "\n";
echo "IConst::COMPUTED: " . IConst::COMPUTED . "\n";
echo "ImplConst::INTERFACE_VAL: " . ImplConst::INTERFACE_VAL . "\n";

echo "\n=== Trait constants ===\n";
trait TConst {
    const TRAIT_VAL = 'from_trait';
}

class UseTraitConst {
    use TConst;
    const CLASS_VAL = 'from_class';
}

echo "UseTraitConst::TRAIT_VAL: " . UseTraitConst::TRAIT_VAL . "\n";
echo "UseTraitConst::CLASS_VAL: " . UseTraitConst::CLASS_VAL . "\n";

echo "\n=== const vs define ===\n";
define('MY_CONST', 123);
define('MY_ARRAY_CONST', ['a' => 1, 'b' => 2]);
echo "defined('MY_CONST'): " . (defined('MY_CONST') ? MY_CONST : 'n/a') . "\n";
echo "defined('MY_ARRAY_CONST'): " . (defined('MY_ARRAY_CONST') ? json_encode(MY_ARRAY_CONST) : 'n/a') . "\n";