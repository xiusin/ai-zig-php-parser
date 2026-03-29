<?php
// Test 002: Advanced type juggling and arithmetic operations
class NumberProcessor {
    public function __construct(private mixed $value) {}

    public function process(): string {
        $result = "Original: " . var_export($this->value, true) . "\n";

        $as_int = (int)$this->value;
        $as_float = (float)$this->value;
        $as_string = (string)$this->value;
        $as_bool = (bool)$this->value;
        $as_array = (array)$this->value;
        $as_object = (object)$this->value;

        $result .= "As int: $as_int (type: " . gettype($as_int) . ")\n";
        $result .= "As float: $as_float (type: " . gettype($as_float) . ")\n";
        $result .= "As string: $as_string (type: " . gettype($as_string) . ")\n";
        $result .= "As bool: " . ($as_bool ? 'true' : 'false') . " (type: " . gettype($as_bool) . ")\n";
        $result .= "As array: " . count($as_array) . " elements\n";
        $result .= "As object: " . get_class($as_object) . "\n";

        // String operations with numbers
        $str_num = "123.456";
        $result .= "String math: $str_num + 1 = " . ($str_num + 1) . "\n";
        $result .= "Intval: " . intval($str_num) . "\n";
        $result .= "Floatval: " . floatval($str_num) . "\n";

        // Hex and octal
        $hex = 0xFF;
        $oct = 0755;
        $bin = 0b1010;
        $result .= "Hex(0xFF): $hex, Oct(0755): $oct, Bin(0b1010): $bin\n";

        // Scientific notation
        $sci = 1.23e4;
        $result .= "Scientific: 1.23e4 = $sci\n";

        // Special float values
        $inf = INF;
        $neg_inf = -INF;
        $nan = NAN;
        $result .= "INF: $inf, -INF: $neg_inf, NAN: " . var_export($nan, true) . "\n";
        $result .= "is_infinite(INF): " . (is_infinite($inf) ? 'true' : 'false') . "\n";
        $result .= "is_nan(NAN): " . (is_nan($nan) ? 'true' : 'false') . "\n";
        $result .= "is_finite(1.0): " . (is_finite(1.0) ? 'true' : 'false') . "\n";

        // Integer overflow
        $max_int = PHP_INT_MAX;
        $min_int = PHP_INT_MIN;
        $result .= "PHP_INT_MAX: $max_int\n";
        $result .= "PHP_INT_MIN: $min_int\n";
        $result .= "PHP_INT_MAX + 1: " . ($max_int + 1) . "\n";

        return $result;
    }
}

$test_values = [
    "123",
    "123.456",
    "0xFF",
    "0755",
    "1e5",
    "true",
    "false",
    "null",
    "123abc",
    "",
    [],
    ['a' => 1],
];

foreach ($test_values as $val) {
    $proc = new NumberProcessor($val);
    echo "--- Testing: " . var_export($val, true) . " ---\n";
    echo $proc->process();
}