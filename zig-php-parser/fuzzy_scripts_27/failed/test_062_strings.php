<?php
// Test 062: String functions, substr, strpos, etc.
class StringFunctions {
    public function process(): string {
        $out = "";

        $str = "Hello, World!";
        $out .= "Original: $str\n";
        $out .= "strlen: " . strlen($str) . "\n";
        $out .= "substr(0, 5): " . substr($str, 0, 5) . "\n";
        $out .= "substr(7, 5): " . substr($str, 7, 5) . "\n";
        $out .= "substr(-5, 5): " . substr($str, -5, 5) . "\n";
        $out .= "strpos('World'): " . strpos($str, 'World') . "\n";
        $out .= "strrpos('l'): " . strrpos($str, 'l') . "\n";
        $out .= "stripos('hello'): " . stripos($str, 'hello') . "\n";
        $out .= "strstr('World'): " . strstr($str, 'World') . "\n";
        $out .= "strchr('World'): " . strchr($str, 'World') . "\n";
        $out .= "str_replace('World', 'PHP', \$str): " . str_replace('World', 'PHP', $str) . "\n";
        $out .= "str_ireplace('hello', 'hi', \$str): " . str_ireplace('hello', 'hi', $str) . "\n";
        $out .= "explode(',', \$str): " . json_encode(explode(',', $str)) . "\n";
        $out .= "implode('-', ['a','b','c']): " . implode('-', ['a','b','c']) . "\n";
        $out .= "str_repeat('ab', 3): " . str_repeat('ab', 3) . "\n";
        $out .= "str_pad('test', 10, '_-'): " . str_pad('test', 10, '_-') . "\n";
        $out .= "str_pad('test', 10, '_-', STR_PAD_BOTH): " . str_pad('test', 10, '_-', STR_PAD_BOTH) . "\n";
        $out .= "str_split(\$str, 3): " . json_encode(str_split($str, 3)) . "\n";

        return $out;
    }
}

$lab = new StringFunctions();
echo $lab->process();

echo "\n=== String comparison ===\n";
echo "strcmp('abc', 'abc'): " . strcmp('abc', 'abc') . "\n";
echo "strcmp('abc', 'abd'): " . strcmp('abc', 'abd') . "\n";
echo "strcasecmp('ABC', 'abc'): " . strcasecmp('ABC', 'abc') . "\n";
echo "strnatcmp('2', '10'): " . strnatcmp('2', '10') . "\n";
echo "strnatcasecmp('A2', 'A10'): " . strnatcasecmp('A2', 'A10') . "\n";

echo "\n=== String trimming ===\n";
echo "trim('  hello  '): '" . trim("  hello  ") . "'\n";
echo "ltrim('  hello'): '" . ltrim("  hello") . "'\n";
echo "rtrim('hello  '): '" . rtrim("hello  ") . "'\n";
echo "trim('\\t\\ntest\\t\\n'): '" . trim("\t\ntest\t\n") . "'\n";

echo "\n=== String case ===\n";
echo "strtoupper('hello'): " . strtoupper('hello') . "\n";
echo "strtolower('HELLO'): " . strtolower('HELLO') . "\n";
echo "ucfirst('hello world'): " . ucfirst('hello world') . "\n";
echo "ucwords('hello world'): " . ucwords('hello world') . "\n";
echo "lcfirst('HELLO'): " . lcfirst('HELLO') . "\n";