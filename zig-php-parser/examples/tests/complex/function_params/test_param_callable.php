<?php
class Math {
    public function add($a, $b) {
        return $a + $b;
    }

    public static function multiply($a, $b) {
        return $a * $b;
    }
}

function execute(callable $func, ...$args) {
    return $func(...$args);
}

$math = new Math();
echo execute([$math, "add"], 5, 10) . "\n";
echo execute([Math::class, "multiply"], 5, 10) . "\n";
echo execute("sqrt", 16) . "\n";
