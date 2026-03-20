<?php
// Test 145: Heredoc with expressions
$name = "World";
$value = 42;

echo "=== Heredoc ===\n";
$heredoc = <<<EOT
Hello, $name!
Value: $value
Expression: EOT;
$heredoc .= ($value * 2);
echo $heredoc . "\n";

echo "\n=== Nowdoc ===\n";
$nowdoc = <<<'EOT'
Hello, $name
No interpolation here
EOT;
echo $nowdoc . "\n";

echo "\n=== Heredoc with indentation ===\n";
$indented = <<<INDENT
    Indented content
    With value
INDENT;
echo $indented . "\n";