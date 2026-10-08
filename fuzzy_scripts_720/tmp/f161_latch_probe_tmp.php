<?php
// f161 超时组探针3：skipWhitespace 型 latch 丢失形态二分
class L {
    private string $s = '';
    private int $pos = 0;

    public function v1_andProp(string $x): string {
        // 形态1: while (pos < strlen && ctype_space(s[pos])) { pos++ }  属性版
        $this->s = $x;
        $this->pos = 0;
        $g = 0;
        while ($this->pos < strlen($this->s) && ctype_space($this->s[$this->pos])) {
            $this->pos++;
            if (++$g > 500) break;
        }
        return "v1 pos={$this->pos} g={$g}";
    }

    public function v2_localAnd(): string {
        // 形态2: 同条件但全局部变量
        $s = '  <a>';
        $p = 0;
        $g = 0;
        while ($p < strlen($s) && ctype_space($s[$p])) {
            $p++;
            if (++$g > 500) break;
        }
        return "v2 p={$p} g={$g}";
    }

    public function v3_propSingle(): string {
        // 形态3: 属性版但条件单一（无 &&）
        $this->s = '  <a>';
        $this->pos = 0;
        $g = 0;
        while (ctype_space($this->s[$this->pos])) {
            $this->pos++;
            if (++$g > 500) break;
        }
        return "v3 pos={$this->pos} g={$g}";
    }

    public function v4_propLtOnly(): string {
        // 形态4: 属性版 && 但第二条件非函数调用
        $this->s = '  <a>';
        $this->pos = 0;
        $g = 0;
        while ($this->pos < 4 && $this->s[$this->pos] == ' ') {
            $this->pos++;
            if (++$g > 500) break;
        }
        return "v4 pos={$this->pos} g={$g}";
    }

    public function v5_forProp(): string {
        // 形态5: for 循环属性版
        $this->s = '  <a>';
        $g = 0;
        for ($this->pos = 0; $this->pos < strlen($this->s) && ctype_space($this->s[$this->pos]); $this->pos++) {
            if (++$g > 500) break;
        }
        return "v5 pos={$this->pos} g={$g}";
    }
}
$l = new L();
echo $l->v1_andProp('  <a>') . "\n";
echo $l->v2_localAnd() . "\n";
echo $l->v3_propSingle() . "\n";
echo $l->v4_propLtOnly() . "\n";
echo $l->v5_forProp() . "\n";
