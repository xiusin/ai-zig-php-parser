<?php
// 探针17: 两层嵌套：外层 foreach ($blocks) → $block->instructions → 内层 foreach args
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
        foreach ($inst->args as $arg) {
            $used[$arg] = true;
            echo "  ADD $arg\n";
        }
    }
    echo "USED=" . implode(',', array_keys($used)) . "\n";
}
echo "DONE\n";
