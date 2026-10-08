<?php
// 探针10b: 更贴近 f095 DCE — 两遍迭代同一属性数组 + if 分支内嵌 foreach(args)
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
    new Inst('const', 'b', []),
    new Inst('add', 'sum', ['a', 'b']),
    new Inst('mul', 'prod', ['a', 'b']),
    new Inst('add', 'sum2', ['a', 'b']),
    new Inst('sub', 'diff', ['sum', 'prod']),
    new Inst('const', 'unused', []),
    new Inst('ret', '', ['diff']),
];
$blocks = [$b1];
foreach ($blocks as $block) {
    $used = [];
    foreach ($block->instructions as $inst) {
        echo "P1 {$inst->op} {$inst->dest}\n";
        if ($inst->op === 'ret' || $inst->op === 'br' || $inst->op === 'store') {
            foreach ($inst->args as $arg) {
                $used[$arg] = true;
                echo "  ADD $arg\n";
            }
        }
    }
    echo "USED=" . implode(',', array_keys($used)) . "\n";
    foreach ($block->instructions as $inst) {
        echo "P2 {$inst->op} {$inst->dest} hit=" . (isset($used[$inst->dest]) ? 'Y' : 'N') . "\n";
    }
}
echo "DONE\n";
