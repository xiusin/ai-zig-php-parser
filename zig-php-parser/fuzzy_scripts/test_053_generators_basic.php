<?php
// 生成器基础测试

// 基础生成器
function simpleGenerator(): Generator {
    yield 1;
    yield 2;
    yield 3;
}

$gen = simpleGenerator();
echo "Generator values:\n";
foreach ($gen as $value) {
    echo "  $value\n";
}

// 带键的生成器
function keyedGenerator(): Generator {
    yield 'a' => 1;
    yield 'b' => 2;
    yield 'c' => 3;
}

echo "Keyed generator:\n";
foreach (keyedGenerator() as $key => $value) {
    echo "  $key => $value\n";
}

// 生成器返回值
function generatorWithReturn(): Generator {
    yield 1;
    yield 2;
    return 'done';
}

$genWithReturn = generatorWithReturn();
foreach ($genWithReturn as $value) {
    echo "Yielded: $value\n";
}
echo "Return value: " . $genWithReturn->getReturn() . "\n";

// 生成器发送值
function bidirectionalGenerator(): Generator {
    $received = yield 'ready';
    echo "Received: $received\n";
    $next = yield 'processing';
    echo "Next: $next\n";
    yield 'done';
}

$bidir = bidirectionalGenerator();
echo "First: " . $bidir->current() . "\n";
$bidir->send('first value');
echo "After send\n";
$bidir->send('second value');
$bidir->next();

// 生成器抛出异常
function generatorWithException(): Generator {
    try {
        yield 'start';
        throw new Exception('Generator error');
    } catch (Exception $e) {
        yield 'caught: ' . $e->getMessage();
    }
}

foreach (generatorWithException() as $value) {
    echo "Exception gen: $value\n";
}

// 生成器方法
function rangeGenerator(int $start, int $end): Generator {
    for ($i = $start; $i <= $end; $i++) {
        yield $i;
    }
}

echo "Range generator:\n";
foreach (rangeGenerator(5, 10) as $num) {
    echo "  $num\n";
}

// 生成器当前/键/有效检查
$checkGen = simpleGenerator();
echo "Before rewind - valid: " . var_export($checkGen->valid(), true) . "\n";
$checkGen->rewind();
echo "After rewind - valid: " . var_export($checkGen->valid(), true) . "\n";
echo "Current: " . $checkGen->current() . "\n";
echo "Key: " . $checkGen->key() . "\n";

// 生成器计数
function infiniteGen(): Generator {
    $i = 0;
    while (true) {
        yield $i++;
    }
}

$inf = infiniteGen();
$count = 0;
foreach ($inf as $value) {
    if (++$count > 5) break;
    echo "Infinite gen: $value\n";
}

// yield from
function innerGen(): Generator {
    yield 1;
    yield 2;
}

function outerGen(): Generator {
    yield 0;
    yield from innerGen();
    yield 3;
}

echo "Yield from:\n";
foreach (outerGen() as $value) {
    echo "  $value\n";
}

// 生成器作为迭代器
function fileLineGenerator(string $content): Generator {
    foreach (explode("\n", $content) as $line) {
        yield trim($line);
    }
}

$content = "Line 1\nLine 2\nLine 3\n";
foreach (fileLineGenerator($content) as $line) {
    echo "File line: $line\n";
}

echo "Generator basic tests completed\n";
