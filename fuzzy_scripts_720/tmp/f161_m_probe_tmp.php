<?php
// f161 探针5：同一 while 形态在自由函数 vs 类方法
function fm(): string {
    $s = '  <a>';
    $p = 0;
    $g = 0;
    while ($p < strlen($s) && ctype_space($s[$p])) {
        $p++;
        $g++;
        if ($g > 500) break;
    }
    return "fn p={$p} g={$g}";
}

class C {
    public function m(): string {
        $s = '  <a>';
        $p = 0;
        $g = 0;
        while ($p < strlen($s) && ctype_space($s[$p])) {
            $p++;
            $g++;
            if ($g > 500) break;
        }
        return "m p={$p} g={$g}";
    }

    public function m2(): string {
        // 无 && 短路的方法版
        $s = '  <a>';
        $p = 0;
        while ($p < 5) {
            $p++;
        }
        return "m2 p={$p}";
    }

    public function m3(string $x): string {
        // 带参数+方法调用链
        $s = $this->id($x);
        $p = 0;
        $g = 0;
        while ($p < strlen($s) && ctype_space($s[$p])) {
            $p++;
            $g++;
        }
        return "m3 p={$p} g={$g}";
    }

    private function id(string $v): string {
        return $v;
    }
}

echo fm() . "\n";
echo (new C)->m() . "\n";
echo (new C)->m2() . "\n";
echo (new C)->m3('  <a>') . "\n";
