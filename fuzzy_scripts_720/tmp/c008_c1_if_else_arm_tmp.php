<?php
// 永久探针 C008-C1（控制臂，绿）：链「有 else」⇒ 臂尾 latch 正常，链后语句完整。
// 实测与 P1 唯一差异是补了 else 臂 ⇒ 证明共因之一是「无 else 的 if/elseif 链」。
$n = $argv[1];
if ($n === 'a') {
    echo "1\n";
} else {
    echo "2\n";
}
echo "AFTER\n";
echo "END\n";
