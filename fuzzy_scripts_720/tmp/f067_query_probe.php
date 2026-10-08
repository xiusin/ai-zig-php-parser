<?php
class JsonPath {
    public static function query(mixed $data, string $path): mixed {
        $parts = explode('.', $path);
        $current = $data;
        foreach ($parts as $part) {
            if (is_array($current)) {
                if (is_int($part) || ctype_digit($part)) {
                    $idx = (int)$part;
                    if (!isset($current[$idx])) return null;
                    $current = $current[$idx];
                } else {
                    if (!isset($current[$part])) return null;
                    $current = $current[$part];
                }
            } else {
                return null;
            }
        }
        return $current;
    }
}
$data = ["name" => "Alice", "age" => 30, "scores" => [95, 87, 92], "meta" => ["city" => "NYC"]];
echo "name: " . JsonPath::query($data, 'name') . "\n";
echo "age: " . JsonPath::query($data, 'age') . "\n";
echo "scores.1: " . JsonPath::query($data, 'scores.1') . "\n";
echo "meta.city: " . JsonPath::query($data, 'meta.city') . "\n";
echo "missing: " . var_export(JsonPath::query($data, 'a.b'), true) . "\n";
