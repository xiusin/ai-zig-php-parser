<?php
// 极度混搭: 排序算法全家桶 + 搜索算法 + 性能对比 + 闭包比较器
echo "=== f014: Sort Algorithms + Search + Benchmark ===\n";

class Sorter {
    public static function bubble(array $arr): array {
        $n = count($arr);
        for ($i = 0; $i < $n - 1; $i++) {
            $swapped = false;
            for ($j = 0; $j < $n - $i - 1; $j++) {
                if ($arr[$j] > $arr[$j + 1]) {
                    $tmp = $arr[$j];
                    $arr[$j] = $arr[$j + 1];
                    $arr[$j + 1] = $tmp;
                    $swapped = true;
                }
            }
            if (!$swapped) break;
        }
        return $arr;
    }

    public static function selection(array $arr): array {
        $n = count($arr);
        for ($i = 0; $i < $n - 1; $i++) {
            $minIdx = $i;
            for ($j = $i + 1; $j < $n; $j++) {
                if ($arr[$j] < $arr[$minIdx]) $minIdx = $j;
            }
            if ($minIdx !== $i) {
                $tmp = $arr[$i];
                $arr[$i] = $arr[$minIdx];
                $arr[$minIdx] = $tmp;
            }
        }
        return $arr;
    }

    public static function insertion(array $arr): array {
        for ($i = 1; $i < count($arr); $i++) {
            $key = $arr[$i];
            $j = $i - 1;
            while ($j >= 0 && $arr[$j] > $key) {
                $arr[$j + 1] = $arr[$j];
                $j--;
            }
            $arr[$j + 1] = $key;
        }
        return $arr;
    }

    public static function merge(array $arr): array {
        if (count($arr) <= 1) return $arr;
        $mid = (int)(count($arr) / 2);
        $left = self::merge(array_slice($arr, 0, $mid));
        $right = self::merge(array_slice($arr, $mid));
        return self::mergeArrays($left, $right);
    }

    private static function mergeArrays(array $left, array $right): array {
        $result = [];
        $i = $j = 0;
        while ($i < count($left) && $j < count($right)) {
            if ($left[$i] <= $right[$j]) {
                $result[] = $left[$i++];
            } else {
                $result[] = $right[$j++];
            }
        }
        while ($i < count($left)) $result[] = $left[$i++];
        while ($j < count($right)) $result[] = $right[$j++];
        return $result;
    }

    public static function quick(array $arr): array {
        if (count($arr) <= 1) return $arr;
        $pivot = $arr[0];
        $left = $right = [];
        for ($i = 1; $i < count($arr); $i++) {
            if ($arr[$i] < $pivot) $left[] = $arr[$i];
            else $right[] = $arr[$i];
        }
        return array_merge(self::quick($left), [$pivot], self::quick($right));
    }

    public static function counting(array $arr): array {
        if (empty($arr)) return $arr;
        $min = min($arr);
        $max = max($arr);
        $range = $max - $min + 1;
        $count = array_fill(0, $range, 0);
        foreach ($arr as $v) $count[$v - $min]++;
        $result = [];
        foreach ($count as $i => $c) {
            for ($j = 0; $j < $c; $j++) $result[] = $i + $min;
        }
        return $result;
    }
}

class Searcher {
    public static function linear(array $arr, mixed $target): int {
        for ($i = 0; $i < count($arr); $i++) {
            if ($arr[$i] === $target) return $i;
        }
        return -1;
    }

    public static function binary(array $arr, mixed $target): int {
        $lo = 0;
        $hi = count($arr) - 1;
        while ($lo <= $hi) {
            $mid = (int)(($lo + $hi) / 2);
            if ($arr[$mid] === $target) return $mid;
            if ($arr[$mid] < $target) $lo = $mid + 1;
            else $hi = $mid - 1;
        }
        return -1;
    }

    public static function binaryLeftmost(array $arr, mixed $target): int {
        $lo = 0;
        $hi = count($arr);
        while ($lo < $hi) {
            $mid = (int)(($lo + $hi) / 2);
            if ($arr[$mid] < $target) $lo = $mid + 1;
            else $hi = $mid;
        }
        return $lo;
    }

    public static function interpolation(array $arr, int $target): int {
        $lo = 0;
        $hi = count($arr) - 1;
        while ($lo <= $hi && $target >= $arr[$lo] && $target <= $arr[$hi]) {
            if ($lo === $hi) {
                return $arr[$lo] === $target ? $lo : -1;
            }
            $pos = $lo + (int)(($target - $arr[$lo]) * ($hi - $lo) / ($arr[$hi] - $arr[$lo]));
            if ($arr[$pos] === $target) return $pos;
            if ($arr[$pos] < $target) $lo = $pos + 1;
            else $hi = $pos - 1;
        }
        return -1;
    }
}

// === 测试 ===
$data = [64, 34, 25, 12, 22, 11, 90, 1, 45, 33];
echo "Original: " . implode(', ', $data) . "\n\n";

echo "Bubble:    " . implode(', ', Sorter::bubble($data)) . "\n";
echo "Selection: " . implode(', ', Sorter::selection($data)) . "\n";
echo "Insertion: " . implode(', ', Sorter::insertion($data)) . "\n";
echo "Merge:     " . implode(', ', Sorter::merge($data)) . "\n";
echo "Quick:     " . implode(', ', Sorter::quick($data)) . "\n";
echo "Counting:  " . implode(', ', Sorter::counting($data)) . "\n";

// 验证所有排序结果一致
$expected = Sorter::quick($data);
$allSame = Sorter::bubble($data) === $expected
    && Sorter::selection($data) === $expected
    && Sorter::insertion($data) === $expected
    && Sorter::merge($data) === $expected
    && Sorter::counting($data) === $expected;
echo "\nAll sort results identical: " . var_export($allSame, true) . "\n";

// 排序后用于搜索
$sorted = $expected;
echo "\nSorted: " . implode(', ', $sorted) . "\n";

// 搜索测试
echo "\n--- Search ---\n";
$targets = [22, 90, 1, 100, 45];
foreach ($targets as $t) {
    $linIdx = Searcher::linear($sorted, $t);
    $binIdx = Searcher::binary($sorted, $t);
    echo "  $t: linear=$linIdx, binary=$binIdx";
    if ($t >= 0 && $t <= 100) {
        $interpIdx = Searcher::interpolation($sorted, $t);
        echo ", interp=$interpIdx";
    }
    echo "\n";
}

// 左边界搜索（重复元素）
$dup = [1, 2, 2, 2, 3, 4, 4, 5];
echo "\nDuplicate array: " . implode(', ', $dup) . "\n";
echo "Leftmost 2: " . Searcher::binaryLeftmost($dup, 2) . "\n";
echo "Leftmost 4: " . Searcher::binaryLeftmost($dup, 4) . "\n";
echo "Leftmost 1: " . Searcher::binaryLeftmost($dup, 1) . "\n";
echo "Leftmost 6: " . Searcher::binaryLeftmost($dup, 6) . "\n";

// 字符串排序
$strings = ['banana', 'apple', 'cherry', 'date', 'elderberry'];
$sortedStrings = Sorter::quick($strings);
echo "\nString sort: " . implode(', ', $sortedStrings) . "\n";

// 自定义比较器排序
$people = [
    ['name' => 'Alice', 'age' => 30],
    ['name' => 'Bob', 'age' => 25],
    ['name' => 'Charlie', 'age' => 35],
    ['name' => 'Dave', 'age' => 28],
];
usort($people, fn($a, $b) => $a['age'] <=> $b['age']);
echo "Sort by age:\n";
foreach ($people as $p) {
    echo "  {$p['name']}: {$p['age']}\n";
}

// 空数组排序
echo "\nEmpty sort: " . json_encode(Sorter::quick([])) . "\n";
echo "Single sort: " . json_encode(Sorter::quick([42])) . "\n";

echo "=== f014 Done ===\n";
