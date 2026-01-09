<?php
function compose(...$functions) {
    return function($value) use ($functions) {
        $result = $value;
        foreach ($functions as $function) {
            $result = $function($result);
        }
        return $result;
    };
}

$f1 = fn($x) => $x + 1;
$f2 = fn($x) => $x * 2;
$f3 = fn($x) => $x ** 2;

$composed = compose($f1, $f2, $f3);

echo "compose(f1, f2, f3)(5) = " . $composed(5) . "\n";
echo "Manual: f3(f2(f1(5))) = " . $f3($f2($f1(5))) . "\n";
