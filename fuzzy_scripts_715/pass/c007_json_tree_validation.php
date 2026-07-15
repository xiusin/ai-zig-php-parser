<?php
// 极度混搭: JSON深度解析 + 递归树遍历 + 数据验证 + 类型映射 + 序列化
echo "=== c007: JSON Deep Parse + Tree Traversal + Validation ===\n\n";

class JsonValidator {
    private array $errors = [];
    private array $schema;

    public function __construct(array $schema) {
        $this->schema = $schema;
    }

    public function validate(mixed $data, string $path = '$'): bool {
        $valid = true;
        $type = $this->schema['type'] ?? 'any';

        if (!$this->checkType($data, $type)) {
            $this->errors[] = "$path: expected $type, got " . gettype($data);
            return false;
        }

        if ($type === 'object' && isset($this->schema['properties'])) {
            if (!is_array($data)) {
                $this->errors[] = "$path: not an array/object";
                return false;
            }
            foreach ($this->schema['properties'] as $key => $subSchema) {
                if (isset($data[$key])) {
                    $sub = new self($subSchema);
                    if (!$sub->validate($data[$key], "$path.$key")) {
                        $this->errors = array_merge($this->errors, $sub->errors);
                        $valid = false;
                    }
                } elseif (($subSchema['required'] ?? false)) {
                    $this->errors[] = "$path.$key: required field missing";
                    $valid = false;
                }
            }
        }

        if ($type === 'array' && isset($this->schema['items'])) {
            foreach ($data as $i => $item) {
                $sub = new self($this->schema['items']);
                if (!$sub->validate($item, "$path[$i]")) {
                    $this->errors = array_merge($this->errors, $sub->errors);
                    $valid = false;
                }
            }
        }

        if (isset($this->schema['enum'])) {
            if (!in_array($data, $this->schema['enum'], true)) {
                $this->errors[] = "$path: value not in enum [" . implode(",", array_map(fn($v) => (string)$v, $this->schema['enum'])) . "]";
                $valid = false;
            }
        }

        if (isset($this->schema['min']) && is_numeric($data)) {
            if ($data < $this->schema['min']) {
                $this->errors[] = "$path: value $data < min {$this->schema['min']}";
                $valid = false;
            }
        }

        if (isset($this->schema['max']) && is_numeric($data)) {
            if ($data > $this->schema['max']) {
                $this->errors[] = "$path: value $data > max {$this->schema['max']}";
                $valid = false;
            }
        }

        if (isset($this->schema['pattern']) && is_string($data)) {
            if (!preg_match('/' . $this->schema['pattern'] . '/', $data)) {
                $this->errors[] = "$path: string '$data' does not match pattern {$this->schema['pattern']}";
                $valid = false;
            }
        }

        return $valid;
    }

    private function checkType(mixed $data, string $type): bool {
        return match($type) {
            'string' => is_string($data),
            'integer' => is_int($data),
            'number' => is_int($data) || is_float($data),
            'boolean' => is_bool($data),
            'array' => is_array($data) && array_is_list($data),
            'object' => is_array($data) && !array_is_list($data) || (is_array($data) && empty($data)),
            'null' => is_null($data),
            'any' => true,
            default => true,
        };
    }

    public function getErrors(): array {
        return $this->errors;
    }
}

class TreeNode {
    public mixed $value;
    public array $children = [];

    public function __construct(mixed $value) {
        $this->value = $value;
    }

    public function addChild(TreeNode $node): self {
        $this->children[] = $node;
        return $this;
    }

    public function depth(): int {
        if (empty($this->children)) return 1;
        return 1 + max(array_map(fn($c) => $c->depth(), $this->children));
    }

    public function count(): int {
        $total = 1;
        foreach ($this->children as $child) {
            $total += $child->count();
        }
        return $total;
    }

    public function traverse(callable $fn, int $depth = 0): void {
        $fn($this, $depth);
        foreach ($this->children as $child) {
            $child->traverse($fn, $depth + 1);
        }
    }

    public function find(mixed $target): ?TreeNode {
        if ($this->value === $target) return $this;
        foreach ($this->children as $child) {
            $found = $child->find($target);
            if ($found !== null) return $found;
        }
        return null;
    }

    public function toArray(): array {
        $result = ['value' => $this->value];
        if (!empty($this->children)) {
            $result['children'] = array_map(fn($c) => $c->toArray(), $this->children);
        }
        return $result;
    }

    public static function fromArray(array $data): self {
        $node = new self($data['value']);
        foreach ($data['children'] ?? [] as $childData) {
            $node->addChild(self::fromArray($childData));
        }
        return $node;
    }
}

// === 测试 ===

// 1. JSON 编码/解码循环
$data = [
    'name' => 'TestObject',
    'version' => 3,
    'active' => true,
    'tags' => ['php', 'aot', 'test'],
    'nested' => [
        'deep' => [
            'value' => 42,
            'list' => [1, 2, 3]
        ]
    ]
];

$json = json_encode($data);
echo "Encoded: $json\n";
$decoded = json_decode($json, true);
echo "Roundtrip: " . ($data === $decoded ? "OK" : "FAIL") . "\n";

// 2. JSON Schema 验证
echo "\n--- Schema Validation ---\n";
$schema = [
    'type' => 'object',
    'properties' => [
        'name' => ['type' => 'string', 'required' => true, 'min' => 1],
        'version' => ['type' => 'integer', 'required' => true, 'min' => 0, 'max' => 100],
        'active' => ['type' => 'boolean'],
        'tags' => [
            'type' => 'array',
            'items' => ['type' => 'string', 'min' => 1],
        ],
    ],
];

$validator = new JsonValidator($schema);
$valid = $validator->validate($decoded);
echo "Valid: " . var_export($valid, true) . "\n";
if (!$valid) {
    foreach ($validator->getErrors() as $err) {
        echo "  Error: $err\n";
    }
}

// Invalid data
$invalidData = [
    'name' => '',
    'version' => 150,
    'tags' => [''],
];
$validator2 = new JsonValidator($schema);
$valid2 = $validator2->validate($invalidData);
echo "Invalid data valid: " . var_export($valid2, true) . "\n";
foreach ($validator2->getErrors() as $err) {
    echo "  Error: $err\n";
}

// 3. 树结构操作
echo "\n--- Tree Operations ---\n";
$tree = TreeNode::fromArray([
    'value' => 'root',
    'children' => [
        ['value' => 'A', 'children' => [
            ['value' => 'A1'],
            ['value' => 'A2', 'children' => [
                ['value' => 'A2a'],
            ]],
        ]],
        ['value' => 'B', 'children' => [
            ['value' => 'B1'],
            ['value' => 'B2'],
        ]],
        ['value' => 'C'],
    ],
]);

echo "Depth: " . $tree->depth() . "\n";
echo "Count: " . $tree->count() . "\n";

echo "Traversal:\n";
$tree->traverse(function($node, $depth) {
    echo str_repeat("  ", $depth) . "- {$node->value}\n";
});

$found = $tree->find('A2a');
echo "Found A2a: " . ($found ? "YES" : "NO") . "\n";

$notFound = $tree->find('XYZ');
echo "Found XYZ: " . ($notFound ? "YES" : "NO") . "\n";

// 4. JSON 转树再转回
$treeJson = json_encode($tree->toArray());
echo "Tree JSON: $treeJson\n";
$treeRestored = TreeNode::fromArray(json_decode($treeJson, true));
echo "Restored depth: " . $treeRestored->depth() . "\n";
echo "Restored count: " . $treeRestored->count() . "\n";

// 5. 复杂嵌套数据操作
echo "\n--- Complex Nested Data ---\n";
$config = [
    'database' => [
        'primary' => ['host' => 'localhost', 'port' => 3306],
        'replica' => ['host' => 'replica1', 'port' => 3307],
    ],
    'cache' => [
        'redis' => ['host' => 'localhost', 'port' => 6379, 'db' => 0],
        'memory' => ['limit' => 128],
    ],
    'logging' => ['level' => 'debug', 'file' => '/var/log/app.log'],
];

function flattenKeys(array $arr, string $prefix = ''): array {
    $result = [];
    foreach ($arr as $key => $val) {
        $fullKey = $prefix === '' ? $key : "$prefix.$key";
        if (is_array($val) && !empty($val)) {
            $result = array_merge($result, flattenKeys($val, $fullKey));
        } else {
            $result[$fullKey] = $val;
        }
    }
    return $result;
}

$flat = flattenKeys($config);
ksort($flat);
foreach ($flat as $k => $v) {
    echo "  $k = $v\n";
}

// 6. JSON 边界条件
echo "\n--- JSON Edge Cases ---\n";
$edgeCases = [
    null,
    true,
    false,
    0,
    "",
    [],
    (object)[],
    3.14159,
    "中文测试",
    [1, "two", 3.0, true, null],
];

foreach ($edgeCases as $i => $case) {
    $enc = json_encode($case);
    $dec = json_decode($enc, true);
    $typeMatch = gettype($case) === gettype($dec);
    echo "  [$i] " . str_pad(gettype($case), 8) . " -> $enc" . ($typeMatch ? " OK" : " TYPE_DIFF") . "\n";
}

echo "\n=== c007 Done ===\n";
