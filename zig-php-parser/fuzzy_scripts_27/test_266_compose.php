<?php
function composeRight(callable ...$fns): callable {
    return function($arg) use ($fns) {
        $result = $arg;
        for ($i = count($fns) - 1; $i >= 0; $i--) {
            $result = $fns[$i]($result);
        }
        return $result;
    };
}

function trace(string $label, callable $fn): callable {
    return function($value) use ($label, $fn) {
        echo "$label: $value\n";
        return $fn($value);
    };
}

$process = composeRight(
    fn($x) => $x + 10,
    fn($x) => $x * 2,
    fn($x) => $x - 5
);

echo $process(10) . "\n";

$traced = trace("Value", fn($x) => $x * 2);
echo $traced(21) . "\n";
echo "OK\n";
