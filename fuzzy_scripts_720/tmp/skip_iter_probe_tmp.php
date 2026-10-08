<?php
// 探针5: 三层 foreach + 属性数组迭代, 定位交替跳迭代缺陷
class Item {
    public function __construct(public string $name, public array $args = []) {}
}
$items = [
    new Item('i1', ['x']),
    new Item('i2', []),
    new Item('i3', ['y']),
    new Item('i4', []),
    new Item('i5', ['z']),
    new Item('i6', []),
];
$map = [];
foreach ($items as $it) {
    echo "OUT {$it->name}\n";
    if ($it->name === 'i3') {
        if (count($it->args) === 1) {
            foreach ($it->args as $a) {
                echo "  INNER {$it->name} $a\n";
                $map[$a] = true;
            }
        }
    }
    if (in_array($it->name, ['i2', 'i6'])) {
        foreach ($it->args as $a) {
            echo "  T2 $a\n";
        }
    }
}
echo "MAP=" . implode(',', array_keys($map)) . "\n";
