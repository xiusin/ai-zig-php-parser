<?php
// 极度混搭: 数组函数全家桶 + 排序/过滤/映射/分组/集合运算
echo "=== f042: Array Functions Full Suite ===\n";

class ArrayTools {
    public static function chunk(array $arr, int $size): array {
        return array_chunk($arr, $size);
    }

    public static function column(array $arr, string $col, ?string $key = null): array {
        return array_column($arr, $col, $key);
    }

    public static function combine(array $keys, array $values): array {
        return array_combine($keys, $values);
    }

    public static function countValues(array $arr): array {
        return array_count_values($arr);
    }

    public static function diff(array $a, array $b): array {
        return array_diff($a, $b);
    }

    public static function intersect(array $a, array $b): array {
        return array_intersect($a, $b);
    }

    public static function fill(int $start, int $count, mixed $value): array {
        return array_fill($start, $count, $value);
    }

    public static function filter(array $arr, callable $fn): array {
        return array_values(array_filter($arr, $fn));
    }

    public static function map(callable $fn, array $arr): array {
        return array_map($fn, $arr);
    }

    public static function reduce(array $arr, callable $fn, mixed $initial = null): mixed {
        return array_reduce($arr, $fn, $initial);
    }

    public static function merge(array ...$arrs): array {
        return array_merge(...$arrs);
    }

    public static function slice(array $arr, int $offset, ?int $len = null): array {
        return array_slice($arr, $offset, $len);
    }

    public static function splice(array &$arr, int $offset, ?int $len = null, mixed $replacement = []): array {
        return array_splice($arr, $offset, $len, $replacement);
    }

    public static function unique(array $arr): array {
        return array_values(array_unique($arr));
    }

    public static function reverse(array $arr): array {
        return array_reverse($arr);
    }

    public static function search(array $arr, mixed $val): int|string|false {
        return array_search($val, $arr);
    }

    public static function contains(array $arr, mixed $val): bool {
        return in_array($val, $arr, true);
    }

    public static function sort(array &$arr, int $flag = SORT_REGULAR): bool {
        return sort($arr, $flag);
    }

    public static function sortAssoc(array &$arr, int $flag = SORT_REGULAR): bool {
        return asort($arr, $flag);
    }

    public static function sortByKey(array &$arr, int $flag = SORT_REGULAR): bool {
        return ksort($arr, $flag);
    }

    public static function usort(array &$arr, callable $fn): bool {
        return usort($arr, $fn);
    }

    public static function sum(array $arr): int|float {
        return array_sum($arr);
    }

    public static function product(array $arr): int|float {
        return array_product($arr);
    }

    public static function first(array $arr): mixed {
        return reset($arr);
    }

    public static function last(array $arr): mixed {
        return end($arr);
    }

    public static function flatten(array $arr): array {
        $result = [];
        array_walk_recursive($arr, function($v) use (&$result) { $result[] = $v; });
        return $result;
    }

    public static function groupBy(array $arr, callable $fn): array {
        $groups = [];
        foreach ($arr as $item) {
            $key = $fn($item);
            $groups[$key][] = $item;
        }
        return $groups;
    }

    public static function partition(array $arr, callable $fn): array {
        $pass = []; $fail = [];
        foreach ($arr as $item) {
            if ($fn($item)) $pass[] = $item;
            else $fail[] = $item;
        }
        return [$pass, $fail];
    }

    public static function zip(array ...$arrs): array {
        $result = [];
        $min = min(array_map('count', $arrs));
        for ($i = 0; $i < $min; $i++) {
            $row = [];
            foreach ($arrs as $arr) $row[] = $arr[$i];
            $result[] = $row;
        }
        return $result;
    }

    public static function range(int $start, int $end, int $step = 1): array {
        return range($start, $end, $step);
    }
}

// === 测试 ===
$arr = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
echo "Original: " . json_encode($arr) . "\n";

echo "unique: " . json_encode(ArrayTools::unique($arr)) . "\n";
echo "sum: " . ArrayTools::sum($arr) . "\n";
echo "product: " . ArrayTools::product([1,2,3,4]) . "\n";
echo "first: " . ArrayTools::first($arr) . "\n";
echo "last: " . ArrayTools::last($arr) . "\n";
echo "countValues: " . json_encode(ArrayTools::countValues($arr)) . "\n";

$sorted = $arr; ArrayTools::sort($sorted);
echo "sorted: " . json_encode($sorted) . "\n";

$reversed = ArrayTools::reverse($arr);
echo "reversed: " . json_encode($reversed) . "\n";

echo "filter(>4): " . json_encode(ArrayTools::filter($arr, fn($x) => $x > 4)) . "\n";
echo "map(x2): " . json_encode(ArrayTools::map(fn($x) => $x * 2, $arr)) . "\n";
echo "reduce(+): " . ArrayTools::reduce($arr, fn($c, $i) => $c + $i, 0) . "\n";

echo "chunk(3): " . json_encode(ArrayTools::chunk($arr, 3)) . "\n";
echo "slice(2,4): " . json_encode(ArrayTools::slice($arr, 2, 4)) . "\n";

echo "diff([1,2,3],[2,4]): " . json_encode(ArrayTools::diff([1,2,3], [2,4])) . "\n";
echo "intersect([1,2,3],[2,4,6]): " . json_encode(ArrayTools::intersect([1,2,3,6], [2,4,6])) . "\n";

$records = [
    ['id' => 1, 'name' => 'Alice', 'dept' => 'Eng'],
    ['id' => 2, 'name' => 'Bob', 'dept' => 'Sales'],
    ['id' => 3, 'name' => 'Charlie', 'dept' => 'Eng'],
];
echo "column(name,id): " . json_encode(ArrayTools::column($records, 'name', 'id')) . "\n";
echo "groupBy(dept): " . json_encode(ArrayTools::groupBy($records, fn($r) => $r['dept'])) . "\n";

[$pass, $fail] = ArrayTools::partition($arr, fn($x) => $x > 3);
echo "partition(>3): pass=" . json_encode($pass) . " fail=" . json_encode($fail) . "\n";

echo "zip([1,2],[a,b],[x,y]): " . json_encode(ArrayTools::zip([1,2], ['a','b'], ['x','y'])) . "\n";

$nested = [1, [2, 3], [4, [5, 6]], 7];
echo "flatten: " . json_encode(ArrayTools::flatten($nested)) . "\n";

$merged = ArrayTools::merge([1,2], [3,4], [5,6]);
echo "merge: " . json_encode($merged) . "\n";

echo "combine: " . json_encode(ArrayTools::combine(['a','b','c'], [1,2,3])) . "\n";
echo "range(1,10,2): " . json_encode(ArrayTools::range(1, 10, 2)) . "\n";
echo "fill(0,3,'x'): " . json_encode(ArrayTools::fill(0, 3, 'x')) . "\n";

echo "=== f042 Done ===\n";
