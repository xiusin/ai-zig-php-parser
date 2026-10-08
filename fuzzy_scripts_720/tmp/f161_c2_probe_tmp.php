<?php
// f161 递归探针2：真递归（带深度参数）
class R {
    public function parse(int $d): int {
        echo "enter d=$d\n";
        $sum = 0;
        $i = 0;
        while ($i < 2) {
            echo "iter d=$d i=$i\n";
            if ($d < 2) {
                $sum += $this->parse($d + 1);
            }
            $i++;
        }
        echo "done d=$d sum=$sum\n";
        return $sum + $d;
    }
}
echo "ret=" . (new R())->parse(0) . "\n";
