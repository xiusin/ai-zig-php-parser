<?php
// f161 探针6：类内多循环方法互相污染二分
class L {
    private string $s = '';
    private int $pos = 0;

    public function v1_andProp(string $x): string {
        $this->s = $x;
        $this->pos = 0;
        $g = 0;
        while ($this->pos < strlen($this->s) && ctype_space($this->s[$this->pos])) {
            $this->pos++;
            if (++$g > 500) break;
        }
        return "v1 pos={$this->pos} g={$g}";
    }
}
$l = new L();
echo $l->v1_andProp('  <a>') . "
";
