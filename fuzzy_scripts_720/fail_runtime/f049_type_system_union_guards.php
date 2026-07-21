<?php
// 极度混搭: 类型系统 + 联合类型 + 交叉类型模拟 + 类型守卫 + instanceof + is_*
echo "=== f049: Type System + Union + Guards + instanceof ===\n";

interface Animal {
    public function getName(): string;
    public function sound(): string;
}

interface Swimmer {
    public function swim(): string;
}

interface Flyer {
    public function fly(): string;
}

class Duck implements Animal, Swimmer, Flyer {
    public function getName(): string { return 'Duck'; }
    public function sound(): string { return 'Quack!'; }
    public function swim(): string { return 'Duck swimming'; }
    public function fly(): string { return 'Duck flying'; }
}

class Penguin implements Animal, Swimmer {
    public function getName(): string { return 'Penguin'; }
    public function sound(): string { return 'Squeak!'; }
    public function swim(): string { return 'Penguin swimming'; }
}

class Eagle implements Animal, Flyer {
    public function getName(): string { return 'Eagle'; }
    public function sound(): string { return 'Screech!'; }
    public function fly(): string { return 'Eagle soaring'; }
}

class TypeGuard {
    public static function process(Animal $animal): string {
        $result = "{$animal->getName()} says {$animal->sound()}";

        // 类型守卫
        if ($animal instanceof Swimmer) {
            $result .= " | " . $animal->swim();
        }
        if ($animal instanceof Flyer) {
            $result .= " | " . $animal->fly();
        }
        return $result;
    }

    public static function describeType(mixed $value): string {
        return match(gettype($value)) {
            'integer' => "int(" . $value . ")",
            'double' => "float(" . number_format($value, 4) . ")",
            'string' => "string('" . $value . "', len=" . strlen($value) . ")",
            'boolean' => "bool(" . var_export($value, true) . ")",
            'array' => "array(count=" . count($value) . ", list=" . var_export(array_is_list($value), true) . ")",
            'NULL' => "null",
            'object' => "object(" . get_class($value) . ")",
            default => "unknown",
        };
    }

    public static function safeCast(mixed $value, string $target): mixed {
        return match($target) {
            'int' => is_numeric($value) ? (int)$value : throw new InvalidArgumentException("Cannot cast to int"),
            'float' => is_numeric($value) ? (float)$value : throw new InvalidArgumentException("Cannot cast to float"),
            'string' => is_scalar($value) || $value === null ? (string)$value : throw new InvalidArgumentException("Cannot cast to string"),
            'bool' => (bool)$value,
            'array' => (array)$value,
            default => throw new InvalidArgumentException("Unknown target type: $target"),
        };
    }

    public static function deepTypeCheck(array $data, array $schema): array {
        $errors = [];
        foreach ($schema as $key => $expectedType) {
            if (!array_key_exists($key, $data)) {
                $errors[] = "Missing key: $key";
                continue;
            }
            $actualType = gettype($data[$key]);
            $typeMap = ['int' => 'integer', 'float' => 'double', 'bool' => 'boolean', 'string' => 'string', 'array' => 'array'];
            $expected = $typeMap[$expectedType] ?? $expectedType;
            if ($actualType !== $expected) {
                $errors[] = "Key '$key': expected $expectedType, got $actualType";
            }
        }
        return $errors;
    }
}

// 测试
echo "--- Animal Type Guards ---\n";
$animals = [new Duck(), new Penguin(), new Eagle()];
foreach ($animals as $animal) {
    echo "  " . TypeGuard::process($animal) . "\n";
}

echo "\n--- Describe Type ---\n";
$values = [42, 3.14, 'hello', true, [1,2,3], null, new Duck()];
foreach ($values as $v) {
    echo "  " . TypeGuard::describeType($v) . "\n";
}

echo "\n--- Safe Cast ---\n";
echo "  (int)'123': " . TypeGuard::safeCast('123', 'int') . "\n";
echo "  (float)'3.14': " . TypeGuard::safeCast('3.14', 'float') . "\n";
echo "  (string)42: " . TypeGuard::safeCast(42, 'string') . "\n";
echo "  (bool)'': " . var_export(TypeGuard::safeCast('', 'bool'), true) . "\n";
echo "  (bool)'text': " . var_export(TypeGuard::safeCast('text', 'bool'), true) . "\n";
echo "  (array)'x': " . json_encode(TypeGuard::safeCast('x', 'array')) . "\n";

try { TypeGuard::safeCast('abc', 'int'); }
catch (InvalidArgumentException $e) { echo "  Caught: " . $e->getMessage() . "\n"; }

echo "\n--- Deep Type Check ---\n";
$config = ['host' => 'localhost', 'port' => 3306, 'debug' => true, 'name' => 'myapp'];
$schema = ['host' => 'string', 'port' => 'int', 'debug' => 'bool', 'timeout' => 'int'];
$errors = TypeGuard::deepTypeCheck($config, $schema);
echo "  Errors: " . (empty($errors) ? 'none' : implode('; ', $errors)) . "\n";

$config2 = ['host' => 'localhost', 'port' => 'wrong', 'debug' => 'yes'];
$errors2 = TypeGuard::deepTypeCheck($config2, $schema);
echo "  Errors2: " . (empty($errors2) ? 'none' : implode('; ', $errors2)) . "\n";

echo "\n--- Union Type Simulation ---\n";
function processId(int|string $id): string {
    if (is_int($id)) {
        return "Numeric ID: $id";
    }
    return "String ID: $id";
}
echo "  processId(42): " . processId(42) . "\n";
echo "  processId('abc'): " . processId('abc') . "\n";

echo "\n--- Nullable Type ---\n";
function findUser(?string $name): string {
    return $name === null ? 'No user' : "User: $name";
}
echo "  findUser('Alice'): " . findUser('Alice') . "\n";
echo "  findUser(null): " . findUser(null) . "\n";

echo "=== f049 Done ===\n";
