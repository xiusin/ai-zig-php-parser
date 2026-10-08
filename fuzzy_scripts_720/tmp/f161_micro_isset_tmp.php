<?php
// f161 xp8 isset-guard 微探针：定位 php_array_isset 真值来源
// T1 字面 subject + limit2（方法内守卫）
// T2 substr subject + limit2（守卫）
// T3 字面 subject 无 limit（守卫）
// T4 substr 结果先赋属性再 split（守卫）
class MICRO {
    public string $s = "  <catalog>\n";

    public function t1(): void {
        $p = preg_split('/\s+/', 'solo', 2);
        if (isset($p[1])) { echo "T1-IN c=" . count($p) . "\n"; } else { echo "T1-SKIP c=" . count($p) . "\n"; }
    }

    public function t2(): void {
        $str = substr($this->s, 3, 7);
        $p = preg_split('/\s+/', $str, 2);
        if (isset($p[1])) { echo "T2-IN c=" . count($p) . " s=[{$str}]\n"; } else { echo "T2-SKIP c=" . count($p) . " s=[{$str}]\n"; }
    }

    public function t3(): void {
        $p = preg_split('/\s+/', 'solo');
        if (isset($p[1])) { echo "T3-IN\n"; } else { echo "T3-SKIP\n"; }
    }

    public function t4(): void {
        $this->s = substr($this->s, 3, 7);
        $p = preg_split('/\s+/', $this->s, 2);
        if (isset($p[1])) { echo "T4-IN c=" . count($p) . "\n"; } else { echo "T4-SKIP c=" . count($p) . "\n"; }
    }
}
$m = new MICRO();
$m->t1();
$m->t2();
$m->t3();
$m->t4();
