#!/usr/bin/env python3
"""
AOT 模糊测试综合对比脚本
对比PHP原生执行与AOT编译执行的结果
支持多个测试目录
"""
import os
import sys
import subprocess
import tempfile
import shutil
import re
from datetime import datetime
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_executor
import threading

# 配置
SCRIPT_DIR = Path("/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser")
TEST_DIRS = [
    SCRIPT_DIR / "fuzzy_scripts_27",
    SCRIPT_DIR / "fuzzy_scripts",
]
REPORT_FILE = SCRIPT_DIR / "AOT_测试问题汇总报告.md"
PHP_BIN = "/usr/local/bin/php" if Path("/usr/local/bin/php").exists() else "php"
AOT_BIN = SCRIPT_DIR / "zig-out/bin/php-interpreter"

# 统计锁
stats_lock = threading.Lock()

# 全局统计
class Stats:
    def __init__(self):
        self.total = 0
        self.passed = 0
        self.failed_compile = 0
        self.failed_mismatch = 0
        self.failed_runtime = 0
        self.php_fail = 0
        self.skipped = 0
        self.issues = []  # 收集所有问题

stats = Stats()

def run_php(file_path: Path) -> tuple[str, int, float]:
    """运行PHP原生执行"""
    try:
        result = subprocess.run(
            [PHP_BIN, str(file_path)],
            capture_output=True,
            text=True,
            timeout=5
        )
        output = result.stdout
        if result.stderr:
            output += "\n[STDERR]\n" + result.stderr
        return output, result.returncode, 0.0
    except subprocess.TimeoutExpired:
        return "[TIMEOUT] Execution exceeded 5 seconds", -1, 0.0
    except Exception as e:
        return f"[ERROR] {e}", -1, 0.0

def compile_aot(file_path: Path, output_exe: Path) -> tuple[bool, str]:
    """编译AOT"""
    try:
        result = subprocess.run(
            [str(AOT_BIN), "--compile", f"--output={output_exe}", str(file_path)],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0:
            return False, f"{result.stderr}\n{result.stdout}"
        return True, ""
    except subprocess.TimeoutExpired:
        return False, "[TIMEOUT] Compilation exceeded 30 seconds"
    except Exception as e:
        return False, f"[ERROR] {e}"

def run_aot(exe_path: Path) -> tuple[str, int]:
    """运行AOT编译后的程序"""
    try:
        result = subprocess.run(
            [str(exe_path)],
            capture_output=True,
            text=True,
            timeout=5
        )
        output = result.stdout
        if result.stderr:
            output += "\n[STDERR]\n" + result.stderr
        return output, result.returncode
    except subprocess.TimeoutExpired:
        return "[TIMEOUT] Execution exceeded 5 seconds", -1
    except Exception as e:
        return f"[ERROR] {e}", -1

def should_skip(file_path: Path) -> tuple[bool, str]:
    """检查是否应该跳过此文件"""
    try:
        content = file_path.read_text().lower()
    except:
        return True, "Cannot read file"
    
    # 跳过包含随机性的测试
    skip_keywords = ['rand(', 'mt_rand', 'random_', 'shuffle(', 'str_shuffle']
    for kw in skip_keywords:
        if kw in content:
            return True, f"Contains randomness: {kw}"
    
    # 跳过pass目录
    if 'pass' in str(file_path):
        return True, "Already passed"
    
    return False, ""

def normalize_output(output: str) -> str:
    """标准化输出以便比较"""
    # 移除空白差异
    lines = output.strip().split('\n')
    normalized = []
    for line in lines:
        # 移除行尾空白
        normalized.append(line.rstrip())
    return '\n'.join(normalized)

def categorize_error(php_output: str, php_code: int, aot_output: str, aot_code: int, compile_error: str = "") -> str:
    """分类错误类型"""
    if compile_error:
        if "parameter" in compile_error.lower() or "argument" in compile_error.lower():
            return "COMPILE_PARAM"
        elif "type" in compile_error.lower():
            return "COMPILE_TYPE"
        elif "syntax" in compile_error.lower():
            return "COMPILE_SYNTAX"
        elif "undefined" in compile_error.lower():
            return "COMPILE_UNDEFINED"
        else:
            return "COMPILE_OTHER"
    
    if php_code != 0:
        return "PHP_FAIL"
    
    if "[TIMEOUT]" in aot_output:
        return "AOT_TIMEOUT"
    
    if "panic" in aot_output.lower() or "error:" in aot_output.lower():
        return "AOT_RUNTIME"
    
    if "segmentation fault" in aot_output.lower() or "abort trap" in aot_output.lower():
        return "AOT_CRASH"
    
    return "MISMATCH"

def test_file(file_path: Path, test_dir_name: str) -> dict:
    """测试单个文件"""
    basename = file_path.name
    
    # 检查是否应该跳过
    should_skip_result, skip_reason = should_skip(file_path)
    if should_skip_result:
        return {
            "file": basename,
            "dir": test_dir_name,
            "status": "SKIP",
            "reason": skip_reason
        }
    
    # PHP原生执行
    php_output, php_code, _ = run_php(file_path)
    
    # 检查PHP是否执行失败
    if php_code != 0 and "fatal error" in php_output.lower():
        return {
            "file": basename,
            "dir": test_dir_name,
            "status": "PHP_FAIL",
            "php_output": php_output[:1000]
        }
    
    # AOT编译
    output_exe = file_path.parent / f".test_{file_path.stem}"
    compile_ok, compile_error = compile_aot(file_path, output_exe)
    
    if not compile_ok:
        return {
            "file": basename,
            "dir": test_dir_name,
            "status": "COMPILE_FAIL",
            "compile_error": compile_error[:2000],
            "php_output": php_output[:500]
        }
    
    # AOT执行
    aot_output, aot_code = run_aot(output_exe)
    
    # 清理编译产物
    if output_exe.exists():
        output_exe.unlink()
    
    # 标准化输出对比
    php_normalized = normalize_output(php_output)
    aot_normalized = normalize_output(aot_output)
    
    if php_normalized == aot_normalized:
        return {
            "file": basename,
            "dir": test_dir_name,
            "status": "PASS"
        }
    else:
        error_type = categorize_error(php_output, php_code, aot_output, aot_code)
        return {
            "file": basename,
            "dir": test_dir_name,
            "status": error_type,
            "php_output": php_output[:2000],
            "aot_output": aot_output[:2000],
            "php_code": php_code,
            "aot_code": aot_code
        }

def process_result(result: dict, report_file):
    """处理测试结果"""
    with stats_lock:
        stats.total += 1
        
        if result["status"] == "SKIP":
            stats.skipped += 1
            print(f"  [SKIP] {result['file']} - {result['reason']}")
        elif result["status"] == "PASS":
            stats.passed += 1
            print(f"  [PASS] {result['file']}")
        elif result["status"] == "PHP_FAIL":
            stats.php_fail += 1
            print(f"  [PHP_FAIL] {result['file']}")
            stats.issues.append({
                "file": result["file"],
                "dir": result["dir"],
                "type": "PHP_FAIL",
                "desc": "PHP原生执行失败",
                "detail": result.get("php_output", "")[:500]
            })
        elif result["status"] == "COMPILE_FAIL":
            stats.failed_compile += 1
            print(f"  [COMPILE_FAIL] {result['file']}")
            stats.issues.append({
                "file": result["file"],
                "dir": result["dir"],
                "type": "COMPILE_FAIL",
                "desc": "AOT编译失败",
                "detail": result.get("compile_error", "")[:500]
            })
        elif result["status"] in ["MISMATCH", "AOT_RUNTIME", "AOT_CRASH", "AOT_TIMEOUT"]:
            if result["status"] == "MISMATCH":
                stats.failed_mismatch += 1
            else:
                stats.failed_runtime += 1
            print(f"  [{result['status']}] {result['file']}")
            stats.issues.append({
                "file": result["file"],
                "dir": result["dir"],
                "type": result["status"],
                "desc": f"AOT执行结果与PHP不一致 ({result['status']})",
                "php_output": result.get("php_output", "")[:500],
                "aot_output": result.get("aot_output", "")[:500]
            })

def collect_test_files() -> list:
    """收集所有测试文件"""
    test_files = []
    for test_dir in TEST_DIRS:
        if not test_dir.exists():
            print(f"警告: 目录不存在 {test_dir}")
            continue
        
        # 收集顶层测试文件
        for f in test_dir.glob("test_*.php"):
            test_files.append((f, test_dir.name))
        
        # 收集failed目录中的测试文件
        failed_dir = test_dir / "failed"
        if failed_dir.exists():
            for f in failed_dir.glob("test_*.php"):
                test_files.append((f, f"{test_dir.name}/failed"))
    
    return sorted(test_files, key=lambda x: x[0].name)

def generate_report():
    """生成报告"""
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write("# AOT 测试问题汇总报告\n\n")
        f.write(f"**测试时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write(f"**PHP解释器**: {PHP_BIN}\n")
        f.write(f"**AOT编译器**: {AOT_BIN}\n\n")
        
        # 测试结果汇总
        f.write("## 测试结果汇总\n\n")
        f.write("| 类型 | 数量 | 说明 |\n")
        f.write("|------|------|------|\n")
        f.write(f"| **PASS** | {stats.passed} | AOT执行结果与PHP一致 |\n")
        f.write(f"| **MISMATCH** | {stats.failed_mismatch} | AOT与PHP输出结果不一致 |\n")
        f.write(f"| **COMPILE_FAIL** | {stats.failed_compile} | AOT编译失败 |\n")
        f.write(f"| **AOT_RUNTIME** | {stats.failed_runtime} | AOT运行时失败 |\n")
        f.write(f"| **PHP_FAIL** | {stats.php_fail} | PHP原生执行失败 |\n")
        f.write(f"| **SKIP** | {stats.skipped} | 跳过测试 |\n")
        total_issues = stats.failed_compile + stats.failed_mismatch + stats.failed_runtime
        if stats.total > 0:
            pass_rate = stats.passed * 100 / (stats.total - stats.skipped - stats.php_fail)
            f.write(f"\n**通过率**: {pass_rate:.1f}% (排除PHP失败和跳过)\n\n")
        
        # 按类型分组问题
        f.write("---\n\n")
        f.write("## 问题详细列表\n\n")
        
        # 编译失败
        compile_issues = [i for i in stats.issues if i["type"] == "COMPILE_FAIL"]
        if compile_issues:
            f.write("### 1. COMPILE_FAIL - 编译失败\n\n")
            f.write("| 脚本名称 | 目录 | 错误详情 |\n")
            f.write("|----------|------|----------|\n")
            for issue in compile_issues:
                detail = issue.get("detail", "").replace("\n", " ")[:100]
                f.write(f"| {issue['file']} | {issue['dir']} | {detail} |\n")
            f.write("\n")
        
        # 输出不一致
        mismatch_issues = [i for i in stats.issues if i["type"] == "MISMATCH"]
        if mismatch_issues:
            f.write("### 2. MISMATCH - 输出不一致\n\n")
            for issue in mismatch_issues:
                f.write(f"#### {issue['file']}\n\n")
                f.write(f"**目录**: {issue['dir']}\n\n")
                f.write("**PHP输出**:\n```\n")
                f.write(issue.get("php_output", "")[:500])
                f.write("\n```\n\n")
                f.write("**AOT输出**:\n```\n")
                f.write(issue.get("aot_output", "")[:500])
                f.write("\n```\n\n")
        
        # AOT运行时错误
        runtime_issues = [i for i in stats.issues if i["type"] in ["AOT_RUNTIME", "AOT_CRASH", "AOT_TIMEOUT"]]
        if runtime_issues:
            f.write("### 3. AOT_RUNTIME - 运行时错误\n\n")
            f.write("| 脚本名称 | 目录 | 错误类型 | 详情 |\n")
            f.write("|----------|------|----------|------|\n")
            for issue in runtime_issues:
                aot_out = issue.get("aot_output", "").replace("\n", " ")[:80]
                f.write(f"| {issue['file']} | {issue['dir']} | {issue['type']} | {aot_out} |\n")
            f.write("\n")
        
        # PHP失败
        php_issues = [i for i in stats.issues if i["type"] == "PHP_FAIL"]
        if php_issues:
            f.write("### 4. PHP_FAIL - PHP原生执行失败\n\n")
            f.write("> 以下脚本在原生PHP执行时本身存在错误，不计入AOT问题统计\n\n")
            f.write("| 脚本名称 | 目录 |\n")
            f.write("|----------|------|\n")
            for issue in php_issues:
                f.write(f"| {issue['file']} | {issue['dir']} |\n")
            f.write("\n")
        
        # 问题分类汇总
        f.write("---\n\n")
        f.write("## 问题分类统计\n\n")
        
        # 分析编译错误模式
        compile_patterns = {}
        for issue in compile_issues:
            detail = issue.get("detail", "")
            # 提取关键错误信息
            if "parameter" in detail.lower() or "argument" in detail.lower():
                key = "参数数量/类型错误"
            elif "undefined" in detail.lower():
                key = "未定义的函数/类型"
            elif "type" in detail.lower():
                key = "类型错误"
            elif "syntax" in detail.lower():
                key = "语法错误"
            else:
                key = "其他编译错误"
            compile_patterns[key] = compile_patterns.get(key, 0) + 1
        
        f.write("### 编译错误类型分布\n\n")
        f.write("| 错误类型 | 数量 |\n")
        f.write("|----------|------|\n")
        for pattern, count in sorted(compile_patterns.items(), key=lambda x: -x[1]):
            f.write(f"| {pattern} | {count} |\n")
        
        f.write("\n---\n\n")
        f.write(f"*报告生成完成于 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*\n")

def main():
    """主函数"""
    # 检查编译器是否存在
    if not AOT_BIN.exists():
        print(f"错误: AOT编译器不存在 {AOT_BIN}")
        print("请先运行 zig build 编译项目")
        return 1
    
    # 检查PHP
    try:
        result = subprocess.run([PHP_BIN, "-v"], capture_output=True, text=True)
        print(f"PHP版本: {result.stdout.split('\\n')[0]}")
    except:
        print(f"警告: 无法执行PHP {PHP_BIN}")
    
    print(f"AOT编译器: {AOT_BIN}")
    print(f"报告文件: {REPORT_FILE}")
    print()
    
    # 收集测试文件
    test_files = collect_test_files()
    
    if not test_files:
        print("没有找到测试文件!")
        return 1
    
    print(f"找到 {len(test_files)} 个测试文件")
    print("=" * 60)
    print()
    
    # 测试每个文件
    with open(REPORT_FILE, "w", encoding="utf-8") as report:
        for i, (file_path, dir_name) in enumerate(test_files, 1):
            result = test_file(file_path, dir_name)
            process_result(result, report)
            
            # 每20个显示进度
            if i % 20 == 0:
                print(f"\n进度: {i}/{len(test_files)} - 通过:{stats.passed} 编译失败:{stats.failed_compile} 输出不一致:{stats.failed_mismatch} 运行时错误:{stats.failed_runtime}\n")
    
    # 生成最终报告
    generate_report()
    
    # 打印总结
    print()
    print("=" * 60)
    print("测试完成!")
    print(f"总计: {stats.total}")
    print(f"通过: {stats.passed}")
    print(f"编译失败: {stats.failed_compile}")
    print(f"输出不一致: {stats.failed_mismatch}")
    print(f"运行时错误: {stats.failed_runtime}")
    print(f"PHP失败: {stats.php_fail}")
    print(f"跳过: {stats.skipped}")
    total_issues = stats.failed_compile + stats.failed_mismatch + stats.failed_runtime
    if stats.total > 0:
        pass_rate = stats.passed * 100 / (stats.total - stats.skipped - stats.php_fail) if (stats.total - stats.skipped - stats.php_fail) > 0 else 0
        print(f"通过率: {pass_rate:.1f}%")
    print(f"报告: {REPORT_FILE}")
    print("=" * 60)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
