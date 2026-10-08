<?php
// 探针6: 外层 foreach over 对象数组 + 体内 foreach over 属性数组, 找 segfault 最小触发
class Item {
    public function __construct(public string $name, public array $args = []) {}
}
$items = [new Item('i1', ['x']), new Item('i2', ['y']), new Item('i3', ['z'])];
$mode = getenv('MODE') ?: 'A';
if ($mode === 'A') {
    // A: 内层 foreach 直接迭代属性数组
    foreach ($items as $it) {
        echo "OUT {$it->name}\n";
        foreach ($it->args as $a) echo "  IN $a\n";
    }
} elseif ($mode === 'B') {
    // B: 内层 foreach 前向 map 写入
    $map = [];
    foreach ($items as $it) {
        echo "OUT {$it->name}\n";
        foreach ($it->args as $a) { $map[$a] = true; }
    }
    echo "MAP=" . count($map) . "\n";
} elseif ($mode === 'C') {
    // C: 条件守卫下内层 foreach（count 检查）
    $map = [];
    foreach ($items as $it) {
        echo "OUT {$it->name}\n";
        if (count($it->args) === 1) {
            foreach ($it->args as $a) { $map[$a] = true; }
        }
    }
    echo "MAP=" . count($map) . "\n";
}
echo "DONE $mode\n";
