<?php
// 探针18: 两层 + $used 在外层体内重置 + 两个 if 各含内层 foreach（第二个无花括号）+ 第二遍 foreach
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
foreach ($blocks as $block) {
    $used = [];
    foreach ($block->instructions as $inst) {
        echo "P1 {$inst->op}\n";
        if ($inst->op === 'ret' || $inst->op === 'br' || $inst->op === 'store') {
            foreach ($inst->args as $arg) {
                $used[$arg] = true;
                echo "  ADD1 $arg\n";
            }
        }
        if (in_array($inst->op, ['add'])) {
            foreach ($inst->args as $arg) $used[$arg] = true;
        }
    }
    echo "USED=" . implode(',', array_keys($used)) . "\n";
    foreach ($block->instructions as $inst) {
        if ($inst->dest !== '' && !isset($used[$inst->dest])) {
            $inst->dead = true;
            echo "MARK {$inst->dest}\n";
        }
    }
    echo "P2DONE\n";
}
echo "DONE\n";
