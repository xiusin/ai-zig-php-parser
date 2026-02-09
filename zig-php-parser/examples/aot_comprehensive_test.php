<?php
/**
 * 复杂 PHP 测试脚本 - 验证 AOT 编译器所有优化
 * 
 * 测试覆盖：
 * 1. 标量替换 - 小对象分配
 * 2. GVN - 冗余计算消除
 * 3. SCCP - 常量传播
 * 4. SLP 向量化 - 同构操作
 * 5. 多面体优化 - 嵌套循环
 * 6. 循环向量化 - 数组操作
 * 7. 去虚化 - 虚方法调用
 * 8. 边界检查消除 - 数组访问
 * 9. 动态代码消除 - eval/动态调用
 * 10. 反射优化 - 元数据访问
 */

// ============================================================================
// 1. 标量替换测试 - 小对象分配
// ============================================================================
class Point {
    public float $x;
    public float $y;
    
    public function __construct(float $x, float $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function distance(): float {
        return sqrt($this->x * $this->x + $this->y * $this->y);
    }
}

function testScalarReplacement(): float {
    $sum = 0.0;
    for ($i = 0; $i < 1000; $i++) {
        $p = new Point($i, $i * 2);  // 应被标量替换
        $sum += $p->distance();
    }
    return $sum;
}

// ============================================================================
// 2. GVN 测试 - 冗余计算消除
// ============================================================================
function testGVN(int $x, int $y): int {
    $a = $x + $y;
    $b = $x + $y;  // 冗余计算，应被 GVN 消除
    $c = $a + $b;
    $d = $x + $y;  // 再次冗余
    return $c + $d;
}

// ============================================================================
// 3. SCCP 测试 - 常量传播
// ============================================================================
function testSCCP(): int {
    $x = 10;  // 常量
    if ($x > 5) {
        $y = $x + 20;  // 应被折叠为 30
    } else {
        $y = $x - 5;   // 死代码，应被消除
    }
    return $y;
}

// ============================================================================
// 4. SLP 向量化测试 - 同构操作
// ============================================================================
function testSLPVectorization(array $a, array $b): array {
    $result = [];
    $result[0] = $a[0] + $b[0];  // 应被打包为向量操作
    $result[1] = $a[1] + $b[1];
    $result[2] = $a[2] + $b[2];
    $result[3] = $a[3] + $b[3];
    return $result;
}

// ============================================================================
// 5. 多面体优化测试 - 嵌套循环
// ============================================================================
function testPolyhedralOptimization(): array {
    $matrix = array_fill(0, 100, array_fill(0, 100, 0));
    
    // 嵌套循环，应被多面体优化（循环分块）
    for ($i = 0; $i < 100; $i++) {
        for ($j = 0; $j < 100; $j++) {
            $matrix[$i][$j] = $i * 100 + $j;
        }
    }
    
    return $matrix;
}

// ============================================================================
// 6. 循环向量化测试 - 数组操作
// ============================================================================
function testLoopVectorization(array $input): array {
    $output = [];
    
    // 简单循环，应被向量化
    for ($i = 0; $i < count($input); $i++) {
        $output[$i] = $input[$i] * 2.0;
    }
    
    return $output;
}

// ============================================================================
// 7. 去虚化测试 - 虚方法调用
// ============================================================================
interface Shape {
    public function area(): float;
}

class Circle implements Shape {
    private float $radius;
    
    public function __construct(float $radius) {
        $this->radius = $radius;
    }
    
    public function area(): float {
        return 3.14159 * $this->radius * $this->radius;
    }
}

class Rectangle implements Shape {
    private float $width;
    private float $height;
    
    public function __construct(float $width, float $height) {
        $this->width = $width;
        $this->height = $height;
    }
    
    public function area(): float {
        return $this->width * $this->height;
    }
}

function testDevirtualization(): float {
    $shapes = [
        new Circle(5.0),
        new Rectangle(10.0, 20.0),
        new Circle(3.0),
    ];
    
    $totalArea = 0.0;
    foreach ($shapes as $shape) {
        $totalArea += $shape->area();  // 虚方法调用，应被去虚化
    }
    
    return $totalArea;
}

// ============================================================================
// 8. 边界检查消除测试 - 数组访问
// ============================================================================
function testBoundsCheckElimination(array $arr): int {
    $sum = 0;
    $len = count($arr);
    
    // 循环边界已知，边界检查应被消除
    for ($i = 0; $i < $len; $i++) {
        $sum += $arr[$i];
    }
    
    return $sum;
}

// ============================================================================
// 9. 动态代码消除测试 - 常量动态调用
// ============================================================================
class Calculator {
    public function add(int $a, int $b): int {
        return $a + $b;
    }
    
    public function multiply(int $a, int $b): int {
        return $a * $b;
    }
}

function testDynamicCodeElimination(): int {
    $calc = new Calculator();
    $method = 'add';  // 常量方法名
    
    // 动态调用，但方法名是常量，应被静态化
    return $calc->$method(10, 20);
}

// ============================================================================
// 10. 反射优化测试 - 元数据访问
// ============================================================================
function testReflectionOptimization(): array {
    $reflection = new ReflectionClass(Circle::class);
    
    return [
        'name' => $reflection->getName(),
        'methods' => count($reflection->getMethods()),
        'implements' => $reflection->getInterfaceNames(),
    ];
}

// ============================================================================
// 综合测试 - 所有优化组合
// ============================================================================
function comprehensiveTest(): array {
    $results = [];
    
    // 1. 标量替换
    $results['scalar_replacement'] = testScalarReplacement();
    
    // 2. GVN
    $results['gvn'] = testGVN(100, 200);
    
    // 3. SCCP
    $results['sccp'] = testSCCP();
    
    // 4. SLP 向量化
    $results['slp'] = testSLPVectorization([1, 2, 3, 4], [5, 6, 7, 8]);
    
    // 5. 多面体优化
    $matrix = testPolyhedralOptimization();
    $results['polyhedral'] = $matrix[50][50];
    
    // 6. 循环向量化
    $input = range(1, 100);
    $output = testLoopVectorization($input);
    $results['loop_vectorization'] = array_sum($output);
    
    // 7. 去虚化
    $results['devirtualization'] = testDevirtualization();
    
    // 8. 边界检查消除
    $results['bounds_check'] = testBoundsCheckElimination(range(1, 1000));
    
    // 9. 动态代码消除
    $results['dynamic_code'] = testDynamicCodeElimination();
    
    // 10. 反射优化
    $results['reflection'] = testReflectionOptimization();
    
    return $results;
}

// ============================================================================
// 主程序
// ============================================================================
echo "=== AOT 编译器优化验证测试 ===\n\n";

$startTime = microtime(true);
$results = comprehensiveTest();
$endTime = microtime(true);

echo "测试结果：\n";
foreach ($results as $name => $value) {
    if (is_array($value)) {
        echo "  $name: " . json_encode($value) . "\n";
    } else {
        echo "  $name: $value\n";
    }
}

$executionTime = ($endTime - $startTime) * 1000;
echo "\n执行时间: " . number_format($executionTime, 2) . " ms\n";

// 内存使用统计
$memoryUsage = memory_get_peak_usage(true) / 1024 / 1024;
echo "峰值内存: " . number_format($memoryUsage, 2) . " MB\n";

echo "\n✅ 所有测试完成！\n";
