<?php
// f161 前缀自增结合性探针：正确语义 bool(false) + int(1)
$g = 0;
var_dump(++$g > 500);
var_dump($g);
$h = 5;
var_dump(--$h < 0);
var_dump($h);
// 乘法结合：++$m * 2 → (++$m)*2 = 4；错误解析 ++($m*2) → 2（$m 不变）
$m = 1;
var_dump(++$m * 2);
var_dump($m);
// 幂结合：PHP 语义 ++$p ** 2 = ++($p**2)（** 高于前缀 ++）→ $p 不变、结果 5
$p = 2;
var_dump(++$p ** 2);
var_dump($p);
// 拼接结合：++$k . "-s" → "1-s"；错误 ++($k."-s") 会 fatal/临时值
$k = 0;
var_dump(++$k . "-s");
var_dump($k);
// 自减+比较组合
$j = 10;
if (--$j > 8) echo "dec-then-cmp ok j=$j\n";
echo "j=$j\n";
