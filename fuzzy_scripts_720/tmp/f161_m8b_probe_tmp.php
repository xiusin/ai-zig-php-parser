<?php
// f161 探针8b：方法 + while 单条件 + 体内 if(++g>500) 无 break
class L {
    public function v6(): string {
        $p = 0;
        $g = 0;
        while ($p < 2) {
            $p++;
            if (++$g > 500) { $x = 1; }
        }
        return "v6 p={$p} g={$g}";
    }
}
$l = new L();
echo $l->v6() . "\n";
