<?php
// f124 p8: calc() 连续两次调用，隔离返回值污染
class AScl {
  public function calc(array $p, int $cur): int {
    if (empty($p)) return 2;
    $t = array_sum(array_map(fn($x) => $x['c'], $p));
    $r = array_sum(array_map(fn($x) => $x['r'], $p));
    if ($r === 0) return $cur;
    $avg = ($t / $r) * 100;
    $d = (int)ceil($cur * $avg / 70.0);
    return max(2, min(10, $d));
  }
}
$a = new AScl();
$p1 = [];
for ($i = 0; $i < 3; $i++) $p1["w$i"] = ['c' => 0.6, 'r' => 0.5];
$d = $a->calc($p1, count($p1));
var_dump($d);
$p2 = [];
for ($i = 0; $i < 6; $i++) $p2["w$i"] = ['c' => 0.1, 'r' => 0.5];
$d2 = $a->calc($p2, count($p2));
var_dump($d2);
