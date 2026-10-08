<?php
// 永久探针：隔离验证 array_walk 的 &$val 写回是否受「回调内桶搬迁」影响（AOT-REF-002 R-1b）。
// 设计要点：判据只看「写回值能否从容器读回」，刻意不打印 visited 数与 count
//   ⇒ 与 §3.1-1（持引用迭代的 live-set 语义）、§3.1-2（回调内追加导致 COW 换代）解耦，
//     使本探针只反映 R-1b 的裸槽悬垂机理。
// 区分力验收：修复前模板（Value.initRef(裸槽)）应丢写，修复后模板（make_ref 装槽）应写回。
function mk_ref002(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

// X1：回调内经 `use (&$b)` 变量句柄向被遍历容器追加 40 键（强制桶搬迁），下一轮再写 &$val
$b = mk_ref002(6);
$mut1 = 0;
array_walk($b, function (&$val, $key) use (&$b, &$mut1) {
    $mut1++;
    if ($mut1 === 1) {
        for ($j = 0; $j < 40; $j++) {
            $b['g' . $j] = -$j;
        }
    }
    if ($mut1 === 2) {
        $val = 4242;
    }
    if ($mut1 > 4) {
        return;
    }
});
echo "X1 k0=", $b['k0'], " k1=", $b['k1'], " k2=", $b['k2'], " g0=", $b['g0'] ?? 'none', "\n";

// X2：回调内经 `$r = &$c` 引用单元句柄追加（同一容器，语义上无 COW），下一轮再写 &$val
$c = mk_ref002(6);
$r = &$c;
$mut2 = 0;
array_walk($c, function (&$val, $key) use (&$r, &$mut2) {
    $mut2++;
    if ($mut2 === 1) {
        for ($j = 0; $j < 40; $j++) {
            $r['h' . $j] = $j;
        }
    }
    if ($mut2 === 2) {
        $val = 5566;
    }
    if ($mut2 > 4) {
        return;
    }
});
echo "X2 k0=", $c['k0'], " k1=", $c['k1'], " k2=", $c['k2'], " h0=", $c['h0'] ?? 'none', "\n";

// X3：对照 —— 回调内完全不碰被遍历容器，只写 &$val（R-1b 装槽的最简正路，必须两侧等值）
$d = mk_ref002(5);
array_walk($d, function (&$val, $key) {
    $val = $val * 100;
});
echo "X3 d0=", $d['k0'], " d4=", $d['k4'], "\n";
