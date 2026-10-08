<?php
class JsonDiff {
    public static function diff(mixed $a, mixed $b, string $path = ''): array {
        $changes = [];
        if (gettype($a) !== gettype($b)) {
            $changes[] = ['path' => $path, 'type' => 'type_change', 'from' => $a, 'to' => $b];
            return $changes;
        }
        if (is_array($a)) {
            $keys = array_unique(array_merge(array_keys($a), array_keys($b)));
            foreach ($keys as $key) {
                $childPath = $path === '' ? "$key" : "$path.$key";
                if (!array_key_exists($key, $a)) {
                    $changes[] = ['path' => $childPath, 'type' => 'added', 'value' => $b[$key]];
                } elseif (!array_key_exists($key, $b)) {
                    $changes[] = ['path' => $childPath, 'type' => 'removed', 'value' => $a[$key]];
                } elseif ($a[$key] !== $b[$key]) {
                    if (is_array($a[$key]) && is_array($b[$key])) {
                        $changes = array_merge($changes, self::diff($a[$key], $b[$key], $childPath));
                    } else {
                        $changes[] = ['path' => $childPath, 'type' => 'changed', 'from' => $a[$key], 'to' => $b[$key]];
                    }
                }
            }
        } elseif ($a !== $b) {
            $changes[] = ['path' => $path, 'type' => 'changed', 'from' => $a, 'to' => $b];
        }
        return $changes;
    }
}
$d1 = ["name" => "Alice", "age" => 30, "city" => "NYC", "scores" => [90, 85]];
$d2 = ["name" => "Alice", "age" => 31, "city" => "LA", "scores" => [90, 85, 95], "email" => "a@b.com"];
$diff = JsonDiff::diff($d1, $d2);
var_dump($diff);
foreach ($diff as $d) {
    echo "  {$d['path']}: {$d['type']}";
    if (isset($d['from'])) echo " from=" . json_encode($d['from']);
    if (isset($d['to'])) echo " to=" . json_encode($d['to']);
    if (isset($d['value'])) echo " value=" . json_encode($d['value']);
    echo "\n";
}
