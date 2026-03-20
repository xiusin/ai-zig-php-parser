<?php
class PhpDot {
    public static function __callStatic(string $name, array $arguments): mixed {
        return match($name) {
            'get' => $arguments[0][$arguments[1]] ?? null,
            'set' => $arguments[0][$arguments[1]] = $arguments[2],
            'has' => isset($arguments[0][$arguments[1]]),
            'forget' => $arguments[0] = array_diff_key($arguments[0], [$arguments[1] => true]),
            default => null
        };
    }
}

$data = ['name' => 'Tom', 'age' => 25];
echo PhpDot::get($data, 'name') . "\n";
echo PhpDot::has($data, 'age') ? 'true' : 'false' . "\n";
PhpDot::set($data, 'city', 'Beijing');
echo ($data['city'] ?? 'null') . "\n";
PhpDot::forget($data, 'age');
echo PhpDot::has($data, 'age') ? 'true' : 'false' . "\n";
echo "OK\n";
