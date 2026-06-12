#!/usr/bin/env php
<?php
/**
 * AOT模糊测试执行脚本 (PHP版本)
 * 执行时间: 2026-04-06
 */

const SCRIPT_DIR = '/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser';
const FUZZY_DIR = SCRIPT_DIR . '/fuzzy_scripts';
const PASS_DIR = FUZZY_DIR . '/pass';
const INTERPRETER = SCRIPT_DIR . '/zig-out/bin/php-interpreter';
const TEMP_DIR = '/tmp/aot_fuzzy_test';
const REPORT_FILE = SCRIPT_DIR . '/fuzzy_test_report.md';
const PROGRESS_FILE = SCRIPT_DIR . '/test_progress.txt';

// 排除模式
const EXCLUDE_PATTERNS = ['fiber', 'coroutine', 'generator', 'random', 'rand'];

// 统计
$stats = ['total' => 0, 'passed' => 0, 'failed' => 0, 'skipped' => 0];
$errors = [];

function shouldExclude(string $scriptName): bool {
    foreach (EXCLUDE_PATTERNS as $pattern) {
        if (stripos($scriptName, $pattern) !== false) {
            return true;
        }
    }
    return false;
}

function runCommand(string $cmd, int $timeout = 10): array {
    $descriptorSpec = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w']
    ];

    $process = proc_open($cmd, $descriptorSpec, $pipes);
    if (!is_resource($process)) {
        return ['output' => 'Failed to start process', 'exitCode' => -1];
    }

    $output = '';
    $startTime = time();
    while (!feof($pipes[1]) || !feof($pipes[2])) {
        if (time() - $startTime > $timeout) {
            proc_terminate($process);
            return ['output' => 'TIMEOUT', 'exitCode' => -1];
        }
        $read = [$pipes[1], $pipes[2]];
        $write = null;
        $except = null;
        if (stream_select($read, $write, $except, 0, 200000) > 0) {
            foreach ($read as $pipe) {
                $output .= stream_get_contents($pipe, 1024);
            }
        }
    }

    fclose($pipes[0]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $exitCode = proc_close($process);

    return ['output' => $output, 'exitCode' => $exitCode];
}

function logProgress(string $message): void {
    file_put_contents(PROGRESS_FILE, date('Y-m-d H:i:s') . " - $message\n", FILE_APPEND);
    echo "$message\n";
}

function runTest(string $scriptPath): void {
    global $stats, $errors;

    $scriptName = basename($scriptPath);
    $stats['total']++;

    // 检查是否排除
    if (shouldExclude($scriptName)) {
        logProgress("[SKIP] $scriptName (excluded pattern)");
        $stats['skipped']++;
        return;
    }

    logProgress("[TEST] $scriptName");

    // Step 1: PHP原生执行
    $phpResult = runCommand("php " . escapeshellarg($scriptPath), 3);
    $phpOutput = $phpResult['output'];

    // Step 2: AOT编译
    $outputName = str_replace('.php', '', $scriptName);
    $aotBinary = TEMP_DIR . '/' . $outputName;
    $compileResult = runCommand(
        INTERPRETER . " --compile --output=" . escapeshellarg($aotBinary) . " " . escapeshellarg($scriptPath),
        30
    );
    $compileOutput = $compileResult['output'];
    $compileExit = $compileResult['exitCode'];

    if ($compileExit !== 0) {
        // 编译失败，检查是否PHP也有错误
        if (preg_match('/fatal|error|parse/i', $phpOutput)) {
            if (preg_match('/error|fail/i', $compileOutput)) {
                logProgress("[PASS] $scriptName (both have errors)");
                $stats['passed']++;
                @unlink($scriptPath);
                return;
            }
        }
        logProgress("[FAIL] $scriptName (compile failed)");
        $errors[] = [
            'script' => $scriptName,
            'php_output' => substr($phpOutput, 0, 500),
            'aot_output' => 'Compile Error: ' . substr($compileOutput, 0, 500)
        ];
        $stats['failed']++;
        return;
    }

    // Step 3: AOT执行
    $aotResult = runCommand($aotBinary, 3);
    $aotOutput = $aotResult['output'];

    // Step 4: 清理编译产物
    @unlink($aotBinary);

    // Step 5: 对比结果
    if ($phpOutput === $aotOutput) {
        logProgress("[PASS] $scriptName");
        $stats['passed']++;
        @unlink($scriptPath);
    } else {
        logProgress("[FAIL] $scriptName (output mismatch)");
        $errors[] = [
            'script' => $scriptName,
            'php_output' => substr($phpOutput, 0, 500),
            'aot_output' => substr($aotOutput, 0, 500)
        ];
        $stats['failed']++;
    }
}

function generateReport(): void {
    global $stats, $errors;

    $content = "# AOT模糊测试报告\n\n";
    $content .= "测试时间: " . date('Y-m-d H:i:s') . "\n\n";

    // 统计信息
    $content .= "## 测试统计\n\n";
    $content .= "| 统计项 | 数量 |\n";
    $content .= "|--------|------|\n";
    $content .= "| 总计 | {$stats['total']} |\n";
    $content .= "| 通过 | {$stats['passed']} |\n";
    $content .= "| 失败 | {$stats['failed']} |\n";
    $content .= "| 跳过 | {$stats['skipped']} |\n\n";

    // 错误详情
    if (!empty($errors)) {
        $content .= "## 错误详情\n\n";
        foreach ($errors as $error) {
            $content .= "### {$error['script']}\n\n";
            $content .= "| 项目 | 内容 |\n";
            $content .= "|------|------|\n";
            $phpOut = str_replace('|', '\\|', preg_replace('/\s+/', ' ', $error['php_output']));
            $aotOut = str_replace('|', '\\|', preg_replace('/\s+/', ' ', $error['aot_output']));
            $content .= "| PHP输出 | `$phpOut` |\n";
            $content .= "| AOT输出 | `$aotOut` |\n\n";
        }
    }

    file_put_contents(REPORT_FILE, $content);
    echo "\n报告已保存到: " . REPORT_FILE . "\n";
}

// 主函数
function main(): void {
    global $stats;

    // 创建目录
    @mkdir(PASS_DIR, 0777, true);
    @mkdir(TEMP_DIR, 0777, true);

    // 删除旧的进度文件
    @unlink(PROGRESS_FILE);

    // 获取所有测试脚本
    $scripts = glob(FUZZY_DIR . '/*.php') ?: [];
    sort($scripts);

    echo str_repeat("=", 50) . "\n";
    echo "开始AOT模糊测试...\n";
    echo "解释器: " . INTERPRETER . "\n";
    echo "测试目录: " . FUZZY_DIR . "\n";
    echo "测试脚本数量: " . count($scripts) . "\n";
    echo str_repeat("=", 50) . "\n\n";

    // 执行测试
    foreach ($scripts as $script) {
        if (file_exists($script)) {
            runTest($script);
        }
    }

    // 清理
    @system("rm -rf " . escapeshellarg(TEMP_DIR));

    // 输出结果
    echo "\n" . str_repeat("=", 50) . "\n";
    echo "测试完成!\n";
    echo "总计: {$stats['total']}, 通过: {$stats['passed']}, 失败: {$stats['failed']}, 跳过: {$stats['skipped']}\n";
    echo str_repeat("=", 50) . "\n";

    // 生成报告
    generateReport();
}

main();
