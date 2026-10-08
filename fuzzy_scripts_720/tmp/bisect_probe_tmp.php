<?php
// 探针14: 变体选择 V1..V4
class Inst {
    public function __construct(public string $op, public string $dest = '', public array $args = [], public bool $dead = false) {}
}
class Box {
    public array $instructions = [];
    public function __construct(public string $name) {}
}
$b1 = new Box('b1');
$b1->instructions = [
    new Inst('const', 'a', []),
    new Inst('add', 'sum', ['a', 'b']),
    new Inst('ret', '', ['sum']),
];
$blocks = [$b1];
$mode = getenv('V') ?: 'V1';
if ($mode === 'V1') {
    $used = [];
    foreach ($blocks[0]->instructions as $inst) {
        echo "P1 {$inst->op}\n";
        if (in_array($inst->op, ['add'])) {
            foreach ($inst->args as $arg) { $used[$arg] = true; }
        }
    }
    echo "USED=" . implode(',', array_keys($used)) . "\n";
} elseif ($mode === 'V2') {
    // 第二个 if 无花括号 foreach
    $used = [];
    foreach ($blocks[0]->instructions as $inst) {
        echo "P1 {$inst->op}\n";
        if (in_array($inst->op, ['add'])) {
            foreach ($inst->args as $arg) $used[$arg] = true;
        }
    }
    echo "USED=" . implode(',', array_keys($used)) . "\n";
} elseif ($mode === 'V3') {
    // 仅单个 foreach 迭代 $inst->args（无 if 包裹）
    $n = 0;
    foreach ($blocks[0]->instructions as $inst) {
        echo "P1 {$inst->op}\n";
        foreach ($inst->args as $arg) { $n++; }
    }
    echo "N=$n\n";
}
echo "DONE $mode\n";
