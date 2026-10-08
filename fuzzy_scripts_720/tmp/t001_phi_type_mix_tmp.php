<?php
// 永久探针：AOT-TYPE-001（Phi 节点类型不匹配 ⇒ 发射 `.toInt()` 到 runtime.Value 寄存器 ⇒ 编译期
// "expected type 'runtime_lib.Value', found 'i64'"）当前树复测。
// 判据：四形必须编译通过且与 PHP 逐字节等值；gettype() 用来把「类型被误特化成原生类型」暴露出来。
// 只用整数与字符串运算，避免浮点末位差干扰逐字节比对。

// T1 循环携带变量跨臂取 int / string / float / bool 四种类型
$mixed = 0;
for ($i = 0; $i < 6; $i++) {
    if ($i === 0) {
        $mixed = "s0";
    } elseif ($i === 1) {
        $mixed = 100;
    } elseif ($i === 2) {
        $mixed = true;
    } elseif ($i === 3) {
        $mixed = 3.5;
    } elseif ($i === 4) {
        $mixed = null;
    } else {
        $mixed = "end";
    }
    $t = gettype($mixed);
    $echoed = is_string($mixed) ? $mixed : (string)(is_bool($mixed) ? ($mixed ? "T" : "F") : intval($mixed));
    echo "T1 i={$i} type={$t} v={$echoed}\n";
}
echo "T1 final_type=" . gettype($mixed) . "\n";

// T2 三元/?? 产生的混合类型 PHI 在 foreach 中累加
$vals = [1, "2", 3.0, "abc", null, 7];
$sum = 0;
$kinds = [];
foreach ($vals as $vi => $vv) {
    $cur = $vv ?? "NULL";
    $kinds[] = gettype($cur);
    if (is_numeric($cur)) {
        $sum += (int)$cur;
    } else {
        $sum += 0;
    }
}
echo "T2 sum={$sum} kinds=" . implode(",", $kinds) . "\n";

// T3 嵌套循环：外层携带 int、内层携带 string，退出边各自带 PHI
$rows = [];
for ($r = 0; $r < 3; $r++) {
    $tag = "r{$r}";
    $inner = 0;
    for ($c = 0; $c < 3; $c++) {
        if ($c === 1) {
            $inner = $inner + 10;
        } else {
            $inner = $inner + 1;
        }
    }
    $rows[] = "{$tag}:{$inner}";
}
echo "T3 " . implode("|", $rows) . "\n";

// T4 while 循环 + 函数返回混合类型 + do-while 中的类型 PHI
function pick(int $k) {
    if ($k % 3 === 0) return $k;          // int
    if ($k % 3 === 1) return "k{$k}";     // string
    return $k <=> 2;                       // int（-1/0/1）
}
$out = [];
$k = 0;
while (true) {
    $k++;
    $p = pick($k);
    $out[] = gettype($p) . ":" . (is_int($p) ? $p : (string)$p);
    if ($k >= 5) break;
}
echo "T4 " . implode(",", $out) . "\n";

$d = 0;
$acc = "";
do {
    $d++;
    $acc .= ($d % 2 === 0) ? $d : "x{$d}";
} while ($d < 4);
echo "T4b acc={$acc} d={$d}\n";
