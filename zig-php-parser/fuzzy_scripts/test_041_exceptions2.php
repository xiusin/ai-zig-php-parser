<?php
// Test 041: Multiple catch, nested try-catch, and finally
class ExceptionLab2 {
    public function division(float $a, float $b): float {
        if ($b == 0) {
            throw new DivisionByZeroError("Cannot divide by zero");
        }
        return $a / $b;
    }

    public function parseJson(string $json): array {
        $result = json_decode($json, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new JsonException(json_last_error_msg());
        }
        return $result;
    }

    public function process(): string {
        $out = "";

        try {
            $out .= "Try block 1\n";
            throw new RuntimeException("First exception");
        } catch (RuntimeException $e) {
            $out .= "Caught RuntimeException: " . $e->getMessage() . "\n";
        }

        try {
            $out .= "Try block 2\n";
            throw new InvalidArgumentException("Invalid argument");
        } catch (RuntimeException $e) {
            $out .= "Caught as RuntimeException: " . $e->getMessage() . "\n";
        } catch (InvalidArgumentException $e) {
            $out .= "Caught InvalidArgumentException: " . $e->getMessage() . "\n";
        }

        try {
            try {
                $out .= "Nested try block\n";
                throw new LogicException("Inner exception");
            } finally {
                $out .= "Inner finally\n";
            }
        } catch (LogicException $e) {
            $out .= "Outer caught: " . $e->getMessage() . "\n";
        }

        try {
            $result = $this->division(10, 0);
        } catch (DivisionByZeroError $e) {
            $out .= "Division error: " . $e->getMessage() . "\n";
        } catch (Throwable $e) {
            $out .= "General error: " . $e->getMessage() . "\n";
        } finally {
            $out .= "Division try-finally executed\n";
        }

        try {
            $this->parseJson('invalid json{');
        } catch (JsonException $e) {
            $out .= "JSON error: " . $e->getMessage() . "\n";
        }

        return $out;
    }

    public function multiCatch(): string {
        $out = "";

        $exceptions = [
            new RuntimeException("Runtime"),
            new InvalidArgumentException("Invalid"),
            new LogicException("Logic"),
            new DomainException("Domain"),
        ];

        foreach ($exceptions as $e) {
            try {
                throw $e;
            } catch (RuntimeException | InvalidArgumentException $ex) {
                $out .= "Caught Runtime or Invalid: " . get_class($ex) . "\n";
            } catch (LogicException | DomainException $ex) {
                $out .= "Caught Logic or Domain: " . get_class($ex) . "\n";
            } catch (Throwable $t) {
                $out .= "Caught other: " . get_class($t) . "\n";
            }
        }

        return $out;
    }
}

echo "=== Exception Lab 2 ===\n";
$lab = new ExceptionLab2();
echo $lab->process();

echo "\n=== Multi-catch ===\n";
echo $lab->multiCatch();

echo "\n=== Finally in loops ===\n";
for ($i = 0; $i < 3; $i++) {
    try {
        if ($i === 1) {
            throw new Exception("Loop exception at $i");
        }
        echo "Iteration $i\n";
    } catch (Exception $e) {
        echo "Caught in loop: " . $e->getMessage() . "\n";
    } finally {
        echo "Finally in iteration $i\n";
    }
}