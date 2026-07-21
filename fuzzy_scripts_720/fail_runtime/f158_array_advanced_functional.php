<?php
// 数组操作：函数式数组、稀疏数组、多维变换、分组、扁平化
echo "=== f158: Array Advanced + Functional + Multi-dimensional ===\n";

class ArrayUtils {
    // 数组分组
    public static function groupBy(array $items, callable $fn): array {
        $result = [];
        foreach ($items as $item) {
            $key = $fn($item);
            $result[$key][] = $item;
        }
        return $result;
    }

    // 数组按键分组求值
    public static function groupByCount(array $items, callable $fn): array {
        $result = [];
        foreach ($items as $item) {
            $key = $fn($item);
            $result[$key] = ($result[$key] ?? 0) + 1;
        }
        return $result;
    }

    // 深度扁平化
    public static function flatten(array $items, int $depth = PHP_INT_MAX): array {
        $result = [];
        foreach ($items as $item) {
            if (is_array($item) && $depth > 0) {
                $result = array_merge($result, self::flatten($item, $depth - 1));
            } else {
                $result[] = $item;
            }
        }
        return $result;
    }

    // 去重（保留键）
    public static function unique(array $items): array {
        $seen = [];
        $result = [];
        foreach ($items as $key => $value) {
            $hash = is_array($value) || is_object($value) ? serialize($value) : (string)$value;
            if (!isset($seen[$hash])) {
                $seen[$hash] = true;
                $result[$key] = $value;
            }
        }
        return $result;
    }

    // 交集（回调比较）
    public static function intersect(array $a, array $b, ?callable $fn = null): array {
        $fn ??= fn($x) => $x;
        $bValues = array_map($fn, $b);
        return array_filter($a, fn($x) => in_array($fn($x), $bValues));
    }

    // 差集
    public static function diff(array $a, array $b, ?callable $fn = null): array {
        $fn ??= fn($x) => $x;
        $bValues = array_map($fn, $b);
        return array_filter($a, fn($x) => !in_array($fn($x), $bValues));
    }

    // 分块
    public static function chunk(array $items, int $size): array {
        return array_chunk($items, $size, true);
    }

    // 排序（回调）
    public static function sortBy(array $items, callable $fn, bool $desc = false): array {
        usort($items, function($a, $b) use ($fn, $desc) {
            $cmp = $fn($a) <=> $fn($b);
            return $desc ? -$cmp : $cmp;
        });
        return $items;
    }

    // Zip
    public static function zip(array ...$arrays): array {
        $result = [];
        $count = min(array_map('count', $arrays));
        for ($i = 0; $i < $count; $i++) {
            $tuple = [];
            foreach ($arrays as $arr) {
                $tuple[] = array_values($arr)[$i];
            }
            $result[] = $tuple;
        }
        return $result;
    }

    // 范围
    public static function range(int $start, int $end, int $step = 1): array {
        $result = [];
        for ($i = $start; $i <= $end; $i += $step) {
            $result[] = $i;
        }
        return $result;
    }

    // 透视表
    public static function pivot(array $items, string $rowKey, string $colKey, string $valueKey, mixed $default = 0): array {
        $result = [];
        $columns = [];
        foreach ($items as $item) {
            $row = $item[$rowKey] ?? 'unknown';
            $col = $item[$colKey] ?? 'unknown';
            $val = $item[$valueKey] ?? $default;
            $columns[$col] = true;
            $result[$row][$col] = $val;
        }
        // 填充缺失值
        foreach ($result as &$row) {
            foreach (array_keys($columns) as $col) {
                if (!isset($row[$col])) $row[$col] = $default;
            }
        }
        return $result;
    }
}

// 测试数据
$people = [
    ['name' => 'Alice', 'age' => 30, 'city' => 'Beijing', 'dept' => 'Engineering'],
    ['name' => 'Bob', 'age' => 25, 'city' => 'Shanghai', 'dept' => 'Sales'],
    ['name' => 'Charlie', 'age' => 35, 'city' => 'Beijing', 'dept' => 'Engineering'],
    ['name' => 'Diana', 'age' => 28, 'city' => 'Shanghai', 'dept' => 'Marketing'],
    ['name' => 'Eve', 'age' => 32, 'city' => 'Guangzhou', 'dept' => 'Engineering'],
    ['name' => 'Frank', 'age' => 40, 'city' => 'Beijing', 'dept' => 'Sales'],
];

echo "--- Group By ---\n";
$byCity = ArrayUtils::groupBy($people, fn($p) => $p['city']);
foreach ($byCity as $city => $members) {
    $names = array_map(fn($p) => $p['name'], $members);
    echo "  $city: " . implode(', ', $names) . " (" . count($members) . ")\n";
}

$byDept = ArrayUtils::groupBy($people, fn($p) => $p['dept']);
foreach ($byDept as $dept => $members) {
    $avgAge = array_sum(array_map(fn($p) => $p['age'], $members)) / count($members);
    echo "  $dept avg age: " . round($avgAge, 1) . "\n";
}

echo "\n--- Flatten ---\n";
$nested = [1, [2, 3], [4, [5, 6]], [7, [8, [9, 10]]]];
echo "  Deep: " . implode(', ', ArrayUtils::flatten($nested)) . "\n";
echo "  Shallow: " . implode(', ', ArrayUtils::flatten($nested, 1)) . "\n";

echo "\n--- Unique ---\n";
$dups = [1, 2, 2, 3, 3, 3, 4, 4, 4, 4, 'a', 'a', 'b'];
echo "  Unique: " . implode(', ', ArrayUtils::unique($dups)) . "\n";

echo "\n--- Intersect / Diff ---\n";
$a = [1, 2, 3, 4, 5, 6];
$b = [4, 5, 6, 7, 8, 9];
echo "  Intersect: " . implode(', ', ArrayUtils::intersect($a, $b)) . "\n";
echo "  Diff (a-b): " . implode(', ', ArrayUtils::diff($a, $b)) . "\n";
echo "  Diff (b-a): " . implode(', ', ArrayUtils::diff($b, $a)) . "\n";

echo "\n--- Chunk ---\n";
$chunks = ArrayUtils::chunk([1, 2, 3, 4, 5, 6, 7], 3);
foreach ($chunks as $i => $chunk) {
    echo "  Chunk $i: " . implode(', ', $chunk) . "\n";
}

echo "\n--- Sort By ---\n";
$sorted = ArrayUtils::sortBy($people, fn($p) => $p['age']);
echo "  By age (asc):\n";
foreach ($sorted as $p) echo "    {$p['name']}: {$p['age']}\n";
$sortedDesc = ArrayUtils::sortBy($people, fn($p) => $p['age'], true);
echo "  By age (desc):\n";
foreach (array_slice($sortedDesc, 0, 3) as $p) echo "    {$p['name']}: {$p['age']}\n";

echo "\n--- Zip ---\n";
$zipped = ArrayUtils::zip(['a', 'b', 'c'], [1, 2, 3], ['x', 'y', 'z']);
foreach ($zipped as $tuple) {
    echo "  " . implode(' - ', $tuple) . "\n";
}

echo "\n--- Pivot Table ---\n";
$sales = [
    ['region' => 'East', 'product' => 'A', 'amount' => 100],
    ['region' => 'East', 'product' => 'B', 'amount' => 200],
    ['region' => 'West', 'product' => 'A', 'amount' => 150],
    ['region' => 'West', 'product' => 'B', 'amount' => 250],
    ['region' => 'East', 'product' => 'A', 'amount' => 50],
    ['region' => 'West', 'product' => 'A', 'amount' => 75],
];
$pivot = ArrayUtils::pivot($sales, 'region', 'product', 'amount');
echo "  Region | A | B\n";
foreach ($pivot as $region => $products) {
    echo "  $region | " . ($products['A'] ?? 0) . " | " . ($products['B'] ?? 0) . "\n";
}

echo "\n--- Multi-dimensional Map ---\n";
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
];
echo "  Original:\n";
foreach ($matrix as $row) echo "    " . implode(', ', $row) . "\n";
$doubled = array_map(fn($row) => array_map(fn($v) => $v * 2, $row), $matrix);
echo "  Doubled:\n";
foreach ($doubled as $row) echo "    " . implode(', ', $row) . "\n";
$transposed = ArrayUtils::zip(...$matrix);
echo "  Transposed:\n";
foreach ($transposed as $row) echo "    " . implode(', ', $row) . "\n";

echo "\n--- Array Reduce Advanced ---\n";
$words = ['hello', 'world', 'foo', 'bar', 'hello', 'foo', 'hello'];
$freq = array_reduce($words, function($acc, $word) {
    $acc[$word] = ($acc[$word] ?? 0) + 1;
    return $acc;
}, []);
arsort($freq);
echo "  Word frequency:\n";
foreach ($freq as $word => $count) echo "    $word: $count\n";

echo "=== f158 Done ===\n";
