<?php
class Immutable {
    private $data;

    public function __construct($data) {
        $this->data = $data;
    }

    public function with($key, $value) {
        $new = clone $this;
        $new->data[$key] = $value;
        return $new;
    }

    public function get($key) {
        return $this->data[$key] ?? null;
    }
}

$original = new Immutable(["a" => 1, "b" => 2]);
$modified = $original->with("b", 200);

echo "Original b: " . $original->get("b") . "\n";
echo "Modified b: " . $modified->get("b") . "\n";
