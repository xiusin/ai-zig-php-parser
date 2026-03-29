<?php
// Test 115: get_debug_type (PHP 8)
class DebugTypeTarget {
    public function process(): string {
        $out = "";

        $out .= "get_debug_type('string'): " . get_debug_type('string') . "\n";
        $out .= "get_debug_type(123): " . get_debug_type(123) . "\n";
        $out .= "get_debug_type(3.14): " . get_debug_type(3.14) . "\n";
        $out .= "get_debug_type(true): " . get_debug_type(true) . "\n";
        $out .= "get_debug_type(null): " . get_debug_type(null) . "\n";
        $out .= "get_debug_type([]): " . get_debug_type([]) . "\n";
        $out .= "get_debug_type(\$this): " . get_debug_type($this) . "\n";

        $obj = new stdClass();
        $out .= "get_debug_type(\$obj): " . get_debug_type($obj) . "\n";

        $arr = [1, 2, 3];
        $out .= "get_debug_type(\$arr): " . get_debug_type($arr) . "\n";

        return $out;
    }
}

echo "=== get_debug_type ===\n";
$lab = new DebugTypeTarget();
echo $lab->process();