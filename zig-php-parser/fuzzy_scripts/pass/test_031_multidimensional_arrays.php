<?php
// 测试31: 多维数组与复杂结构
// 3D数组
$matrix3d = [
    [[1, 2, 3], [4, 5, 6]],
    [[7, 8, 9], [10, 11, 12]]
];

// 遍历3D数组
foreach ($matrix3d as $i => $layer) {
    echo "Layer $i:\n";
    foreach ($layer as $j => $row) {
        echo "  Row $j: " . implode(", ", $row) . "\n";
    }
}

// 不规则数组
$jagged = [
    [1, 2, 3],
    [4, 5],
    [6, 7, 8, 9, 10]
];

echo "Jagged array:\n";
foreach ($jagged as $i => $row) {
    echo "  Row $i (size=" . count($row) . "): " . implode(", ", $row) . "\n";
}

// 混合类型数组
$mixed = [
    'string' => 'value',
    'number' => 42,
    'array' => ['a', 'b'],
    'nested' => [
        'deep' => [
            'deeper' => [
                'value' => 'found me!'
            ]
        ]
    ]
];

// 深度访问
echo "Deep value: " . $mixed['nested']['deep']['deeper']['value'] . "\n";

// 数组_column多维
$records = [
    ['id' => 1, 'name' => 'Alice', 'data' => ['score' => 85]],
    ['id' => 2, 'name' => 'Bob', 'data' => ['score' => 92]],
    ['id' => 3, 'name' => 'Charlie', 'data' => ['score' => 78]]
];

$names = array_column($records, 'name');
echo "Names: " . implode(", ", $names) . "\n";

// array_walk_recursive
$sum = 0;
array_walk_recursive($matrix3d, function($value) use (&$sum) {
    $sum += $value;
});
echo "Sum of all elements: $sum\n";

// 数组转树结构
$flat = [
    ['id' => 1, 'parent' => 0, 'name' => 'Root'],
    ['id' => 2, 'parent' => 1, 'name' => 'Child 1'],
    ['id' => 3, 'parent' => 1, 'name' => 'Child 2'],
    ['id' => 4, 'parent' => 2, 'name' => 'Grandchild']
];

function buildTree(array $flat, int $parentId = 0): array {
    $tree = [];
    foreach ($flat as $item) {
        if ($item['parent'] === $parentId) {
            $children = buildTree($flat, $item['id']);
            if ($children) {
                $item['children'] = $children;
            }
            $tree[] = $item;
        }
    }
    return $tree;
}

$tree = buildTree($flat);
echo "Tree structure:\n";
print_r($tree);

// 矩阵转置
function transpose(array $matrix): array {
    return array_map(null, ...$matrix);
}

$original = [[1, 2, 3], [4, 5, 6]];
$transposed = transpose($original);
echo "Transposed matrix:\n";
foreach ($transposed as $row) {
    echo "  " . implode(", ", $row) . "\n";
}
?>
