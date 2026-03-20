<?php
// Test 077: Exception hierarchy, custom exceptions
class CustomException extends Exception {
    public function __construct(
        string $message,
        private string $extra = ''
    ) {
        parent::__construct($message);
    }

    public function getExtra(): string {
        return $this->extra;
    }
}

class ChildException extends CustomException {}

function throwCustom(): void {
    throw new CustomException('Custom error', 'extra_data');
}

function throwChild(): void {
    throw new ChildException('Child error', 'child_extra');
}

echo "=== Exception hierarchy ===\n";
try {
    throw new Exception('Original');
} catch (CustomException $e) {
    echo "Caught as CustomException\n";
} catch (Exception $e) {
    echo "Caught as Exception: " . $e->getMessage() . "\n";
}

echo "\n=== Custom exception ===\n";
try {
    throwCustom();
} catch (CustomException $e) {
    echo "Message: " . $e->getMessage() . "\n";
    echo "Extra: " . $e->getExtra() . "\n";
    echo "Code: " . $e->getCode() . "\n";
}

echo "\n=== Rethrow ===\n";
try {
    try {
        throw new RuntimeException('Inner');
    } catch (RuntimeException $e) {
        throw new CustomException('Outer from: ' . $e->getMessage());
    }
} catch (CustomException $e) {
    echo "Caught rethrown: " . $e->getMessage() . "\n";
}

echo "\n=== Multiple catch ===\n";
$exceptions = [
    new RuntimeException('Runtime'),
    new InvalidArgumentException('Invalid'),
    new LogicException('Logic'),
    new CustomException('Custom'),
];

foreach ($exceptions as $e) {
    try {
        throw $e;
    } catch (CustomException $ce) {
        echo "CustomException: " . $ce->getMessage() . "\n";
    } catch (LogicException $le) {
        echo "LogicException: " . $le->getMessage() . "\n";
    } catch (RuntimeException $re) {
        echo "RuntimeException: " . $re->getMessage() . "\n";
    } catch (Exception $e) {
        echo "Exception: " . $e->getMessage() . "\n";
    }
}