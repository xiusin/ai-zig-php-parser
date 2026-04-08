<?php
// 递归和复杂算法测试

// 斐波那契数列
function fib(int $n): int {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}
echo "fib(10): " . fib(10) . "\n";

// 尾递归优化模拟
function fibTail(int $n, int $a = 0, int $b = 1): int {
    if ($n === 0) return $a;
    if ($n === 1) return $b;
    return fibTail($n - 1, $b, $a + $b);
}
echo "fibTail(10): " . fibTail(10) . "\n";

// 迭代斐波那契
function fibIter(int $n): int {
    $a = 0;
    $b = 1;
    for ($i = 0; $i < $n; $i++) {
        $temp = $a + $b;
        $a = $b;
        $b = $temp;
    }
    return $a;
}
echo "fibIter(10): " . fibIter(10) . "\n";

// 阶乘
function factorial(int $n): int {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}
echo "factorial(7): " . factorial(7) . "\n";

// 二分查找
function binarySearch(array $arr, int $target): int {
    $left = 0;
    $right = count($arr) - 1;

    while ($left <= $right) {
        $mid = intdiv($left + $right, 2);
        if ($arr[$mid] === $target) return $mid;
        if ($arr[$mid] < $target) $left = $mid + 1;
        else $right = $mid - 1;
    }
    return -1;
}

$sorted = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19];
echo "binarySearch 11: " . binarySearch($sorted, 11) . "\n";
echo "binarySearch 8: " . binarySearch($sorted, 8) . "\n";

// 快速排序
function quickSort(array $arr): array {
    if (count($arr) <= 1) return $arr;

    $pivot = $arr[0];
    $left = [];
    $right = [];

    for ($i = 1; $i < count($arr); $i++) {
        if ($arr[$i] < $pivot) $left[] = $arr[$i];
        else $right[] = $arr[$i];
    }

    return array_merge(quickSort($left), [$pivot], quickSort($right));
}

$unsorted = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3];
echo "quickSort: " . implode(', ', quickSort($unsorted)) . "\n";

// 归并排序
function mergeSort(array $arr): array {
    if (count($arr) <= 1) return $arr;

    $mid = intdiv(count($arr), 2);
    $left = mergeSort(array_slice($arr, 0, $mid));
    $right = mergeSort(array_slice($arr, $mid));

    return merge($left, $right);
}

function merge(array $left, array $right): array {
    $result = [];
    $i = $j = 0;

    while ($i < count($left) && $j < count($right)) {
        if ($left[$i] <= $right[$j]) {
            $result[] = $left[$i++];
        } else {
            $result[] = $right[$j++];
        }
    }

    return array_merge($result, array_slice($left, $i), array_slice($right, $j));
}

echo "mergeSort: " . implode(', ', mergeSort($unsorted)) . "\n";

// 树遍历模拟
$tree = [
    'value' => 1,
    'left' => [
        'value' => 2,
        'left' => ['value' => 4, 'left' => null, 'right' => null],
        'right' => ['value' => 5, 'left' => null, 'right' => null]
    ],
    'right' => [
        'value' => 3,
        'left' => ['value' => 6, 'left' => null, 'right' => null],
        'right' => ['value' => 7, 'left' => null, 'right' => null]
    ]
];

// 前序遍历
function preOrder(?array $node, array &$result): void {
    if ($node === null) return;
    $result[] = $node['value'];
    preOrder($node['left'], $result);
    preOrder($node['right'], $result);
}

$preOrderResult = [];
preOrder($tree, $preOrderResult);
echo "preOrder: " . implode(', ', $preOrderResult) . "\n";

// 中序遍历
function inOrder(?array $node, array &$result): void {
    if ($node === null) return;
    inOrder($node['left'], $result);
    $result[] = $node['value'];
    inOrder($node['right'], $result);
}

$inOrderResult = [];
inOrder($tree, $inOrderResult);
echo "inOrder: " . implode(', ', $inOrderResult) . "\n";

// 后序遍历
function postOrder(?array $node, array &$result): void {
    if ($node === null) return;
    postOrder($node['left'], $result);
    postOrder($node['right'], $result);
    $result[] = $node['value'];
}

$postOrderResult = [];
postOrder($tree, $postOrderResult);
echo "postOrder: " . implode(', ', $postOrderResult) . "\n";

// 汉诺塔
function hanoi(int $n, string $from, string $to, string $aux, array &$moves): void {
    if ($n === 1) {
        $moves[] = "$from -> $to";
        return;
    }
    hanoi($n - 1, $from, $aux, $to, $moves);
    $moves[] = "$from -> $to";
    hanoi($n - 1, $aux, $to, $from, $moves);
}

$hanoiMoves = [];
hanoi(3, 'A', 'C', 'B', $hanoiMoves);
echo "hanoi moves: " . implode(', ', $hanoiMoves) . "\n";

// 深度计算
function maxDepth(?array $node): int {
    if ($node === null) return 0;
    return 1 + max(maxDepth($node['left']), maxDepth($node['right']));
}

echo "tree depth: " . maxDepth($tree) . "\n";
