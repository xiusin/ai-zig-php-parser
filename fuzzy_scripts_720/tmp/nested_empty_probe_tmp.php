<?php
// 探针11: 外层 foreach 每个迭代内, 对"空数组属性"做 foreach —— 是否推进外层游标
class Row {
    public function __construct(public string $tag, public array $empty = [], public array $one = ['z']) {}
}
$rows = [];
foreach (['r1', 'r2', 'r3', 'r4', 'r5', 'r6'] as $t) { $rows[] = new Row($t); }
foreach ($rows as $r) {
    echo "OUT {$r->tag}\n";
    if ($r->tag === 'r3' or $r->tag === 'r5') {
        foreach ($r->empty as $e) { echo "  E $e\n"; }
    }
    foreach ($r->one as $o) { echo "  ONE $o\n"; }
}
echo "DONE\n";
