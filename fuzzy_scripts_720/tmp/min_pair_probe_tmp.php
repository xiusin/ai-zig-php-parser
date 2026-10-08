<?php
// 探针19: 外层 foreach 体内 $used=[] ; 体内两个【无条件】foreach($x->args) 写 $used
class Node {
    public function __construct(public array $args = []) {}
}
$groups = [];
$g = new Node([]);
$g->args = ['a', 'b'];
$h = new Node(['c']);
$groups = [$g, $h];
$outer = [1, 2];
foreach ($outer as $k) {
    $used = [];
    foreach ($groups as $node) {
        foreach ($node->args as $arg) {
            $used[$arg] = true;
        }
        echo "SEEN $k {$node->args[0]}\n";
        foreach ($node->args as $arg) {
            $used[$arg . '!'] = true;
        }
    }
    echo "USED=" . count($used) . "\n";
}
echo "DONE\n";
