<?php
// Test 057: isset, empty, unset with various types
class IssetLab {
    private array $data = [];

    public function set(string $key, mixed $value): void {
        $this->data[$key] = $value;
    }

    public function test(): string {
        $out = "";

        $this->data = [
            'null' => null,
            'zero' => 0,
            'empty_string' => '',
            'false' => false,
            'empty_array' => [],
            'string' => 'value',
        ];

        foreach ($this->data as $key => $value) {
            $out .= "$key - isset: " . (isset($this->data[$key]) ? 'yes' : 'no');
            $out .= ", empty: " . (empty($this->data[$key]) ? 'yes' : 'no') . "\n";
        }

        return $out;
    }
}

$lab = new IssetLab();
echo $lab->test();

echo "\n=== Direct isset/empty ===\n";
$null = null;
$zero = 0;
$str = '';
$arr = [];
$obj = new stdClass();

echo "isset(\$null): " . (isset($null) ? 'yes' : 'no') . "\n";
echo "empty(\$null): " . (empty($null) ? 'yes' : 'no') . "\n";
echo "isset(\$zero): " . (isset($zero) ? 'yes' : 'no') . "\n";
echo "empty(\$zero): " . (empty($zero) ? 'yes' : 'no') . "\n";
echo "isset(\$str): " . (isset($str) ? 'yes' : 'no') . "\n";
echo "empty(\$str): " . (empty($str) ? 'yes' : 'no') . "\n";
echo "isset(\$arr): " . (isset($arr) ? 'yes' : 'no') . "\n";
echo "empty(\$arr): " . (empty($arr) ? 'yes' : 'no') . "\n";
echo "isset(\$obj): " . (isset($obj) ? 'yes' : 'no') . "\n";
echo "empty(\$obj): " . (empty($obj) ? 'yes' : 'no') . "\n";

echo "\n=== Unset ===\n";
$toUnset = ['a' => 1, 'b' => 2, 'c' => 3];
echo "Before unset: " . json_encode($toUnset) . "\n";
unset($toUnset['b']);
echo "After unset(b): " . json_encode($toUnset) . "\n";

echo "\n=== isset with array keys ===\n";
$arr = ['key' => 'value'];
echo "isset(\$arr['key']): " . (isset($arr['key']) ? 'yes' : 'no') . "\n";
echo "isset(\$arr['missing']): " . (isset($arr['missing']) ? 'yes' : 'no') . "\n";