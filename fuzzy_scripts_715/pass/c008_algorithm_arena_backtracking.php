<?php
// 极度混搭: 算法竞赛 + 数据结构 + 位运算 + 数学 + 递归回溯
echo "=== c008: Algorithm Arena + DataStructure + BitMath + Backtracking ===\n\n";

class ArrayUtils {
    public static function rotateLeft(array $arr, int $k): array {
        $n = count($arr);
        if ($n == 0) return $arr;
        $k = $k % $n;
        if ($k < 0) $k += $n;
        return array_merge(array_slice($arr, $k), array_slice($arr, 0, $k));
    }

    public static function rotateRight(array $arr, int $k): array {
        $n = count($arr);
        if ($n == 0) return $arr;
        return self::rotateLeft($arr, $n - ($k % $n));
    }

    public static function partition(array $arr, callable $fn): array {
        $truthy = [];
        $falsy = [];
        foreach ($arr as $v) {
            if ($fn($v)) $truthy[] = $v;
            else $falsy[] = $v;
        }
        return [$truthy, $falsy];
    }

    public static function groupBy(array $arr, callable $fn): array {
        $result = [];
        foreach ($arr as $v) {
            $key = $fn($v);
            if (!isset($result[$key])) $result[$key] = [];
            $result[$key][] = $v;
        }
        return $result;
    }

    public static function windowed(array $arr, int $size): array {
        $result = [];
        $n = count($arr);
        for ($i = 0; $i <= $n - $size; $i++) {
            $result[] = array_slice($arr, $i, $size);
        }
        return $result;
    }

    public static function zip(array ...$arrays): array {
        $result = [];
        $min = min(array_map('count', $arrays));
        for ($i = 0; $i < $min; $i++) {
            $tuple = [];
            foreach ($arrays as $arr) {
                $tuple[] = $arr[$i];
            }
            $result[] = $tuple;
        }
        return $result;
    }
}

class Backtracker {
    private array $results = [];

    public function permutations(array $elements): array {
        $this->results = [];
        $this->permute($elements, []);
        return $this->results;
    }

    private function permute(array $remaining, array $current): void {
        if (empty($remaining)) {
            $this->results[] = $current;
            return;
        }
        $seen = [];
        for ($i = 0; $i < count($remaining); $i++) {
            if (in_array($remaining[$i], $seen)) continue;
            $seen[] = $remaining[$i];
            $newRemaining = array_merge(
                array_slice($remaining, 0, $i),
                array_slice($remaining, $i + 1)
            );
            $this->permute($newRemaining, array_merge($current, [$remaining[$i]]));
        }
    }

    public function combinations(array $elements, int $k): array {
        $this->results = [];
        $this->combine($elements, $k, 0, []);
        return $this->results;
    }

    private function combine(array $elements, int $k, int $start, array $current): void {
        if (count($current) == $k) {
            $this->results[] = $current;
            return;
        }
        for ($i = $start; $i < count($elements); $i++) {
            $this->combine($elements, $k, $i + 1, array_merge($current, [$elements[$i]]));
        }
    }

    public function subsets(array $elements): array {
        $this->results = [];
        $this->subset($elements, 0, []);
        return $this->results;
    }

    private function subset(array $elements, int $start, array $current): void {
        $this->results[] = $current;
        for ($i = $start; $i < count($elements); $i++) {
            $this->subset($elements, $i + 1, array_merge($current, [$elements[$i]]));
        }
    }
}

// === 测试 ===

// 1. 数组旋转
echo "--- Array Rotation ---\n";
$arr = [1, 2, 3, 4, 5, 6, 7];
echo "Original: " . implode(",", $arr) . "\n";
echo "RotLeft 3: " . implode(",", ArrayUtils::rotateLeft($arr, 3)) . "\n";
echo "RotRight 2: " . implode(",", ArrayUtils::rotateRight($arr, 2)) . "\n";

// 2. 分区
echo "\n--- Partition ---\n";
[$even, $odd] = ArrayUtils::partition([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], fn($x) => $x % 2 == 0);
echo "Even: " . implode(",", $even) . "\n";
echo "Odd: " . implode(",", $odd) . "\n";

// 3. 分组
echo "\n--- Group By ---\n";
$words = ["apple", "banana", "cherry", "date", "fig", "grape"];
$grouped = ArrayUtils::groupBy($words, fn($w) => strlen($w));
ksort($grouped);
foreach ($grouped as $len => $ws) {
    echo "  len=$len: " . implode(",", $ws) . "\n";
}

// 4. 滑动窗口
echo "\n--- Sliding Window ---\n";
$windowed = ArrayUtils::windowed([1, 2, 3, 4, 5], 3);
foreach ($windowed as $w) {
    echo "  [" . implode(",", $w) . "] sum=" . array_sum($w) . "\n";
}

// 5. Zip 操作
echo "\n--- Zip ---\n";
$zipped = ArrayUtils::zip([1, 2, 3], ['a', 'b', 'c'], [true, false, true]);
foreach ($zipped as $z) {
    echo "  [" . implode(",", array_map(fn($v) => var_export($v, true), $z)) . "]\n";
}

// 6. 排列
echo "\n--- Permutations ---\n";
$bt = new Backtracker();
$perms = $bt->permutations(['A', 'B', 'C']);
echo "Count: " . count($perms) . "\n";
foreach ($perms as $p) {
    echo "  " . implode("-", $p) . "\n";
}

// 7. 组合
echo "\n--- Combinations ---\n";
$combs = $bt->combinations(['A', 'B', 'C', 'D'], 2);
echo "Count: " . count($combs) . "\n";
foreach ($combs as $c) {
    echo "  {" . implode(",", $c) . "}\n";
}

// 8. 子集
echo "\n--- Subsets ---\n";
$subs = $bt->subsets([1, 2, 3]);
echo "Count: " . count($subs) . "\n";
foreach ($subs as $s) {
    echo "  {" . implode(",", $s) . "}\n";
}

// 9. 位运算: 求所有子集（二进制法）
echo "\n--- Bitmask Subsets ---\n";
$set = ['x', 'y', 'z'];
$n = count($set);
for ($mask = 0; $mask < (1 << $n); $mask++) {
    $subset = [];
    for ($i = 0; $i < $n; $i++) {
        if ($mask & (1 << $i)) {
            $subset[] = $set[$i];
        }
    }
    echo "  mask=" . sprintf("%0{$n}b", $mask) . " {" . implode(",", $subset) . "}\n";
}

// 10. 矩阵运算（二维数组）
echo "\n--- Matrix Operations ---\n";
$matA = [[1, 2, 3], [4, 5, 6]];
$matB = [[7, 8], [9, 10], [11, 12]];
$product = [];
for ($i = 0; $i < count($matA); $i++) {
    $product[$i] = [];
    for ($j = 0; $j < count($matB[0]); $j++) {
        $sum = 0;
        for ($k = 0; $k < count($matB); $k++) {
            $sum += $matA[$i][$k] * $matB[$k][$j];
        }
        $product[$i][$j] = $sum;
    }
}
echo "Matrix product:\n";
foreach ($product as $row) {
    echo "  [" . implode(", ", $row) . "]\n";
}

// 11. 快速排序 + 二分搜索
echo "\n--- QuickSort + BinarySearch ---\n";
function quickSort(array $arr): array {
    if (count($arr) <= 1) return $arr;
    $pivot = $arr[0];
    [$less, $greater] = [[], []];
    for ($i = 1; $i < count($arr); $i++) {
        if ($arr[$i] <= $pivot) $less[] = $arr[$i];
        else $greater[] = $arr[$i];
    }
    return array_merge(quickSort($less), [$pivot], quickSort($greater));
}

function binarySearch(array $arr, int $target): int {
    $lo = 0; $hi = count($arr) - 1;
    while ($lo <= $hi) {
        $mid = intdiv($lo + $hi, 2);
        if ($arr[$mid] == $target) return $mid;
        if ($arr[$mid] < $target) $lo = $mid + 1;
        else $hi = $mid - 1;
    }
    return -1;
}

$unsorted = [38, 27, 43, 3, 9, 82, 10];
$sorted = quickSort($unsorted);
echo "Sorted: " . implode(",", $sorted) . "\n";
echo "Search 43: index=" . binarySearch($sorted, 43) . "\n";
echo "Search 99: index=" . binarySearch($sorted, 99) . "\n";

echo "\n=== c008 Done ===\n";
