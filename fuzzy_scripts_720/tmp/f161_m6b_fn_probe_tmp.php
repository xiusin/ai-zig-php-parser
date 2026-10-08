<?php
// f161 探针6b-F：与 m6b 完全同形但是自由函数（对照基线）
function v2_localAnd(): string {
    $s = '  <a>';
    $p = 0;
    $g = 0;
    while ($p < strlen($s) && ctype_space($s[$p])) {
        $p++;
        if (++$g > 500) break;
    }
    return "v2 p={$p} g={$g}";
}
echo v2_localAnd() . "\n";
