<?php
function retry(callable $fn, int $maxAttempts = 3, int $delayMs = 100): mixed {
    $attempts = 0;
    $lastException = null;

    while ($attempts < $maxAttempts) {
        try {
            return $fn();
        } catch (Exception $e) {
            $lastException = $e;
            $attempts++;
            if ($attempts < $maxAttempts) {
                usleep($delayMs * 1000);
            }
        }
    }

    throw $lastException;
}

$counter = 0;
try {
    retry(function() use (&$counter) {
        $counter++;
        if ($counter < 3) {
            throw new Exception("Attempt $counter failed");
        }
        return "Success on attempt $counter";
    });
} catch (Exception $e) {
    echo "Final failure: " . $e->getMessage() . "\n";
}
echo "OK\n";
