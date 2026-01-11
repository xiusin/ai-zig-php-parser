<?php
/**
 * PHP 常用内置函数性能测试 (原生 PHP)
 * 
 * 测试范围: 字符串、数组、数学基础函数
 * 每个函数单独测试
 */

class PHPBenchmark {
    private array $results = [];
    private int $iterations = 100000;
    private string $outputDir;
    
    public function __construct(string $outputDir = __DIR__) {
        $this->outputDir = $outputDir;
    }
    
    public function runBenchmarks(): array {
        echo "=================================================\n";
        echo "  PHP 原生性能测试\n";
        echo "  测试时间: " . date('Y-m-d H:i:s') . "\n";
        echo "  迭代次数: " . number_format($this->iterations) . "\n";
        echo "=================================================\n\n";
        
        // ========== 字符串函数 ==========
        echo "--- 字符串函数 ---\n";
        $this->testStrlen();
        $this->testStrReplace();
        $this->testStrtr();
        $this->testSubstr();
        $this->testStrtolower();
        $this->testExplode();
        $this->testImplode();
        
        // ========== 数组函数 ==========
        echo "\n--- 数组函数 ---\n";
        $this->testCount();
        $this->testArrayKeys();
        $this->testArrayMerge();
        $this->testArrayPush();
        $this->testInArray();
        $this->testArraySearch();
        
        // ========== 数学函数 ==========
        echo "\n--- 数学函数 ---\n";
        $this->testAbs();
        $this->testFloor();
        $this->testCeil();
        $this->testRound();
        $this->testMax();
        $this->testMin();
        $this->testRand();
        
        $this->generateReport();
        $this->printSummary();
        
        return $this->results;
    }
    
    private function runTest(string $name, callable $test): array {
        gc_collect_cycles();
        $startMem = memory_get_usage(true);
        
        $start = microtime(true);
        $test();
        $time = microtime(true) - $start;
        
        $endMem = memory_get_usage(true);
        $peakMem = memory_get_peak_usage(true);
        
        $opsPerSec = $this->iterations / $time;
        
        $result = [
            'name' => $name,
            'time' => $time,
            'ops_per_sec' => $opsPerSec,
            'memory' => $peakMem,
        ];
        
        $this->results[$name] = $result;
        
        echo sprintf("  %-20s: %8.2f ms  (%s/s)  内存: %s\n", 
            $name, 
            $time * 1000,
            number_format($opsPerSec),
            $this->formatBytes($peakMem)
        );
        
        return $result;
    }
    
    // ========== 字符串函数 ==========
    
    private function testStrlen() {
        $this->runTest('strlen', function() {
            $str = "Hello World! This is a test string.";
            for ($i = 0; $i < $this->iterations; $i++) {
                strlen($str);
            }
        });
    }
    
    private function testStrReplace() {
        $this->runTest('str_replace', function() {
            $str = "Hello World!";
            $search = "World";
            $replace = "PHP";
            for ($i = 0; $i < $this->iterations; $i++) {
                str_replace($search, $replace, $str);
            }
        });
    }
    
    private function testStrtr() {
        $this->runTest('strtr', function() {
            $str = "Hello World!";
            $from = "HWeo";
            $to = "Xyz";
            for ($i = 0; $i < $this->iterations; $i++) {
                strtr($str, $from, $to);
            }
        });
    }
    
    private function testSubstr() {
        $this->runTest('substr', function() {
            $str = "Hello World! This is a test string.";
            for ($i = 0; $i < $this->iterations; $i++) {
                substr($str, 0, 5);
            }
        });
    }
    
    private function testStrtolower() {
        $this->runTest('strtolower', function() {
            $str = "HELLO WORLD! THIS IS A TEST.";
            for ($i = 0; $i < $this->iterations; $i++) {
                strtolower($str);
            }
        });
    }
    
    private function testExplode() {
        $this->runTest('explode', function() {
            $str = "apple,banana,orange,grape,melon";
            for ($i = 0; $i < $this->iterations; $i++) {
                explode(',', $str);
            }
        });
    }
    
    private function testImplode() {
        $this->runTest('implode', function() {
            $arr = ["apple", "banana", "orange", "grape", "melon"];
            for ($i = 0; $i < $this->iterations; $i++) {
                implode(',', $arr);
            }
        });
    }
    
    // ========== 数组函数 ==========
    
    private function testCount() {
        $this->runTest('count', function() {
            $arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
            for ($i = 0; $i < $this->iterations; $i++) {
                count($arr);
            }
        });
    }
    
    private function testArrayKeys() {
        $this->runTest('array_keys', function() {
            $arr = ["a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5];
            for ($i = 0; $i < $this->iterations; $i++) {
                array_keys($arr);
            }
        });
    }
    
    private function testArrayMerge() {
        $this->runTest('array_merge', function() {
            $arr1 = [1, 2, 3];
            $arr2 = [4, 5, 6];
            for ($i = 0; $i < $this->iterations; $i++) {
                array_merge($arr1, $arr2);
            }
        });
    }
    
    private function testArrayPush() {
        $this->runTest('array_push', function() {
            for ($i = 0; $i < $this->iterations; $i++) {
                $arr = [];
                array_push($arr, $i);
                array_push($arr, $i + 1);
            }
        });
    }
    
    private function testInArray() {
        $this->runTest('in_array', function() {
            $arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
            for ($i = 0; $i < $this->iterations; $i++) {
                in_array(5, $arr);
            }
        });
    }
    
    private function testArraySearch() {
        $this->runTest('array_search', function() {
            $arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
            for ($i = 0; $i < $this->iterations; $i++) {
                array_search(5, $arr);
            }
        });
    }
    
    // ========== 数学函数 ==========
    
    private function testAbs() {
        $this->runTest('abs', function() {
            for ($i = 0; $i < $this->iterations; $i++) {
                abs(-123.45);
            }
        });
    }
    
    private function testFloor() {
        $this->runTest('floor', function() {
            for ($i = 0; $i < $this->iterations; $i++) {
                floor(123.45);
            }
        });
    }
    
    private function testCeil() {
        $this->runTest('ceil', function() {
            for ($i = 0; $i < $this->iterations; $i++) {
                ceil(123.45);
            }
        });
    }
    
    private function testRound() {
        $this->runTest('round', function() {
            for ($i = 0; $i < $this->iterations; $i++) {
                round(123.456, 2);
            }
        });
    }
    
    private function testMax() {
        $this->runTest('max', function() {
            $arr = [1, 5, 3, 9, 2, 8, 4, 7, 6];
            for ($i = 0; $i < $this->iterations; $i++) {
                max($arr);
            }
        });
    }
    
    private function testMin() {
        $this->runTest('min', function() {
            $arr = [1, 5, 3, 9, 2, 8, 4, 7, 6];
            for ($i = 0; $i < $this->iterations; $i++) {
                min($arr);
            }
        });
    }
    
    private function testRand() {
        $this->runTest('rand', function() {
            for ($i = 0; $i < $this->iterations; $i++) {
                rand(1, 1000);
            }
        });
    }
    
    // ========== 工具方法 ==========
    
    private function formatBytes(int $bytes): string {
        if ($bytes >= 1048576) {
            return sprintf("%.1f MB", $bytes / 1048576);
        } elseif ($bytes >= 1024) {
            return sprintf("%.1f KB", $bytes / 1024);
        }
        return $bytes . " B";
    }
    
    private function generateReport(): void {
        $report = "# PHP 原生性能测试报告\n\n";
        $report .= "**测试时间**: " . date('Y-m-d H:i:s') . "\n";
        $report .= "**迭代次数**: " . number_format($this->iterations) . "\n\n";
        
        $report .= "## 测试结果汇总\n\n";
        $report .= "| 函数 | 执行时间(ms) | OPS/s | 内存 |\n";
        $report .= "|------|-------------|-------|------|\n";
        
        foreach ($this->results as $r) {
            $report .= sprintf("| %s | %.2f | %s | %s |\n",
                $r['name'],
                $r['time'] * 1000,
                number_format($r['ops_per_sec']),
                $this->formatBytes($r['memory'])
            );
        }
        
        // 保存报告
        $filename = $this->outputDir . '/php_native_report.md';
        file_put_contents($filename, $report);
        echo "\n报告已保存至: {$filename}\n";
    }
    
    private function printSummary(): void {
        echo "\n=================================================\n";
        echo "  性能排名 (OPS/s)\n";
        echo "=================================================\n";
        
        $sorted = $this->results;
        uasort($sorted, fn($a, $b) => $b['ops_per_sec'] <=> $a['ops_per_sec']);
        
        $i = 1;
        foreach ($sorted as $r) {
            echo sprintf("  %d. %-15s %s/s\n", $i++, $r['name'], number_format($r['ops_per_sec']));
        }
    }
    
    public function getResults(): array {
        return $this->results;
    }
}

// 运行测试
$benchmark = new PHPBenchmark(__DIR__);
$benchmark->runBenchmarks();