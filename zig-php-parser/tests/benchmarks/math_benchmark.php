<?php
/**
 * 数学运算性能测试
 * 
 * 测试项目：
 * - 整数运算（100,000 次迭代）
 * - 浮点运算（100,000 次迭代）
 * - 数学函数（100,000 次迭代）
 * - 复数运算
 * - 矩阵运算
 */

// 配置
const ITERATIONS = 100000;

// ============================================================================
// 整数运算测试
// ============================================================================

function test_integer_addition() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += $i;
    }
    return $result;
}

function test_integer_subtraction() {
    $result = ITERATIONS * ITERATIONS;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result -= $i;
    }
    return $result;
}

function test_integer_multiplication() {
    $result = 1;
    for ($i = 1; $i < 100; $i++) {
        $result *= $i;
        $result %= 1000000007; // 防止溢出
    }
    return $result;
}

function test_integer_division() {
    $result = 0;
    for ($i = 1; $i < ITERATIONS; $i++) {
        $result += ITERATIONS / $i;
    }
    return $result;
}

function test_integer_modulo() {
    $result = 0;
    for ($i = 1; $i < ITERATIONS; $i++) {
        $result += $i % 97;
    }
    return $result;
}

// ============================================================================
// 浮点运算测试
// ============================================================================

function test_float_addition() {
    $result = 0.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += $i * 0.1;
    }
    return $result;
}

function test_float_subtraction() {
    $result = ITERATIONS * 1.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result -= $i * 0.1;
    }
    return $result;
}

function test_float_multiplication() {
    $result = 1.0;
    for ($i = 1; $i < 1000; $i++) {
        $result *= 1.001;
    }
    return $result;
}

function test_float_division() {
    $result = 0.0;
    for ($i = 1; $i < ITERATIONS; $i++) {
        $result += ITERATIONS / ($i * 1.0);
    }
    return $result;
}

// ============================================================================
// 数学函数测试
// ============================================================================

function test_power() {
    $result = 0.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += pow(2, $i % 10);
    }
    return $result;
}

function test_sqrt() {
    $result = 0.0;
    for ($i = 1; $i < ITERATIONS; $i++) {
        $result += sqrt($i);
    }
    return $result;
}

function test_sin() {
    $result = 0.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += sin($i * 0.01);
    }
    return $result;
}

function test_cos() {
    $result = 0.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += cos($i * 0.01);
    }
    return $result;
}

function test_tan() {
    $result = 0.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += tan($i * 0.01);
    }
    return $result;
}

function test_log() {
    $result = 0.0;
    for ($i = 1; $i < ITERATIONS; $i++) {
        $result += log($i);
    }
    return $result;
}

function test_exp() {
    $result = 0.0;
    for ($i = 0; $i < 1000; $i++) {
        $result += exp($i * 0.01);
    }
    return $result;
}

function test_abs() {
    $result = 0;
    for ($i = -ITERATIONS/2; $i < ITERATIONS/2; $i++) {
        $result += abs($i);
    }
    return $result;
}

function test_floor() {
    $result = 0.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += floor($i * 0.7);
    }
    return $result;
}

function test_ceil() {
    $result = 0.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += ceil($i * 0.7);
    }
    return $result;
}

function test_round() {
    $result = 0.0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += round($i * 0.7);
    }
    return $result;
}

// ============================================================================
// 复数运算测试
// ============================================================================

class Complex {
    public $real;
    public $imag;
    
    public function __construct($real, $imag) {
        $this->real = $real;
        $this->imag = $imag;
    }
    
    public function add($other) {
        return new Complex(
            $this->real + $other->real,
            $this->imag + $other->imag
        );
    }
    
    public function multiply($other) {
        return new Complex(
            $this->real * $other->real - $this->imag * $other->imag,
            $this->real * $other->imag + $this->imag * $other->real
        );
    }
    
    public function magnitude() {
        return sqrt($this->real * $this->real + $this->imag * $this->imag);
    }
}

function test_complex_addition() {
    $a = new Complex(1.0, 2.0);
    $b = new Complex(3.0, 4.0);
    $result = new Complex(0.0, 0.0);
    
    for ($i = 0; $i < 10000; $i++) {
        $result = $result->add($a);
        $result = $result->add($b);
    }
    
    return $result->magnitude();
}

function test_complex_multiplication() {
    $a = new Complex(1.0, 2.0);
    $b = new Complex(0.9, 0.1);
    $result = new Complex(1.0, 0.0);
    
    for ($i = 0; $i < 1000; $i++) {
        $result = $result->multiply($b);
    }
    
    return $result->magnitude();
}

// ============================================================================
// 矩阵运算测试
// ============================================================================

class Matrix {
    public $data;
    public $rows;
    public $cols;
    
    public function __construct($rows, $cols) {
        $this->rows = $rows;
        $this->cols = $cols;
        $this->data = array_fill(0, $rows, array_fill(0, $cols, 0.0));
    }
    
    public function set($i, $j, $value) {
        $this->data[$i][$j] = $value;
    }
    
    public function get($i, $j) {
        return $this->data[$i][$j];
    }
    
    public function add($other) {
        $result = new Matrix($this->rows, $this->cols);
        for ($i = 0; $i < $this->rows; $i++) {
            for ($j = 0; $j < $this->cols; $j++) {
                $result->set($i, $j, $this->get($i, $j) + $other->get($i, $j));
            }
        }
        return $result;
    }
    
    public function multiply($other) {
        if ($this->cols != $other->rows) {
            throw new Exception("矩阵维度不匹配");
        }
        
        $result = new Matrix($this->rows, $other->cols);
        for ($i = 0; $i < $this->rows; $i++) {
            for ($j = 0; $j < $other->cols; $j++) {
                $sum = 0.0;
                for ($k = 0; $k < $this->cols; $k++) {
                    $sum += $this->get($i, $k) * $other->get($k, $j);
                }
                $result->set($i, $j, $sum);
            }
        }
        return $result;
    }
}

function test_matrix_addition() {
    $a = new Matrix(10, 10);
    $b = new Matrix(10, 10);
    
    // 初始化矩阵
    for ($i = 0; $i < 10; $i++) {
        for ($j = 0; $j < 10; $j++) {
            $a->set($i, $j, $i + $j);
            $b->set($i, $j, $i - $j);
        }
    }
    
    // 执行加法
    $result = $a;
    for ($i = 0; $i < 1000; $i++) {
        $result = $result->add($b);
    }
    
    return $result->get(5, 5);
}

function test_matrix_multiplication() {
    $a = new Matrix(10, 10);
    $b = new Matrix(10, 10);
    
    // 初始化矩阵
    for ($i = 0; $i < 10; $i++) {
        for ($j = 0; $j < 10; $j++) {
            $a->set($i, $j, ($i + $j) * 0.1);
            $b->set($i, $j, ($i - $j) * 0.1);
        }
    }
    
    // 执行乘法
    $result = $a;
    for ($i = 0; $i < 100; $i++) {
        $result = $result->multiply($b);
    }
    
    return $result->get(5, 5);
}

// ============================================================================
// 随机数生成测试
// ============================================================================

function test_rand() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += rand(0, 100);
    }
    return $result;
}

function test_mt_rand() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += mt_rand(0, 100);
    }
    return $result;
}

// ============================================================================
// 主测试运行器
// ============================================================================

function run_all_tests() {
    $tests = [
        // 整数运算
        'integer_addition' => 'test_integer_addition',
        'integer_subtraction' => 'test_integer_subtraction',
        'integer_multiplication' => 'test_integer_multiplication',
        'integer_division' => 'test_integer_division',
        'integer_modulo' => 'test_integer_modulo',
        
        // 浮点运算
        'float_addition' => 'test_float_addition',
        'float_subtraction' => 'test_float_subtraction',
        'float_multiplication' => 'test_float_multiplication',
        'float_division' => 'test_float_division',
        
        // 数学函数
        'power' => 'test_power',
        'sqrt' => 'test_sqrt',
        'sin' => 'test_sin',
        'cos' => 'test_cos',
        'tan' => 'test_tan',
        'log' => 'test_log',
        'exp' => 'test_exp',
        'abs' => 'test_abs',
        'floor' => 'test_floor',
        'ceil' => 'test_ceil',
        'round' => 'test_round',
        
        // 复数运算
        'complex_addition' => 'test_complex_addition',
        'complex_multiplication' => 'test_complex_multiplication',
        
        // 矩阵运算
        'matrix_addition' => 'test_matrix_addition',
        'matrix_multiplication' => 'test_matrix_multiplication',
        
        // 随机数
        'rand' => 'test_rand',
        'mt_rand' => 'test_mt_rand',
    ];
    
    $results = [];
    
    foreach ($tests as $name => $func) {
        $start = microtime(true);
        $result = call_user_func($func);
        $end = microtime(true);
        
        $time_ms = ($end - $start) * 1000;
        $results[$name] = [
            'time_ms' => $time_ms,
            'result' => $result,
        ];
        
        echo sprintf("%-30s: %10.3f ms (result: %s)\n", 
            $name, $time_ms, substr(strval($result), 0, 20));
    }
    
    return $results;
}

// 运行测试
echo "=== 数学运算性能测试 ===\n";
echo "迭代次数: " . ITERATIONS . "\n\n";

$results = run_all_tests();

echo "\n=== 测试完成 ===\n";
