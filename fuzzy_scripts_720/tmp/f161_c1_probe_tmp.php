<?php
// f161 递归调用探针1：while 内 $out[] = $this->tick()
class T {
    private int $n = 0;
    public function run(): array {
        $out = [];
        $i = 0;
        while ($i < 3) {
            echo "iter$i\n";
            $out[] = $this->tick();
            $i++;
        }
        return $out;
    }
    private function tick(): string {
        echo "tick\n";
        return "t";
    }
}
$r = (new T())->run();
echo count($r) . "\n";
