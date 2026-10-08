<?php
// f161 探针7：方法 + while 双条件、体内无 if/break（只 $p++）
class L {
    public function v3_andOnly(): string {
        $s = '  <a>';
        $p = 0;
        while ($p < strlen($s) && ctype_space($s[$p])) {
            $p++;
        }
        return "v3 p={$p}";
    }
}
$l = new L();
echo $l->v3_andOnly() . "\n";
