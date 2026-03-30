<?php
// Test 066: Variable interpolation in strings
class Interpolation {
    public string $property = 'prop_value';
    public int $number = 42;
    public array $array = ['a' => 1, 'b' => 2];

    public function method(): string {
        return "method_result";
    }

    public function process(): string {
        $out = "";

        $local = "local_value";
        $out .= "Simple: $local\n";
        $out .= "With braces: {$local}\n";
        $out .= "Property: {$this->property}\n";
        $out .= "Number: {$this->number}\n";
        $out .= "Method: {$this->method()}\n";
        $out .= "Array access: {$this->array['a']}\n";

        $nested = ['key' => ['inner' => 'deep']];
        $out .= "Nested: {$nested['key']['inner']}\n";

        return $out;
    }
}

$obj = new Interpolation();
echo $obj->process();

echo "\n=== Complex interpolation ===\n";
$class = new stdClass();
$class->name = 'std';
$arr = ['x' => 10];

echo "Object: {$class->name}\n";
echo "Array direct: {$arr['x']}\n";

echo "\n=== Arithmetic in interpolation ===\n";
$a = 5;
$b = 10;
echo "Sum: {$a} + {$b} = " . ($a + $b) . "\n";

echo "\n=== Escape sequences ===\n";
echo "Escaped \\$notvar: \${notvar}\n";
echo "Backslash: \\\n";
echo "Tab: \t\n";

echo "\n=== Heredoc interpolation ===\n";
$heredoc = <<<EOT
Property: {$obj->property}
Method: {$obj->method()}
Array: {$obj->array['a']}
EOT;
echo $heredoc . "\n";