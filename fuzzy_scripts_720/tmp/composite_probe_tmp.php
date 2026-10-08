<?php
// 探针12: pass2 的 isset+in_array 复合条件 + dead 写入 + array_filter arrow 捕获
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
    new Inst('const', 'sum', []),
    new Inst('const', 'prod', []),
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
        if ($inst->dest !== '' && !isset($used[$inst->dest]) && !in_array($inst->op, ['ret', 'br', 'store'])) {
            $inst->dead = true;
            echo "MARK {$inst->dest}\n";
        }
    }
    $block->instructions = array_values(array_filter($block->instructions, fn($i) => !$i->dead));
    echo "KEPT=" . count($block->instructions) . "\n";
}
echo "DONE\n";
