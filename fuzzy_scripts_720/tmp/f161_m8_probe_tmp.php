<?php
// f161 探针8：方法 + while 单条件 + 体内 if(++g>500) break
class L {
    public function v4_condNoAnd(): string {
        $s = '  <a>';
        $p = 0;
        $g = 0;
        while ($p < 2) {
            $p++;
            if (++$g > 500) break;
        }
        return "v4 p={$p} g={$g}";
    }
}
$l = new L();
echo $l->v4_condNoAnd() . "\n";
