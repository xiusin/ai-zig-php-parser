<?php
// 探针15: 隔离缺陷 —— 内层 foreach 的无花括号单语句体写外层 map
class Inst {
    public function __construct(public string $op, public string $dest = '', public array $args = [], public bool $dead = false) {}
}
$b1 = new Inst('add', 'sum', ['a', 'b']);
$items = [$b1];
$used = [];
foreach ($items as $inst) {
    echo "P1 {$inst->op}\n";
    if (in_array($inst->op, ['add'])) {
        foreach ($inst->args as $arg) $used[$arg] = true;
    }
}
echo "USED=" . implode(',', array_keys($used)) . "\n";
echo "DONE\n";
