<?php
// Test 049: Heredoc, nowdoc, and complex string syntax
class StringSyntax {
    public function heredoc(): string {
        $name = "Test";
        $value = 42;

        $heredoc = <<<EOT
This is a heredoc string
With multiple lines
Name: $name
Value: $value
Expression: EOT;
        $heredoc .= ($value * 2);

        return $heredoc;
    }

    public function nowdoc(): string {
        $label = "label";

        $nowdoc = <<<'EOT'
This is a nowdoc string
No interpolation: \$label
Just literal text
EOT;

        return $nowdoc;
    }

    public function complexBraces(): string {
        $arr = ['key' => 'value'];
        $obj = new stdClass();
        $obj->prop = 100;

        $result = "Array: " . $arr['key'] . ", Object: " . $obj->prop;
        return $result;
    }

    public function offsetAccess(): string {
        $data = [
            'str' => 'hello',
            'int' => 42,
            'float' => 3.14,
            'array' => [1, 2, 3],
        ];

        $out = "";
        $out .= "Direct: " . $data['str'] . "\n";
        $out .= "Numeric: " . $data['int'] . "\n";

        $nested = ['a' => ['b' => ['c' => 'deep']]];
        $out .= "Nested: " . $nested['a']['b']['c'] . "\n";

        return $out;
    }
}

echo "=== Heredoc ===\n";
$lab = new StringSyntax();
echo $lab->heredoc();
echo "\n";

echo "=== Nowdoc ===\n";
echo $lab->nowdoc();
echo "\n";

echo "=== Complex braces ===\n";
echo $lab->complexBraces() . "\n";

echo "=== Offset access ===\n";
echo $lab->offsetAccess();

echo "=== Multiple braces ===\n";
$a = 1;
$b = 2;
$c = 3;
echo "Multiple: " . ($a + $b + $c) . "\n";

echo "=== Heredoc with indentation ===\n";
$code = <<<CODE
    function test() {
        echo "indented";
    }
CODE;
echo "Heredoc indented:\n$code\n";

echo "=== Complex nested ===\n";
class Nested {
    public array $data = ['x' => 10];
}
$n = new Nested();
echo "Object in string: " . $n->data['x'] . "\n";