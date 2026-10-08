<?php
// f161 探针2：分离三个嫌疑点——fwrite 丢失 / trim / 字符串偏移读取
class M {
    private string $s = '';
    private int $pos = 0;

    public function run(string $x): void {
        fwrite(STDERR, "M0.raw\n");
        echo "E0\n";
        $this->s = trim($x);
        echo "E1.len=" . strlen($this->s) . "\n";
        $this->pos = 0;
        $c = $this->s[$this->pos];
        echo "E2.ch={$c} ne=" . var_export($c !== '<', true) . "\n";
        $d = $this->direct($x);
        echo "E3.direct_len=" . strlen($d) . "\n";
    }

    private function direct(string $x): string {
        $t = trim($x);
        $u = '<';
        echo "F0\n";
        return $t;
    }
}
$m = new M();
$m->run("<?xml version=\"1.0\"?>\n<catalog>\n</catalog>");
echo "END\n";
