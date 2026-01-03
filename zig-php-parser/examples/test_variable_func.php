<?php
$greet = function($name) {
    return "Hello, " . $name;
};

echo "Variable function test:\n";
echo $greet("World") . "\n";

$value = 10;
$incrementer = function() use ($value) {
    return $value + 1;
};

echo "Closure test:\n";
echo $incrementer() . "\n";
