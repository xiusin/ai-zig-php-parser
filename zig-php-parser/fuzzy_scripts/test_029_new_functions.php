<?php
// Test 029: New functions in PHP 8.x
class NewFunctionsLab {
    public function process(): string {
        $out = "";

        // str_contains, str_starts_with, str_ends_with
        $haystack = "Hello World";
        $out .= "str_contains('$haystack', 'World'): " . (str_contains($haystack, 'World') ? 'true' : 'false') . "\n";
        $out .= "str_starts_with('$haystack', 'Hello'): " . (str_starts_with($haystack, 'Hello') ? 'true' : 'false') . "\n";
        $out .= "str_ends_with('$haystack', 'World'): " . (str_ends_with($haystack, 'World') ? 'true' : 'false') . "\n";

        // fdiv
        $out .= "fdiv(10, 3): " . fdiv(10, 3) . "\n";
        $out .= "fdiv(-10, 3): " . fdiv(-10, 3) . "\n";
        $out .= "fdiv(1, INF): " . fdiv(1, INF) . "\n";

        // get_resource_id
        $fh = fopen('php://memory', 'r+');
        $out .= "get_resource_id(\$fh): " . get_resource_id($fh) . "\n";
        fclose($fh);

        // get_debug_type
        $out .= "get_debug_type('string'): " . get_debug_type('string') . "\n";
        $out .= "get_debug_type(123): " . get_debug_type(123) . "\n";
        $out .= "get_debug_type([]): " . get_debug_type([]) . "\n";
        $out .= "get_debug_type(null): " . get_debug_type(null) . "\n";

        // array_is_list
        $out .= "array_is_list([1,2,3]): " . (array_is_list([1,2,3]) ? 'true' : 'false') . "\n";
        $out .= "array_is_list(['a'=>1,'b'=>2]): " . (array_is_list(['a'=>1,'b'=>2]) ? 'true' : 'false') . "\n";
        $out .= "array_is_list([]): " . (array_is_list([]) ? 'true' : 'false') . "\n";

        // enum_exists
        $out .= "enum_exists('Status'): " . (enum_exists('Status') ? 'true' : 'false') . "\n";
        $out .= "enum_exists('NonExistent'): " . (enum_exists('NonExistent') ? 'true' : 'false') . "\n";

        return $out;
    }
}

enum Status: string {
    case Active = 'active';
    case Inactive = 'inactive';
}

echo "=== New string functions ===\n";
$lab = new NewFunctionsLab();
echo $lab->process();

echo "\n=== MySQL functions emulation ===\n";
echo "function_exists('mysql_connect'): " . (function_exists('mysql_connect') ? 'yes' : 'no') . "\n";
echo "function_exists('mysqli_connect'): " . (function_exists('mysqli_connect') ? 'yes' : 'no') . "\n";

echo "\n=== Other PHP 8 functions ===\n";
echo "token_get_all exists: " . (function_exists('token_get_all') ? 'yes' : 'no') . "\n";
echo "array_find exists: " . (function_exists('array_find') ? 'yes' : 'no') . "\n";
echo "array_find_key exists: " . (function_exists('array_find_key') ? 'yes' . "\n" : 'no' . "\n");

echo "\n=== String functions ===\n";
echo "trim('  test  '): '" . trim("  test  ") . "'\n";
echo "ltrim('  test'): '" . ltrim("  test") . "'\n";
echo "rtrim('test  '): '" . rtrim("test  ") . "'\n";
echo "strip_tags('<b>test</b>'): '" . strip_tags("<b>test</b>") . "'\n";

echo "\n=== Number formatting ===\n";
echo "number_format(1234567.89, 2): " . number_format(1234567.89, 2) . "\n";
echo "sprintf('%.2f', 3.14159): " . sprintf("%.2f", 3.14159) . "\n";