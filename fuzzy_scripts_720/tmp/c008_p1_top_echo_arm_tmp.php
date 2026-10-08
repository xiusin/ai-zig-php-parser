<?php
// 永久探针 C008-P1（红形）：顶层无 else 的 if/elseif 链 + 臂体以 echo 结尾 + 链后 echo
// 实测（代次 1f15e4ce）：命中 'a'/'b' 臂时链后 AFTER/END 零发射，rc=0 静默截断；
// 零臂命中（走隐式 else）时才输出链后语句。生成码中链后语句的 setSourceLocation
// 出现在最内层 `} else {` 之内 ⇒ 链后语句被并入隐式 else 臂而非链 merge 块。
$n = $argv[1];
if ($n === 'a') {
    echo "1\n";
} elseif ($n === 'b') {
    echo "2\n";
}
echo "AFTER\n";
echo "END\n";
