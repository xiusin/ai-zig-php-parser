<?php
// Test 054: Instanceof, type checks, and casting
class TypeCheckLab {
    public function process(): string {
        $out = "";

        $obj = new stdClass();
        $obj->prop = 'value';

        $arr = [];
        $str = 'string';
        $int = 42;
        $float = 3.14;
        $bool = true;
        $null = null;
        $callable = function() {};

        $out .= "=== Instanceof ===\n";
        $out .= "\$obj instanceof stdClass: " . ($obj instanceof stdClass ? 'yes' : 'no') . "\n";
        $out .= "\$obj instanceof stdClass: " . ($obj instanceof stdClass ? 'yes' : 'no') . "\n";

        $child = new class extends stdClass {};
        $out .= "child instanceof stdClass: " . ($child instanceof stdClass ? 'yes' : 'no') . "\n";

        echo $out;

        echo "\n=== Type checks ===\n";
        echo "is_object(\$obj): " . (is_object($obj) ? 'yes' : 'no') . "\n";
        echo "is_array(\$arr): " . (is_array($arr) ? 'yes' : 'no') . "\n";
        echo "is_string(\$str): " . (is_string($str) ? 'yes' : 'no') . "\n";
        echo "is_int(\$int): " . (is_int($int) ? 'yes' : 'no') . "\n";
        echo "is_float(\$float): " . (is_float($float) ? 'yes' : 'no') . "\n";
        echo "is_bool(\$bool): " . (is_bool($bool) ? 'yes' : 'no') . "\n";
        echo "is_null(\$null): " . (is_null($null) ? 'yes' : 'no') . "\n";
        echo "is_scalar(\$str): " . (is_scalar($str) ? 'yes' : 'no') . "\n";
        echo "is_countable(\$arr): " . (is_countable($arr) ? 'yes' : 'no') . "\n";
        echo "is_callable(\$callable): " . (is_callable($callable) ? 'yes' : 'no') . "\n";

        echo "\n=== Casting ===\n";
        echo "(string)42: " . (string)42 . "\n";
        echo "(int)'123': " . (int)'123' . "\n";
        echo "(float)'3.14': " . (float)'3.14' . "\n";
        echo "(bool)1: " . ((bool)1 ? 'true' : 'false') . "\n";
        echo "(array)\$obj: " . count((array)$obj) . " keys\n";
        echo "(object)\$arr: " . get_class((object)$arr) . "\n";

        echo "\n=== gettype ===\n";
        echo "gettype(\$obj): " . gettype($obj) . "\n";
        echo "gettype(\$arr): " . gettype($arr) . "\n";
        echo "gettype(\$str): " . gettype($str) . "\n";

        return "";
    }
}

$lab = new TypeCheckLab();
$lab->process();