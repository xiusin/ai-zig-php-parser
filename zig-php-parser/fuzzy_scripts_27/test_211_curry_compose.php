<?php
function curriedAdd(int $a): callable {
    return function(int $b) use ($a): int {
        return $a + $b;
    };
}

function curriedMultiply(int $a): callable {
    return function(int $b) use ($a): int {
        return $a * $b;
    };
}

function compose(callable ...$fns): callable {
    return function($x) use ($fns) {
        foreach ($fns as $fn) {
            $x = $fn($x);
        }
        return $x;
    };
}

$addFive = curriedAdd(5);
$multiplyThree = curriedMultiply(3);

echo $addFive(10) . "\n";
echo $multiplyThree(7) . "\n";

$compute = compose($addFive, $multiplyThree);
echo $compute(4) . "\n";

$compute2 = compose(
    fn($x) => $x * 2,
    fn($x) => $x + 10,
    fn($x) => $x / 2
);
echo $compute2(6) . "\n";
echo "OK\n";
