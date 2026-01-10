<?php
// 简单测试 - 生成器迭代 (30秒超时保护)
$start = microtime(true);

class TestGen {
    public function gen() {
        yield 1;
        yield 2;
        yield 3;
    }
}

$gen = new TestGen();
$result = $gen->gen();
echo "Created generator object\n";
echo "Class: " . get_class($result) . "\n";

// 简单迭代
$i = 0;
foreach ($result as $value) {
    $i++;
    echo "Got value: $value\n";
    if ($i > 100) {
        echo "Too many iterations, stopping\n";
        break;
    }
    // 30秒超时检查
    if ((microtime(true) - $start) > 30) {
        echo "Timeout reached\n";
        break;
    }
}
echo "Foreach done, total: $i values\n";
