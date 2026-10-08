<?php
// 永久探针：AOT-CODEGEN-003（while(true) + break 未生成）当前树复测。
// 原工单的复现脚本（test_while_simple.php / rec_mini.php 等）已在清理轮次中删除，
// 本文件按工单 §复现代码 忠实重建 R1，并按「影响范围」补 R2/R3/R4 三形。
// 判据：四形 AOT 输出必须与 /opt/homebrew/bin/php 逐字节等值。

class T003 {
    private array $obj = [];
    private int $pos = 0;

    public function test(): array {
        $this->obj = [];
        $this->pos = 0;
        while (true) {
            if ($this->pos >= 2) break;
            $key = "key" . $this->pos;
            $val = $this->getValue();
            $this->obj[$key] = $val;
            $this->pos++;
        }
        return $this->obj;
    }

    private function getValue(): int {
        return 42;
    }
}

// R1 = 工单原文复现
$t = new T003();
echo "R1 " . json_encode($t->test()) . "\n";

// R2 while(true) + if/else + break + continue（短路链首条件 + 循环携带变量）
$acc = [];
$iter = 0;
while (true) {
    $iter++;
    if ($iter > 5) {
        break;
    }
    if ($iter % 2 === 0) {
        continue;
    }
    $acc[] = $iter * 10;
}
echo "R2 iter={$iter} " . json_encode($acc) . "\n";

// R3 while(true) + throw，外层 catch 后同函数二次调用（异常后状态污染形）
class T003B {
    public int $hits = 0;

    public function run(): string {
        $out = [];
        $i = 0;
        while (true) {
            $i++;
            $this->hits++;
            if ($i >= 3) {
                throw new RuntimeException("stop@{$i}");
            }
            $out[] = $i;
        }
        return implode(",", $out);
    }
}

$tb = new T003B();
$r3 = "none";
try {
    $r3 = $tb->run();
} catch (Exception $e) {
    $r3 = "caught:" . $e->getMessage();
}
$second = "none";
try {
    $second = $tb->run();
} catch (Exception $e) {
    $second = "caught:" . $e->getMessage();
}
echo "R3 first={$r3} second={$second} hits={$tb->hits}\n";

// R4 foreach 驱动 + 内层 while(true) + break（与迭代器/臂内派发家族的交叉形）
$list = [1, 2, 3];
$found = [];
foreach ($list as $li) {
    $k = 0;
    while (true) {
        $k++;
        if ($k > $li) break;
        $found[] = "{$li}-{$k}";
    }
}
echo "R4 " . json_encode($found) . " count=" . count($found) . "\n";
