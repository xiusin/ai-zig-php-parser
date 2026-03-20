<?php
// === ReflectionFunction ===
function add($a, $b, $c = 0) {
    return $a + $b + $c;
}

function greet($name) {
    return "Hello, $name!";
}

// Test getName / getNumberOfParameters / getNumberOfRequiredParameters
$rf = new ReflectionFunction('add');
echo "RF Name: " . $rf->getName() . "\n";
echo "RF Params: " . $rf->getNumberOfParameters() . "\n";
echo "RF Required: " . $rf->getNumberOfRequiredParameters() . "\n";

// Test invoke
$result = $rf->invoke(1, 2, 3);
echo "RF invoke(1,2,3): " . $result . "\n";

// Test isClosure / isUserDefined / isInternal
$ic = $rf->isClosure();
echo "RF isClosure: " . ($ic ? "true" : "false") . "\n";
$ud = $rf->isUserDefined();
echo "RF isUserDefined: " . ($ud ? "true" : "false") . "\n";
$ii = $rf->isInternal();
echo "RF isInternal: " . ($ii ? "true" : "false") . "\n";

// Test closure reflection
$closure = function($x, $y) { return $x * $y; };
$rf2 = new ReflectionFunction($closure);
echo "Closure Params: " . $rf2->getNumberOfParameters() . "\n";
echo "Closure Required: " . $rf2->getNumberOfRequiredParameters() . "\n";
$ic2 = $rf2->isClosure();
echo "Closure isClosure: " . ($ic2 ? "true" : "false") . "\n";

// Test closure invoke
$result2 = $rf2->invoke(3, 4);
echo "Closure invoke(3,4): " . $result2 . "\n";

// Test getParameters
$params = $rf->getParameters();
echo "RF param count from array: " . count($params) . "\n";

// === ReflectionFunction greet ===
$rf3 = new ReflectionFunction('greet');
echo "RF3 invoke: " . $rf3->invoke("World") . "\n";
?>
