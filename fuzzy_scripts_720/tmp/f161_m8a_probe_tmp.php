<?php
// f161 探针8a：方法 + while 单条件 + 体内 if(普通条件) break
class L {
    public function v5(): string {
        $p = 0;
        $g = 0;
        while ($p < 2) {
            $p++;
            $g++;
            if ($g > 500) break;
        }
        return "v5 p={$p} g={$g}";
    }
}
$l = new L();
echo $l->v5() . "\n";
