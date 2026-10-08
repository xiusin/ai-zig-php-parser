<?php
// 探针3: foreach 构建 map + arrow fn 捕获该 map 做 array_filter
// (复刻 DCE 第二遍的 $block->instructions = array_values(array_filter(..., fn($i) => !$i->dead)))
class Inst {
    public function __construct(public string $dest, public bool $dead = false) {}
}
$insts = [new Inst('a'), new Inst('b'), new Inst('c')];
$dead_set = [];
foreach ($insts as $k => $i) {
    if ($k === 1) {
        $i->dead = true;
        $dead_set[$i->dest] = true;
    }
}
$kept = array_values(array_filter($insts, fn($i) => !$i->dead));
echo "kept=" . count($kept) . "\n";
// 再验证捕获普通 map
$map = [];
$nums = [1, 2, 3, 4];
foreach ($nums as $n) {
    if ($n > 2) $map[$n] = true;
}
$big = array_filter($nums, fn($n) => isset($map[$n]));
echo "big=" . implode(',', array_keys($big)) . "\n";
