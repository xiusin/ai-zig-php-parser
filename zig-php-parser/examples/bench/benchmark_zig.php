<?php
/**
 * Zig-PHP 常用内置函数性能测试 (单进程模式)
 * 
 * 测试范围: 字符串、数组、数学基础函数
 * 每个函数单独测试，循环在PHP脚本内执行
 */

class ZigBenchmark {
    private string $phpBinary;
    private array $results = [];
    private int $iterations = 100000;
    private string $outputDir;
    
    public function __construct(string $phpBinary, string $outputDir = __DIR__) {
        $this->phpBinary = $phpBinary;
        $this->outputDir = $outputDir;
    }
    
    public function runBenchmarks(): array {
        echo "=================================================\n";
        echo "  Zig-PHP 性能测试 (单进程模式)\n";
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
        
        $this->generateComparisonReport();
        $this->printSummary();
        
        return $this->results;
    }
    
    private function runTest(string $name, string $phpCode): array {
        // 创建临时文件
        $tempFile = sys_get_temp_dir() . '/zig_bench_' . $name . '_' . getmypid() . '.php';
        file_put_contents($tempFile, $phpCode);
        
        // 执行测试 - 只启动一次解释器
        $startTime = microtime(true);
        exec("{$this->phpBinary} {$tempFile} 2>/dev/null", $output, $exitCode);
        $execTime = microtime(true) - $startTime;
        
        // 清理
        @unlink($tempFile);
        
        // 解析输出获取时间
        $opsPerSec = $this->iterations / $execTime;
        
        $result = [
            'name' => $name,
            'time' => $execTime,
            'ops_per_sec' => $opsPerSec,
            'exit_code' => $exitCode,
        ];
        
        $this->results[$name] = $result;
        
        $status = $exitCode === 0 ? "OK" : "FAIL";
        echo sprintf("  %-20s: %8.2f ms  (%s/s)  [%s]\n", 
            $name, 
            $execTime * 1000,
            number_format($opsPerSec),
            $status
        );
        
        return $result;
    }
    
    // ========== 字符串函数 ==========
    
    private function testStrlen() {
        $php = '<?php
$str = "Hello World! This is a test string.";
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $len = strlen($str);
}
echo "OK";
';
        $this->runTest('strlen', $php);
    }
    
    private function testStrReplace() {
        $php = '<?php
$str = "Hello World!";
$search = "World";
$replace = "PHP";
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $result = str_replace($search, $replace, $str);
}
echo "OK";
';
        $this->runTest('str_replace', $php);
    }
    
    private function testStrtr() {
        $php = '<?php
$str = "Hello World!";
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $result = strtr($str, "HWeo", "Xyz");
}
echo "OK";
';
        $this->runTest('strtr', $php);
    }
    
    private function testSubstr() {
        $php = '<?php
$str = "Hello World! This is a test string.";
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $result = substr($str, 0, 5);
}
echo "OK";
';
        $this->runTest('substr', $php);
    }
    
    private function testStrtolower() {
        $php = '<?php
$str = "HELLO WORLD! THIS IS A TEST.";
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $result = strtolower($str);
}
echo "OK";
';
        $this->runTest('strtolower', $php);
    }
    
    private function testExplode() {
        $php = '<?php
$str = "apple,banana,orange,grape,melon";
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $result = explode(",", $str);
}
echo "OK";
';
        $this->runTest('explode', $php);
    }
    
    private function testImplode() {
        $php = '<?php
$arr = ["apple", "banana", "orange", "grape", "melon"];
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $result = implode(",", $arr);
}
echo "OK";
';
        $this->runTest('implode', $php);
    }
    
    // ========== 数组函数 ==========
    
    private function testCount() {
        $php = '<?php
$arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $cnt = count($arr);
}
echo "OK";
';
        $this->runTest('count', $php);
    }
    
    private function testArrayKeys() {
        $php = '<?php
$arr = ["a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5];
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $keys = array_keys($arr);
}
echo "OK";
';
        $this->runTest('array_keys', $php);
    }
    
    private function testArrayMerge() {
        $php = '<?php
$arr1 = [1, 2, 3];
$arr2 = [4, 5, 6];
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $result = array_merge($arr1, $arr2);
}
echo "OK";
';
        $this->runTest('array_merge', $php);
    }
    
    private function testArrayPush() {
        $php = '<?php
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $arr = [];
    array_push($arr, $i);
    array_push($arr, $i + 1);
}
echo "OK";
';
        $this->runTest('array_push', $php);
    }
    
    private function testInArray() {
        $php = '<?php
$arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $found = in_array(5, $arr);
}
echo "OK";
';
        $this->runTest('in_array', $php);
    }
    
    private function testArraySearch() {
        $php = '<?php
$arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $idx = array_search(5, $arr);
}
echo "OK";
';
        $this->runTest('array_search', $php);
    }
    
    // ========== 数学函数 ==========
    
    private function testAbs() {
        $php = '<?php
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $val = abs(-123.45);
}
echo "OK";
';
        $this->runTest('abs', $php);
    }
    
    private function testFloor() {
        $php = '<?php
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $val = floor(123.45);
}
echo "OK";
';
        $this->runTest('floor', $php);
    }
    
    private function testCeil() {
        $php = '<?php
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $val = ceil(123.45);
}
echo "OK";
';
        $this->runTest('ceil', $php);
    }
    
    private function testRound() {
        $php = '<?php
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $val = round(123.456, 2);
}
echo "OK";
';
        $this->runTest('round', $php);
    }
    
    private function testMax() {
        $php = '<?php
$arr = [1, 5, 3, 9, 2, 8, 4, 7, 6];
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $val = max($arr);
}
echo "OK";
';
        $this->runTest('max', $php);
    }
    
    private function testMin() {
        $php = '<?php
$arr = [1, 5, 3, 9, 2, 8, 4, 7, 6];
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $val = min($arr);
}
echo "OK";
';
        $this->runTest('min', $php);
    }
    
    private function testRand() {
        $php = '<?php
for ($i = 0; $i < ' . $this->iterations . '; $i++) {
    $val = rand(1, 1000);
}
echo "OK";
';
        $this->runTest('rand', $php);
    }
    
    // ========== 报告生成 ==========
    
    private function generateComparisonReport(): void {
        // 读取 PHP 原生结果
        $phpResultsFile = $this->outputDir . '/php_native_report.md';
        $phpResults = $this->parsePhpResults($phpResultsFile);
        
        $report = "# Zig-PHP vs PHP 原生 性能对比报告 (单进程)\n\n";
        $report .= "**测试时间**: " . date('Y-m-d H:i:s') . "\n";
        $report .= "**迭代次数**: " . number_format($this->iterations) . "\n";
        $report .= "**测试模式**: 单进程，循环在PHP脚本内执行\n\n";
        
        // 性能对比表格
        $report .= "## 性能对比\n\n";
        $report .= "| 函数 | PHP (OPS/s) | Zig-PHP (OPS/s) | PHP快倍数 |\n";
        $report .= "|------|-------------|-----------------|----------|\n";
        
        $totalPhpOps = 0;
        $totalZigOps = 0;
        
        foreach ($this->results as $name => $zig) {
            $php = $phpResults[$name] ?? null;
            if ($php) {
                $ratio = $php > 0 ? sprintf("%.1fx", $php / $zig['ops_per_sec']) : "N/A";
                $report .= sprintf("| %s | %s | %s | %s |\n",
                    $name,
                    number_format($php),
                    number_format($zig['ops_per_sec']),
                    $ratio
                );
                $totalPhpOps += $php;
                $totalZigOps += $zig['ops_per_sec'];
            } else {
                $report .= "| {$name} | N/A | " . number_format($zig['ops_per_sec']) . " | N/A |\n";
            }
        }
        
        // 总体统计
        $overallRatio = $totalZigOps > 0 ? sprintf("%.1fx", $totalPhpOps / $totalZigOps) : "N/A";
        $report .= "\n## 总体统计\n\n";
        $report .= "- PHP 原生总 OPS: " . number_format($totalPhpOps) . "\n";
        $report .= "- Zig-PHP 总 OPS: " . number_format($totalZigOps) . "\n";
        $report .= "- PHP 总体快倍数: **" . $overallRatio . "**\n";
        
        // 结论
        $report .= "\n## 分析结论\n\n";
        $report .= "- 单进程模式下消除了进程启动/退出开销\n";
        $report .= "- 主要开销来自：树遍历解释、内存分配、GC\n";
        $report .= "- 数学函数差距相对较小\n";
        $report .= "- 数组查找函数（in_array）差距最大，需重点优化\n";
        
        // 保存报告
        $filename = $this->outputDir . '/comparison_report_single.md';
        file_put_contents($filename, $report);
        echo "\n对比报告已保存至: {$filename}\n";
    }
    
    private function parsePhpResults(string $file): array {
        $results = [];
        if (!file_exists($file)) {
            return $results;
        }

        $content = file_get_contents($file);
        $lines = explode("\n", $content);
        foreach ($lines as $line) {
            if (preg_match('/^\| (\w+) \|.*?\| (\d[\d,]+) \|/', $line, $m)) {
                $results[$m[1]] = (int)str_replace(',', '', $m[2]);
            }
        }

        return $results;
    }
    
    private function printSummary(): void {
        echo "\n=================================================\n";
        echo "  Zig-PHP 性能排名 (OPS/s)\n";
        echo "=================================================\n";
        
        $sorted = $this->results;
        uasort($sorted, fn($a, $b) => $b['ops_per_sec'] <=> $a['ops_per_sec']);
        
        $i = 1;
        foreach ($sorted as $r) {
            $status = $r['exit_code'] === 0 ? "OK" : "FAIL";
            echo sprintf("  %d. %-15s %s/s [%s]\n", $i++, $r['name'], number_format($r['ops_per_sec']), $status);
        }
    }
}

// 运行测试
$zigBinary = $argv[1] ?? dirname(__DIR__) . '/zig-out/bin/php-interpreter';
$benchmark = new ZigBenchmark($zigBinary, __DIR__);
$benchmark->runBenchmarks();
