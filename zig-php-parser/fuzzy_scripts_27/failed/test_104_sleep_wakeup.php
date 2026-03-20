<?php
// Test 104: Object serialization, __sleep, __wakeup
class SleepWakeup {
    public string $name;
    public int $value;
    private string $secret;
    private array $dynamic = [];

    public function __construct() {
        $this->name = 'test';
        $this->value = 42;
        $this->secret = 'hidden';
        $this->dynamic = ['computed' => 'value'];
    }

    public function __sleep(): array {
        return ['name', 'value'];
    }

    public function __wakeup(): void {
        $this->secret = 'revealed_after_wakeup';
    }

    public function describe(): string {
        return "name={$this->name}, value={$this->value}, secret={$this->secret}";
    }
}

echo "=== __sleep/__wakeup ===\n";
$obj = new SleepWakeup();
echo "Before serialize: " . $obj->describe() . "\n";

$serialized = serialize($obj);
echo "Serialized: " . strlen($serialized) . " bytes\n";

$unserialized = unserialize($serialized);
echo "After unserialize: " . $unserialized->describe() . "\n";

echo "\n=== Serialize with dynamic ===\n";
$obj2 = new SleepWakeup();
$serialized2 = serialize($obj2);
$unserialized2 = unserialize($serialized2);
echo "Unserialized2: " . $unserialized2->describe() . "\n";