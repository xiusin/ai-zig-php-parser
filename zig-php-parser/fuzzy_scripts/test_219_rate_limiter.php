<?php
function rateLimiter(callable $fn, int $maxCalls, int $windowSeconds): callable {
    $calls = [];
    return function(...$args) use ($fn, $maxCalls, $windowSeconds, &$calls) {
        $now = time();
        $calls = array_filter($calls, fn($t) => $now - $t < $windowSeconds);

        if (count($calls) >= $maxCalls) {
            return "Rate limit exceeded";
        }

        $calls[] = $now;
        return $fn(...$args);
    };
}

$counter = 0;
$limited = rateLimiter(fn() => ++$counter, 3, 60);

for ($i = 0; $i < 5; $i++) {
    echo $limited() . "\n";
}
echo "OK\n";
