<?php
// 排序算法对比测试

// 测试数据
$unsorted = [64, 34, 25, 12, 22, 11, 90, 45, 33, 78];

// PHP内置排序
$builtin = $unsorted;
sort($builtin);
echo "Built-in sort: " . implode(', ', $builtin) . "\n";

// 冒泡排序
function bubbleSort(array $arr): array {
    $n = count($arr);
    for ($i = 0; $i < $n - 1; $i++) {
        for ($j = 0; $j < $n - $i - 1; $j++) {
            if ($arr[$j] > $arr[$j + 1]) {
                $temp = $arr[$j];
                $arr[$j] = $arr[$j + 1];
                $arr[$j + 1] = $temp;
            }
        }
    }
    return $arr;
}
echo "Bubble sort: " . implode(', ', bubbleSort($unsorted)) . "\n";

// 选择排序
function selectionSort(array $arr): array {
    $n = count($arr);
    for ($i = 0; $i < $n - 1; $i++) {
        $minIdx = $i;
        for ($j = $i + 1; $j < $n; $j++) {
            if ($arr[$j] < $arr[$minIdx]) {
                $minIdx = $j;
            }
        }
        $temp = $arr[$i];
        $arr[$i] = $arr[$minIdx];
        $arr[$minIdx] = $temp;
    }
    return $arr;
}
echo "Selection sort: " . implode(', ', selectionSort($unsorted)) . "\n";

// 插入排序
function insertionSort(array $arr): array {
    $n = count($arr);
    for ($i = 1; $i < $n; $i++) {
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
echo "Insertion sort: " . implode(', ', insertionSort($unsorted)) . "\n";

// 快速排序
function quickSort(array $arr): array {
    if (count($arr) <= 1) return $arr;
    $pivot = $arr[0];
    $left = $right = [];
    for ($i = 1; $i < count($arr); $i++) {
        if ($arr[$i] < $pivot) $left[] = $arr[$i];
        else $right[] = $arr[$i];
    }
    return array_merge(quickSort($left), [$pivot], quickSort($right));
}
echo "Quick sort: " . implode(', ', quickSort($unsorted)) . "\n";

// 归并排序
function mergeSort(array $arr): array {
    if (count($arr) <= 1) return $arr;
    $mid = intdiv(count($arr), 2);
    $left = mergeSort(array_slice($arr, 0, $mid));
    $right = mergeSort(array_slice($arr, $mid));
    $result = [];
    $i = $j = 0;
    while ($i < count($left) && $j < count($right)) {
        if ($left[$i] <= $right[$j]) $result[] = $left[$i++];
        else $result[] = $right[$j++];
    }
    return array_merge($result, array_slice($left, $i), array_slice($right, $j));
}
echo "Merge sort: " . implode(', ', mergeSort($unsorted)) . "\n";

// 堆排序
function heapSort(array $arr): array {
    $n = count($arr);

    // 构建最大堆
    for ($i = intdiv($n, 2) - 1; $i >= 0; $i--) {
        heapify($arr, $n, $i);
    }

    // 逐个提取元素
    for ($i = $n - 1; $i > 0; $i--) {
        $temp = $arr[0];
        $arr[0] = $arr[$i];
        $arr[$i] = $temp;
        heapify($arr, $i, 0);
    }

    return $arr;
}

function heapify(array &$arr, int $n, int $i): void {
    $largest = $i;
    $left = 2 * $i + 1;
    $right = 2 * $i + 2;

    if ($left < $n && $arr[$left] > $arr[$largest]) $largest = $left;
    if ($right < $n && $arr[$right] > $arr[$largest]) $largest = $right;

    if ($largest !== $i) {
        $temp = $arr[$i];
        $arr[$i] = $arr[$largest];
        $arr[$largest] = $temp;
        heapify($arr, $n, $largest);
    }
}
echo "Heap sort: " . implode(', ', heapSort($unsorted)) . "\n";

// 验证所有排序结果一致
$expected = $builtin;
$algorithms = [
    'bubble' => bubbleSort($unsorted),
    'selection' => selectionSort($unsorted),
    'insertion' => insertionSort($unsorted),
    'quick' => quickSort($unsorted),
    'merge' => mergeSort($unsorted),
    'heap' => heapSort($unsorted)
];

echo "\nValidation:\n";
foreach ($algorithms as $name => $result) {
    $match = $result === $expected ? 'OK' : 'FAIL';
    echo "  $name: $match\n";
}

echo "\nSorting tests completed\n";
