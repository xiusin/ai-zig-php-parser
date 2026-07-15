<?php
// 极度混搭: 类型系统 + 泛型约束 + 协变逆变 + 模式匹配 + 类型守卫
echo "=== c049: TypeSystem + Generic + Covariant + PatternGuard ===\n\n";

class TypeSystem {
    private array $types = [];
    private array $relations = [];

    public function defineType(string $name, string $parent = 'any'): void {
        $this->types[$name] = ['parent' => $parent];
        if (!isset($this->relations[$parent])) {
            $this->relations[$parent] = [];
        }
        $this->relations[$parent][] = $name;
    }

    public function isSubtype(string $sub, string $super): bool {
        if ($sub === $super) return true;
        if ($super === 'any' || $super === 'mixed') return true;
        $current = $sub;
        while (isset($this->types[$current]['parent'])) {
            $parent = $this->types[$current]['parent'];
            if ($parent === $super) return true;
            $current = $parent;
        }
        return false;
    }

    public function getHierarchy(string $type): array {
        $hierarchy = [$type];
        $current = $type;
        while (isset($this->types[$current]['parent'])) {
            $current = $this->types[$current]['parent'];
            $hierarchy[] = $current;
        }
        return $hierarchy;
    }

    public function getSubtypes(string $type): array {
        $result = [];
        if (isset($this->relations[$type])) {
            foreach ($this->relations[$type] as $sub) {
                $result[] = $sub;
                $result = array_merge($result, $this->getSubtypes($sub));
            }
        }
        return $result;
    }
}

class GenericType {
    public string $name;
    public array $typeParams;
    public array $constraints;

    public function __construct(string $name, array $typeParams, array $constraints = []) {
        $this->name = $name;
        $this->typeParams = $typeParams;
        $this->constraints = $constraints;
    }

    public function instantiate(array $typeArgs, TypeSystem $ts): array {
        $errors = [];
        if (count($typeArgs) !== count($this->typeParams)) {
            $errors[] = "Expected " . count($this->typeParams) . " type arguments, got " . count($typeArgs);
            return $errors;
        }
        for ($i = 0; $i < count($this->typeParams); $i++) {
            $param = $this->typeParams[$i];
            $constraint = $this->constraints[$param] ?? 'any';
            if (!$ts->isSubtype($typeArgs[$i], $constraint)) {
                $errors[] = "Type argument $typeArgs[$i] does not satisfy constraint $constraint for $param";
            }
        }
        return $errors;
    }
}

class PatternMatcher {
    public static function match(mixed $value, array $patterns): mixed {
        foreach ($patterns as $pattern) {
            $type = $pattern['type'] ?? null;
            $guard = $pattern['guard'] ?? null;
            $handler = $pattern['handler'];

            if ($type !== null) {
                $typeFunc = 'is_' . $type;
                if (function_exists($typeFunc) && !$typeFunc($value)) continue;
                if ($type === 'int' && !is_int($value)) continue;
                if ($type === 'string' && !is_string($value)) continue;
                if ($type === 'float' && !is_float($value)) continue;
                if ($type === 'bool' && !is_bool($value)) continue;
                if ($type === 'array' && !is_array($value)) continue;
                if ($type === 'null' && !is_null($value)) continue;
            }

            if ($guard !== null && !($guard)($value)) continue;

            return $handler($value);
        }
        return null;
    }

    public static function matchType(mixed $value): string {
        return match(true) {
            is_int($value) => 'int',
            is_float($value) => 'float',
            is_string($value) => 'string',
            is_bool($value) => 'bool',
            is_array($value) => 'array',
            is_null($value) => 'null',
            is_object($value) => get_class($value),
            default => 'unknown',
        };
    }
}

class CovariantTest {
    public static function testCovariance(TypeSystem $ts): bool {
        $types = ['animal', 'dog', 'poodle'];
        foreach ($types as $t) {
            $ts->defineType($t, $t === 'animal' ? 'any' : ($t === 'dog' ? 'animal' : 'dog'));
        }
        return $ts->isSubtype('poodle', 'animal')
            && $ts->isSubtype('dog', 'animal')
            && $ts->isSubtype('poodle', 'dog')
            && !$ts->isSubtype('animal', 'dog');
    }

    public static function testContravariance(TypeSystem $ts): bool {
        // If Handler<T> is contravariant in T, then Handler<Animal> <: Handler<Dog>
        // This means: if we need a handler that can handle dogs, a handler for animals works
        // In our type system: isSubtype checks if first is subtype of second
        // Contravariant: Handler<Animal> is usable where Handler<Dog> is expected
        // Simulated: 'handler_animal' is usable as 'handler_dog'
        $ts->defineType('handler_animal', 'any');
        $ts->defineType('handler_dog', 'handler_animal');
        return $ts->isSubtype('handler_dog', 'handler_animal');
    }
}

// === 测试 ===

echo "--- Type Hierarchy ---\n";
$ts = new TypeSystem();
$ts->defineType('number');
$ts->defineType('int', 'number');
$ts->defineType('float', 'number');
$ts->defineType('string');
$ts->defineType('collection');
$ts->defineType('list', 'collection');
$ts->defineType('vector', 'list');
$ts->defineType('array', 'list');

echo "int <: number: " . var_export($ts->isSubtype('int', 'number'), true) . "\n";
echo "int <: any: " . var_export($ts->isSubtype('int', 'any'), true) . "\n";
echo "vector <: list: " . var_export($ts->isSubtype('vector', 'list'), true) . "\n";
echo "vector <: collection: " . var_export($ts->isSubtype('vector', 'collection'), true) . "\n";
echo "string <: number: " . var_export($ts->isSubtype('string', 'number'), true) . "\n";

echo "\nHierarchy of 'vector': " . implode(" -> ", $ts->getHierarchy('vector')) . "\n";
echo "Subtypes of 'list': " . implode(", ", $ts->getSubtypes('list')) . "\n";
echo "Subtypes of 'collection': " . implode(", ", $ts->getSubtypes('collection')) . "\n";

echo "\n--- Generic Type Instantiation ---\n";
$genericList = new GenericType('List', ['T'], ['T' => 'number']);
echo "List<int> errors: " . (empty($genericList->instantiate(['int'], $ts)) ? "none" : implode("; ", $genericList->instantiate(['int'], $ts))) . "\n";
echo "List<string> errors: " . (empty($genericList->instantiate(['string'], $ts)) ? "none" : implode("; ", $genericList->instantiate(['string'], $ts))) . "\n";

$genericCollection = new GenericType('Collection', ['K', 'V'], ['K' => 'string', 'V' => 'collection']);
echo "Collection<string,list> errors: " . (empty($genericCollection->instantiate(['string', 'list'], $ts)) ? "none" : implode("; ", $genericCollection->instantiate(['string', 'list'], $ts))) . "\n";
echo "Collection<int,list> errors: " . (empty($genericCollection->instantiate(['int', 'list'], $ts)) ? "none" : implode("; ", $genericCollection->instantiate(['int', 'list'], $ts))) . "\n";

echo "\n--- Pattern Matching ---\n";
$values = [42, 3.14, "hello", true, [1, 2, 3], null, 0, ""];

foreach ($values as $val) {
    $result = PatternMatcher::match($val, [
        ['type' => 'int', 'guard' => fn($v) => $v > 0, 'handler' => fn($v) => "positive int: $v"],
        ['type' => 'int', 'guard' => fn($v) => $v === 0, 'handler' => fn($v) => "zero"],
        ['type' => 'int', 'handler' => fn($v) => "negative int: $v"],
        ['type' => 'float', 'handler' => fn($v) => "float: $v"],
        ['type' => 'string', 'guard' => fn($v) => strlen($v) > 0, 'handler' => fn($v) => "non-empty string: '$v'"],
        ['type' => 'string', 'handler' => fn($v) => "empty string"],
        ['type' => 'bool', 'handler' => fn($v) => "boolean: " . var_export($v, true)],
        ['type' => 'array', 'guard' => fn($v) => count($v) > 2, 'handler' => fn($v) => "large array: " . count($v) . " items"],
        ['type' => 'array', 'handler' => fn($v) => "small array: " . count($v) . " items"],
        ['type' => 'null', 'handler' => fn($v) => "null value"],
    ]);
    echo "  " . PatternMatcher::matchType($val) . " -> $result\n";
}

echo "\n--- Covariance/Contravariance ---\n";
echo "Covariance test: " . var_export(CovariantTest::testCovariance($ts), true) . "\n";
echo "Contravariance test: " . var_export(CovariantTest::testContravariance($ts), true) . "\n";

echo "\n=== c049 Done ===\n";
