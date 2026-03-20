<?php
// Test 095: Return types
class ReturnTypes {
    public function returnsInt(): int {
        return 42;
    }

    public function returnsString(): string {
        return "string";
    }

    public function returnsArray(): array {
        return [1, 2, 3];
    }

    public function returnsObject(): object {
        return new stdClass();
    }

    public function returnsNull(): ?string {
        return null;
    }

    public function returnsVoid(): void {
        $result = 1 + 2;
    }

    public function returnsNever(): void {
        throw new RuntimeException("Never returns");
    }

    public function returnsMixed(): mixed {
        return "anything";
    }

    public function returnsUnion(): int|string {
        return random_int(0, 1) ? 1 : "one";
    }
}

echo "=== Return types ===\n";
$obj = new ReturnTypes();
echo "returnsInt: " . $obj->returnsInt() . "\n";
echo "returnsString: " . $obj->returnsString() . "\n";
echo "returnsArray: " . json_encode($obj->returnsArray()) . "\n";
echo "returnsObject class: " . get_class($obj->returnsObject()) . "\n";
echo "returnsNull: " . ($obj->returnsNull() ?? 'null') . "\n";
echo "returnsVoid: " . $obj->returnsVoid() . "\n";
echo "returnsMixed: " . $obj->returnsMixed() . "\n";

$union = $obj->returnsUnion();
echo "returnsUnion type: " . gettype($union) . ", value: $union\n";

echo "\n=== Never return ===\n";
try {
    $obj->returnsNever();
} catch (RuntimeException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}