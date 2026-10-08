<?php
// f124 p7: autoscale() 第二次调用走 elseif 臂，返回值为空 + 臂体丢失
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
function autoscale(AScl $a, array $pods): int {
  $current = count($pods);
  $desired = $a->calc($pods, $current);
  if ($desired > $current) {
    echo "UP {$current}D{$desired}\n";
    for ($i = $current; $i < $desired; $i++) { echo "  add $i\n"; }
  } elseif ($desired < $current) {
    echo "DOWN {$current}D{$desired}\n";
    $names = array_keys($pods);
    $toRemove = array_slice($names, 0, $current - $desired);
    foreach ($toRemove as $n) echo "  del $n\n";
  }
  return $desired;
}
$p1 = [];
for ($i = 0; $i < 3; $i++) $p1["w$i"] = ['c' => 0.6, 'r' => 0.5];
$d = autoscale(new AScl(), $p1);
echo "d=$d\n";
$p2 = [];
for ($i = 0; $i < 6; $i++) $p2["w$i"] = ['c' => 0.1, 'r' => 0.5];
$d2 = autoscale(new AScl(), $p2);
echo "d2=$d2\n";
