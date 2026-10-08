<?php
// 探针13: pass1 两个并列 if：第一个(三路 or + 内嵌 foreach args)，第二个(in_array 六操作符 + 内嵌 foreach args 无花括号)
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
    new Inst('ret', '', ['sum']),
];
$blocks = [$b1];
foreach ($blocks as $block) {
    $used = [];
    foreach ($block->instructions as $inst) {
        echo "P1 {$inst->op} {$inst->dest}\n";
        if ($inst->op === 'ret' || $inst->op === 'br' || $inst->op === 'store') {
            foreach ($inst->args as $arg) {
                $used[$arg] = true;
                echo "  ADD1 $arg\n";
            }
        }
        if (in_array($inst->op, ['add', 'sub', 'mul', 'div', 'load', 'cmp'])) {
            foreach ($inst->args as $arg) $used[$arg] = true;
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
