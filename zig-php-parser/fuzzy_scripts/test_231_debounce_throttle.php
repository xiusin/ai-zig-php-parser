<?php
function debounce(callable $fn, int $ms): callable {
    $timeout = null;
    return function(...$args) use ($fn, $ms, &$timeout) {
        if ($timeout !== null) {
            return;
        }
        $timeout = true;
        $result = $fn(...$args);
        usleep($ms * 1000);
        $timeout = null;
        return $result;
    };
}

function throttle(callable $fn, int $ms): callable {
    $lastCall = 0;
    return function(...$args) use ($fn, $ms, &$lastCall) {
        $now = microtime(true) * 1000;
        if ($now - $lastCall < $ms) {
            return;
        }
        $lastCall = $now;
        return $fn(...$args);
    };
}

$counter = 0;
$debouncedFn = debounce(function() use (&$counter) { return ++$counter; }, 10);
$throttledFn = throttle(function() use (&$counter) { return ++$counter; }, 10);

echo $debouncedFn() . "\n";
echo $throttledFn() . "\n";
echo $throttledFn() . "\n";
echo $debouncedFn() . "\n";
echo "OK\n";
