<?php
// Test 170: Object to array conversion
class ToArray {
    public string $a = 'value_a';
    public int $b = 42;
    protected string $c = 'protected';

    public function toArray(): array {
        return (array)$this;
    }
}

$obj = new ToArray();
$arr = (array)$obj;
echo "As array: " . json_encode($arr) . "\n";