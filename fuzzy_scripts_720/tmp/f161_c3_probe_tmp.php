<?php
// f161 探针3：while + 外层if-else + then臂内单语句if(带break) + 其后 $out[]=方法调用
class W {
    private int $pos = 0;
    public function run(): array {
        $out = [];
        $guard = 0;
        while ($this->pos < 6) {
            if (++$guard > 60) { break; }
            if ($this->pos % 2 === 0) {
                if ($this->pos === 4) {
                    $this->pos = 4;
                    break;
                }
                $out[] = $this->tick($this->pos);
            } else {
                $t = $this->pos * 10;
                $out[] = "odd:$t";
            }
            $this->pos++;
        }
        return $out;
    }
    private function tick(int $p): string {
        echo "tick$p\n";
        return "e$p";
    }
}
$r = (new W())->run();
echo implode(",", $r) . "\n";
