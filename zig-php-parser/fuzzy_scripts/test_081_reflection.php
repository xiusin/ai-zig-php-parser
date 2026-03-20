<?php
// Test ReflectionFunction with named functions
function add($a, $b, $c = 0) {
    return $a + $b + $c;
}

function greet($name) {
    return "Hello, $name!";
}

$rf = new ReflectionFunction('add');
echo "Name: " . $rf->getName() . "\n";
echo "Params: " . $rf->getNumberOfParameters() . "\n";
echo "Required: " . $rf->getNumberOfRequiredParameters() . "\n";

$rf2 = new ReflectionFunction('greet');
echo "Name: " . $rf2->getName() . "\n";
echo "Params: " . $rf2->getNumberOfParameters() . "\n";
echo "Required: " . $rf2->getNumberOfRequiredParameters() . "\n";

// Test ReflectionFunction with closure
$closure = function($x, $y) { return $x + $y; };
$rf3 = new ReflectionFunction($closure);
echo "Closure Params: " . $rf3->getNumberOfParameters() . "\n";
echo "Closure Required: " . $rf3->getNumberOfRequiredParameters() . "\n";
?>
