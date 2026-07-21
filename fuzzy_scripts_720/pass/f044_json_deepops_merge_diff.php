<?php
// 极度混搭: JSON深度操作 + 嵌套合并 + 路径访问 + 差异对比 + Schema验证
echo "=== f044: JSON Deep Ops + Merge + Diff + Schema ===\n";

class JsonTools {
    public static function deepGet(array $data, string $path, string $sep = '.'): mixed {
        $keys = explode($sep, $path);
        $current = $data;
        foreach ($keys as $key) {
            if (!is_array($current) || !array_key_exists($key, $current)) return null;
            $current = $current[$key];
        }
        return $current;
    }

    public static function deepSet(array &$data, string $path, mixed $value, string $sep = '.'): void {
        $keys = explode($sep, $path);
        $ref = &$data;
        foreach ($keys as $i => $key) {
            if (!isset($ref[$key])) $ref[$key] = [];
            $ref = &$ref[$key];
        }
        $ref = $value;
    }

    public static function deepHas(array $data, string $path, string $sep = '.'): bool {
        return self::deepGet($data, $path, $sep) !== null;
    }

    public static function deepMerge(array $base, array $override): array {
        $result = $base;
        foreach ($override as $key => $value) {
            if (is_array($value) && isset($result[$key]) && is_array($result[$key])) {
                $result[$key] = self::deepMerge($result[$key], $value);
            } else {
                $result[$key] = $value;
            }
        }
        return $result;
    }

    public static function deepDiff(array $a, array $b, string $prefix = ''): array {
        $diffs = [];
        $allKeys = array_unique(array_merge(array_keys($a), array_keys($b)));
        foreach ($allKeys as $key) {
            $path = $prefix === '' ? $key : "$prefix.$key";
            $inA = array_key_exists($key, $a);
            $inB = array_key_exists($key, $b);
            if ($inA && !$inB) {
                $diffs[] = ['path' => $path, 'type' => 'removed', 'old' => $a[$key]];
            } elseif (!$inA && $inB) {
                $diffs[] = ['path' => $path, 'type' => 'added', 'new' => $b[$key]];
            } elseif (is_array($a[$key]) && is_array($b[$key])) {
                $diffs = array_merge($diffs, self::deepDiff($a[$key], $b[$key], $path));
            } elseif ($a[$key] !== $b[$key]) {
                $diffs[] = ['path' => $path, 'type' => 'changed', 'old' => $a[$key], 'new' => $b[$key]];
            }
        }
        return $diffs;
    }

    public static function flatten(array $data, string $prefix = ''): array {
        $result = [];
        foreach ($data as $key => $value) {
            $path = $prefix === '' ? $key : "$prefix.$key";
            if (is_array($value) && !empty($value) && !array_is_list($value)) {
                $result = array_merge($result, self::flatten($value, $path));
            } else {
                $result[$path] = $value;
            }
        }
        return $result;
    }

    public static function unflatten(array $flat): array {
        $result = [];
        foreach ($flat as $path => $value) {
            self::deepSet($result, $path, $value);
        }
        return $result;
    }

    public static function validateSchema(array $data, array $schema): array {
        $errors = [];
        $type = $schema['type'] ?? 'any';
        if ($type === 'object' && !is_array($data)) {
            return ['Expected object'];
        }
        $properties = $schema['properties'] ?? [];
        $required = $schema['required'] ?? [];
        foreach ($required as $field) {
            if (!array_key_exists($field, $data)) {
                $errors[] = "Missing required field: $field";
            }
        }
        foreach ($properties as $field => $rules) {
            if (!array_key_exists($field, $data)) continue;
            $value = $data[$field];
            $expectedType = $rules['type'] ?? 'any';
            $actualType = gettype($value);
            $typeMap = ['integer' => 'integer', 'string' => 'string', 'boolean' => 'boolean', 'number' => 'double', 'array' => 'array', 'object' => 'array'];
            if ($expectedType !== 'any' && ($typeMap[$expectedType] ?? $expectedType) !== $actualType) {
                $errors[] = "Field '$field': expected $expectedType, got $actualType";
            }
            if (isset($rules['min']) && $value < $rules['min']) {
                $errors[] = "Field '$field': value $value < min {$rules['min']}";
            }
            if (isset($rules['max']) && $value > $rules['max']) {
                $errors[] = "Field '$field': value $value > max {$rules['max']}";
            }
            if (isset($rules['pattern']) && is_string($value)) {
                if (!preg_match($rules['pattern'], $value)) {
                    $errors[] = "Field '$field': does not match pattern {$rules['pattern']}";
                }
            }
        }
        return $errors;
    }
}

// 测试
$data = [
    'user' => ['name' => 'Alice', 'age' => 30, 'roles' => ['admin', 'editor']],
    'settings' => ['theme' => 'dark', 'lang' => 'en'],
];

echo "deepGet(user.name): " . JsonTools::deepGet($data, 'user.name') . "\n";
echo "deepGet(user.roles.0): " . JsonTools::deepGet($data, 'user.roles.0') . "\n";
echo "deepGet(settings.theme): " . JsonTools::deepGet($data, 'settings.theme') . "\n";
echo "deepGet(missing.path): " . var_export(JsonTools::deepGet($data, 'missing.path'), true) . "\n";
echo "deepHas(user.name): " . var_export(JsonTools::deepHas($data, 'user.name'), true) . "\n";

JsonTools::deepSet($data, 'user.email', 'alice@test.com');
echo "After set user.email: " . json_encode($data['user']) . "\n";

// Deep merge
$base = ['a' => 1, 'b' => ['c' => 2, 'd' => 3]];
$override = ['b' => ['d' => 4, 'e' => 5], 'f' => 6];
$merged = JsonTools::deepMerge($base, $override);
echo "Merge: " . json_encode($merged) . "\n";

// Diff
$a = ['name' => 'Alice', 'age' => 30, 'city' => 'NYC', 'tags' => ['a','b']];
$b = ['name' => 'Bob', 'age' => 30, 'tags' => ['a','c'], 'email' => 'bob@test.com'];
$diffs = JsonTools::deepDiff($a, $b);
echo "\nDiffs:\n";
foreach ($diffs as $d) {
    echo "  {$d['path']}: {$d['type']}";
    if (isset($d['old'])) echo " old=" . json_encode($d['old']);
    if (isset($d['new'])) echo " new=" . json_encode($d['new']);
    echo "\n";
}

// Flatten / Unflatten
$flat = JsonTools::flatten($data);
echo "\nFlattened:\n";
foreach ($flat as $path => $val) echo "  $path = " . json_encode($val) . "\n";

$restored = JsonTools::unflatten($flat);
echo "Unflatten matches: " . var_export($restored == $data, true) . "\n";

// Schema 验证
$schema = [
    'type' => 'object',
    'required' => ['name', 'age'],
    'properties' => [
        'name' => ['type' => 'string'],
        'age' => ['type' => 'integer', 'min' => 0, 'max' => 150],
        'email' => ['type' => 'string', 'pattern' => '/^[^@]+@[^@]+$/'],
    ],
];

$valid = ['name' => 'Alice', 'age' => 30, 'email' => 'alice@test.com'];
$errors = JsonTools::validateSchema($valid, $schema);
echo "\nValid data errors: " . (empty($errors) ? 'none' : implode('; ', $errors)) . "\n";

$invalid = ['name' => 'Bob', 'email' => 'not-an-email'];
$errors2 = JsonTools::validateSchema($invalid, $schema);
echo "Invalid data errors: " . implode('; ', $errors2) . "\n";

echo "=== f044 Done ===\n";
