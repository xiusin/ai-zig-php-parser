<?php
// 探针2: 外层 foreach 内两个顺序兄弟内层 foreach，pass1 体内带 if + 第三个嵌套 foreach
// (复刻 DeadCodeElimination::optimize 的 CFG 形态)
class Box {
    public function __construct(public string $name, public array $items) {}
}
$blocks = [
    new Box('b1', ['k1', 'k2']),
    new Box('b2', ['k3']),
];
$total = 0;
foreach ($blocks as $block) {
    $used = [];
    foreach ($block->items as $u) {
        if ($u === 'k1') {
            foreach ($block->items as $w) {
                $used[$w] = true;
            }
        }
        if ($u === 'k2' or $u === 'k3') {
            $used[$u] = true;
        }
    }
    foreach ($block->items as $u) {
        if (!isset($used[$u])) {
            echo "DEAD $block->name $u\n";
            $total++;
        } else {
            echo "USED $block->name $u\n";
        }
    }
}
echo "total=$total\n";
