<?php
// 极度混搭: 序列化/反序列化 + 对象图 + 循环引用检测 + 版本迁移
echo "=== c027: Serializer + ObjectGraph + CircularRef + Migration ===\n\n";

class ObjectSerializer {
    private array $objectMap = [];
    private array $serialized = [];
    private int $nextId = 1;

    public function serialize(mixed $value): string {
        $this->objectMap = [];
        $this->nextId = 1;
        $data = $this->serializeValue($value);
        return json_encode($data);
    }

    private function serializeValue(mixed $value): mixed {
        if (is_null($value)) return ['t' => 'null'];
        if (is_bool($value)) return ['t' => 'bool', 'v' => $value];
        if (is_int($value)) return ['t' => 'int', 'v' => $value];
        if (is_float($value)) return ['t' => 'float', 'v' => $value];
        if (is_string($value)) return ['t' => 'string', 'v' => $value];
        if (is_array($value)) {
            $items = [];
            $isList = array_is_list($value);
            foreach ($value as $k => $v) {
                $items[] = [
                    'k' => $isList ? null : $k,
                    'v' => $this->serializeValue($v),
                ];
            }
            return ['t' => 'array', 'list' => $isList, 'items' => $items];
        }
        if (is_object($value)) {
            $id = spl_object_id($value);
            if (isset($this->objectMap[$id])) {
                return ['t' => 'ref', 'id' => $this->objectMap[$id]];
            }
            $objId = $this->nextId++;
            $this->objectMap[$id] = $objId;

            $className = get_class($value);
            $props = [];
            foreach (get_object_vars($value) as $prop => $val) {
                $props[$prop] = $this->serializeValue($val);
            }
            return ['t' => 'object', 'id' => $objId, 'class' => $className, 'props' => $props];
        }
        return ['t' => 'unknown'];
    }

    public function deserialize(string $json): mixed {
        $data = json_decode($json, true);
        $this->serialized = [];
        return $this->deserializeValue($data);
    }

    private function deserializeValue(mixed $data): mixed {
        if (!is_array($data) || !isset($data['t'])) return null;

        return match($data['t']) {
            'null' => null,
            'bool' => $data['v'],
            'int' => $data['v'],
            'float' => $data['v'],
            'string' => $data['v'],
            'array' => $this->deserializeArray($data),
            'object' => $this->deserializeObject($data),
            'ref' => $this->serialized[$data['id']] ?? null,
            default => null,
        };
    }

    private function deserializeArray(array $data): array {
        $result = [];
        foreach ($data['items'] as $item) {
            $val = $this->deserializeValue($item['v']);
            if ($item['k'] === null) {
                $result[] = $val;
            } else {
                $result[$item['k']] = $val;
            }
        }
        return $result;
    }

    private function deserializeObject(array $data): object {
        $obj = new stdClass();
        $this->serialized[$data['id']] = $obj;
        foreach ($data['props'] as $prop => $val) {
            $obj->{$prop} = $this->deserializeValue($val);
        }
        $obj->__class = $data['class'];
        return $obj;
    }
}

class VersionMigrator {
    private array $migrations = [];

    public function addMigration(int $fromVersion, int $toVersion, callable $fn): self {
        $this->migrations[$fromVersion] = [
            'to' => $toVersion,
            'fn' => $fn,
        ];
        return $this;
    }

    public function migrate(array $data, int $fromVersion, int $toVersion): array {
        $current = $fromVersion;
        while ($current < $toVersion) {
            if (!isset($this->migrations[$current])) {
                throw new RuntimeException("No migration from version $current");
            }
            $migration = $this->migrations[$current];
            $data = ($migration['fn'])($data);
            $current = $migration['to'];
        }
        $data['__version'] = $toVersion;
        return $data;
    }
}

// === 测试 ===

echo "--- Basic Serialization ---\n";
$serializer = new ObjectSerializer();

$scalar = ['int' => 42, 'float' => 3.14, 'string' => 'hello', 'bool' => true, 'null' => null];
$serialized = $serializer->serialize($scalar);
$deserialized = $serializer->deserialize($serialized);
echo "Scalar roundtrip: " . var_export($scalar === $deserialized, true) . "\n";

echo "\n--- Array Serialization ---\n";
$arr = [1, [2, [3, [4, 5]]], 'key' => 'value'];
$serialized = $serializer->serialize($arr);
$deserialized = $serializer->deserialize($serialized);
echo "Array roundtrip: " . var_export($arr === $deserialized, true) . "\n";

echo "\n--- Object Serialization ---\n";
$obj = new stdClass();
$obj->name = 'TestObject';
$obj->value = 100;
$obj->tags = ['a', 'b', 'c'];
$obj->nested = new stdClass();
$obj->nested->deep = 'value';
$obj->nested->count = 5;

$serialized = $serializer->serialize($obj);
$deserialized = $serializer->deserialize($serialized);
echo "Original: name={$obj->name} value={$obj->value}\n";
echo "Restored: name={$deserialized->name} value={$deserialized->value}\n";
echo "Nested: deep={$deserialized->nested->deep} count={$deserialized->nested->count}\n";
echo "Tags: " . implode(",", $deserialized->tags) . "\n";

echo "\n--- Circular Reference ---\n";
$a = new stdClass();
$b = new stdClass();
$a->name = 'A';
$a->partner = $b;
$b->name = 'B';
$b->partner = $a;

$serialized = $serializer->serialize($a);
$restored = $serializer->deserialize($serialized);
echo "A name: {$restored->name}\n";
echo "A partner name: {$restored->partner->name}\n";
echo "Circular ref: " . var_export($restored->partner->partner === $restored, true) . "\n";

echo "\n--- Version Migration ---\n";
$migrator = new VersionMigrator();
$migrator->addMigration(1, 2, function($data) {
    $data['v2_field'] = 'added in v2';
    return $data;
});
$migrator->addMigration(2, 3, function($data) {
    $data['v3_field'] = 'added in v3';
    $data['v2_field'] = strtoupper($data['v2_field']);
    return $data;
});
$migrator->addMigration(3, 4, function($data) {
    $data['v4_count'] = count($data);
    return $data;
});

$v1Data = ['name' => 'test', 'value' => 42];
$v4Data = $migrator->migrate($v1Data, 1, 4);
echo "V1: " . json_encode($v1Data) . "\n";
echo "V4: " . json_encode($v4Data) . "\n";

echo "\n--- Complex Mixed Serialization ---\n";
$mixed = [
    'version' => 3,
    'config' => [
        'name' => 'MyApp',
        'settings' => ['debug' => true, 'max_conn' => 100],
    ],
    'users' => [
        ['id' => 1, 'name' => 'Alice', 'roles' => ['admin', 'user']],
        ['id' => 2, 'name' => 'Bob', 'roles' => ['user']],
    ],
    'metadata' => new stdClass(),
];
$mixed['metadata']->created = '2024-01-01';
$mixed['metadata']->tags = ['stable', 'production'];

$serialized = $serializer->serialize($mixed);
$deserialized = $serializer->deserialize($serialized);
echo "Mixed roundtrip name: " . $deserialized['config']['name'] . "\n";
echo "Mixed users count: " . count($deserialized['users']) . "\n";
echo "Mixed metadata created: {$deserialized['metadata']->created}\n";
echo "Mixed metadata tags: " . implode(",", $deserialized['metadata']->tags) . "\n";

echo "\n=== c027 Done ===\n";
