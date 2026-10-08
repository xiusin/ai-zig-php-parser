<?php
// 探针16: 外层 foreach + pass1 两个 if 块各含内层 foreach（第二个无花括号）
class Inst {
    public function __construct(public string $op, public string $dest = '', public array $args = [], public bool $dead = false) {}
}
$b1 = new Inst('const', 'a', []);
$b2 = new Inst('add', 'sum', ['a', 'b']);
$items = [$b1, $b2];
$used = [];
foreach ($items as $inst) {
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
echo "DONE\n";
