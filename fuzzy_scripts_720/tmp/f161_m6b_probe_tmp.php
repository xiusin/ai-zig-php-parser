<?php
// f161 探针6b：仅 v2 单方法
class L {
    public function v2_localAnd(): string {
        $s = '  <a>';
        $p = 0;
        $g = 0;
        while ($p < strlen($s) && ctype_space($s[$p])) {
            $p++;
            if (++$g > 500) break;
        }
        return "v2 p={$p} g={$g}";
    }
}
$l = new L();
echo $l->v2_localAnd() . "\n";
