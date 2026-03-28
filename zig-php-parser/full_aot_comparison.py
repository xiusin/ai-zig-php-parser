#!/usr/bin/env python3
"""
AOT 完整对比测试脚本
对比PHP原生执行与AOT编译执行的结果
收集所有问题到统一文档
"""
import os
import sys
import subprocess
import shutil
import re
from datetime import datetime
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading

# 配置
SCRIPT_DIR = Path("/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser")
TEST_DIRS = [
    (SCRIPT_DIR / "fuzzy_scripts_27", "fuzzy_scripts_27"),
    (SCRIPT_DIR / "fuzzy_scripts", "fuzzy_scripts"),
]
REPORT_FILE = SCRIPT_DIR / "AOT_全面测试问题汇总报告_2026-03-27.md"
PHP_BIN = "/opt/homebrew/bin/php"
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
        self.issues = []

stats = Stats()

def run_php(file_path: Path) -> tuple[str, int]:
    """运行PHP原生执行"""
    try:
        result = subprocess.run(
            [PHP_BIN, str(file_path)],
            capture_output=True,
            text=True,
            timeout=10
        )
        output = result.stdout
        if result.stderr:
            output += "\n[STDERR]\n" + result.stderr
        return output, result.returncode
    except subprocess.TimeoutExpired:
        return "[TIMEOUT] Execution exceeded 10 seconds", -1
    except Exception as e:
        return f"[ERROR] {e}", -1

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
            timeout=10
        )
        output = result.stdout
        if result.stderr:
            output += "\n[STDERR]\n" + result.stderr
        return output, result.returncode
    except subprocess.TimeoutExpired:
        return "[TIMEOUT] Execution exceeded 10 seconds", -1
    except Exception as e:
        return f"[ERROR] {e}", -1

def should_skip(file_path: Path) -> tuple[bool, str]:
    """检查是否应该跳过此文件"""
    try:
        content = file_path.read_text(encoding='utf-8', errors='ignore').lower()
    except:
        return True, "Cannot read file"

    # 跳过包含随机性的测试
    skip_keywords = ['rand(', 'mt_rand', 'random_', 'shuffle(', 'str_shuffle']
    for kw in skip_keywords:
        if kw in content:
            return True, f"Contains randomness: {kw}"

    # 跳过Fiber和Generator相关测试
    if 'fiber' in content or 'generator' in content:
        return True, "Contains Fiber/Generator"

    return False, ""

def normalize_output(output: str) -> str:
    """标准化输出以便比较"""
    lines = output.strip().split('\n')
    normalized = []
    for line in lines:
        normalized.append(line.rstrip())
    return '\n'.join(normalized)

def categorize_error(php_output: str, php_code: int, aot_output: str, aot_code: int, compile_error: str = "") -> tuple[str, str]:
    """分类错误类型和详细原因"""
    if compile_error:
        if "parameter" in compile_error.lower() or "argument" in compile_error.lower():
            return "COMPILE_PARAM", "参数数量/类型错误"
        elif "type" in compile_error.lower():
            return "COMPILE_TYPE", "类型错误"
        elif "syntax" in compile_error.lower():
            return "COMPILE_SYNTAX", "语法错误"
        elif "undefined" in compile_error.lower():
            return "COMPILE_UNDEFINED", "未定义的函数/类型"
        elif "not found" in compile_error.lower():
            return "COMPILE_NOT_FOUND", "找不到符号/函数"
        elif "trait" in compile_error.lower():
            return "COMPILE_TRAIT", "Trait相关问题"
        elif "class" in compile_error.lower():
            return "COMPILE_CLASS", "类相关问题"
        else:
            return "COMPILE_OTHER", "其他编译错误"

    if php_code != 0 and "fatal error" in php_output.lower():
        return "PHP_FAIL", "PHP原生执行失败"

    if "[TIMEOUT]" in aot_output:
        return "AOT_TIMEOUT", "AOT执行超时"

    if "panic" in aot_output.lower():
        return "AOT_PANIC", "AOT运行时panic"

    if "error:" in aot_output.lower() or "error" in aot_output.lower():
        return "AOT_RUNTIME_ERROR", "AOT运行时错误"

    if "segmentation fault" in aot_output.lower() or "abort trap" in aot_output.lower():
        return "AOT_CRASH", "AOT崩溃"

    return "MISMATCH", "输出结果不一致"

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
    php_output, php_code = run_php(file_path)

    # 检查PHP是否执行失败(致命错误)
    if php_code != 0 and "fatal error" in php_output.lower():
        return {
            "file": basename,
            "dir": test_dir_name,
            "status": "PHP_FAIL",
            "php_output": php_output[:1000],
            "php_code": php_code
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
    # 清理.o文件
    o_file = file_path.parent / f".test_{file_path.stem}_zcu.o"
    if o_file.exists():
        o_file.unlink()

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
        error_type, error_desc = categorize_error(php_output, php_code, aot_output, aot_code)
        return {
            "file": basename,
            "dir": test_dir_name,
            "status": error_type,
            "desc": error_desc,
            "php_output": php_output[:2000],
            "aot_output": aot_output[:2000],
            "php_code": php_code,
            "aot_code": aot_code
        }

def process_result(result: dict):
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
                "detail": result.get("compile_error", "")[:1000]
            })
        elif result["status"] in ["MISMATCH", "AOT_TIMEOUT", "AOT_PANIC", "AOT_RUNTIME_ERROR", "AOT_CRASH"]:
            if result["status"] == "MISMATCH":
                stats.failed_mismatch += 1
            else:
                stats.failed_runtime += 1
            print(f"  [{result['status']}] {result['file']}")
            stats.issues.append({
                "file": result["file"],
                "dir": result["dir"],
                "type": result["status"],
                "desc": result.get("desc", "AOT执行问题"),
                "php_output": result.get("php_output", "")[:800],
                "aot_output": result.get("aot_output", "")[:800]
            })

def collect_test_files() -> list:
    """收集所有测试文件"""
    test_files = []
    for test_dir, dir_name in TEST_DIRS:
        if not test_dir.exists():
            print(f"警告: 目录不存在 {test_dir}")
            continue

        # 收集顶层测试文件（排除pass目录中的）
        for f in test_dir.glob("test_*.php"):
            test_files.append((f, dir_name))

        # 收集failed目录中的测试文件
        failed_dir = test_dir / "failed"
        if failed_dir.exists():
            for f in failed_dir.glob("test_*.php"):
                test_files.append((f, f"{dir_name}/failed"))

    return sorted(test_files, key=lambda x: x[0].name)

def generate_report():
    """生成完整报告"""
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write("# AOT 全面测试问题汇总报告\n\n")
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
        f.write(f"| **AOT_RUNTIME** | {stats.failed_runtime} | AOT运行时失败(崩溃/panic/超时) |\n")
        f.write(f"| **PHP_FAIL** | {stats.php_fail} | PHP原生执行失败 |\n")
        f.write(f"| **SKIP** | {stats.skipped} | 跳过测试(随机性/Generator) |\n")

        total_tested = stats.total - stats.skipped - stats.php_fail
        if total_tested > 0:
            pass_rate = stats.passed * 100 / total_tested
            f.write(f"\n**通过率**: {pass_rate:.1f}% (排除PHP失败和跳过)\n")
            f.write(f"**总计测试**: {stats.total} 个文件\n\n")

        # 按类型分组问题
        f.write("---\n\n")
        f.write("## 问题详细列表\n\n")

        # 1. 编译失败
        compile_issues = [i for i in stats.issues if i["type"] == "COMPILE_FAIL"]
        if compile_issues:
            f.write("### 1. COMPILE_FAIL - 编译失败 (共 {} 个)\n\n".format(len(compile_issues)))
            for issue in compile_issues:
                f.write(f"#### {issue['file']} (目录: {issue['dir']})\n\n")
                detail = issue.get("detail", "")
                f.write("**错误详情**:\n```\n")
                f.write(detail[:1500])
                f.write("\n```\n\n")
            f.write("\n")

        # 2. 输出不一致
        mismatch_issues = [i for i in stats.issues if i["type"] == "MISMATCH"]
        if mismatch_issues:
            f.write("### 2. MISMATCH - 输出不一致 (共 {} 个)\n\n".format(len(mismatch_issues)))
            for issue in mismatch_issues:
                f.write(f"#### {issue['file']} (目录: {issue['dir']})\n\n")
                f.write("**PHP输出**:\n```\n")
                f.write(issue.get("php_output", "")[:600])
                f.write("\n```\n\n")
                f.write("**AOT输出**:\n```\n")
                f.write(issue.get("aot_output", "")[:600])
                f.write("\n```\n\n")
            f.write("\n")

        # 3. AOT运行时错误
        runtime_issues = [i for i in stats.issues if i["type"] in ["AOT_TIMEOUT", "AOT_PANIC", "AOT_RUNTIME_ERROR", "AOT_CRASH"]]
        if runtime_issues:
            f.write("### 3. AOT_RUNTIME - 运行时错误 (共 {} 个)\n\n".format(len(runtime_issues)))
            for issue in runtime_issues:
                f.write(f"#### {issue['file']} (目录: {issue['dir']}) - {issue['desc']}\n\n")
                f.write("**PHP输出**:\n```\n")
                f.write(issue.get("php_output", "")[:400])
                f.write("\n```\n\n")
                f.write("**AOT输出**:\n```\n")
                f.write(issue.get("aot_output", "")[:800])
                f.write("\n```\n\n")
            f.write("\n")

        # 4. PHP失败
        php_issues = [i for i in stats.issues if i["type"] == "PHP_FAIL"]
        if php_issues:
            f.write("### 4. PHP_FAIL - PHP原生执行失败 (共 {} 个)\n\n".format(len(php_issues)))
            f.write("> 以下脚本在原生PHP执行时本身存在错误，不计入AOT问题统计\n\n")
            f.write("| 脚本名称 | 目录 |\n")
            f.write("|----------|------|\n")
            for issue in php_issues:
                f.write(f"| {issue['file']} | {issue['dir']} |\n")
            f.write("\n")

        # 问题分类统计
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
            elif "trait" in detail.lower():
                key = "Trait冲突/问题"
            elif "class" in detail.lower():
                key = "类相关问题"
            elif "not found" in detail.lower():
                key = "符号找不到"
            else:
                key = "其他编译错误"
            compile_patterns[key] = compile_patterns.get(key, 0) + 1

        if compile_patterns:
            f.write("### 编译错误类型分布\n\n")
            f.write("| 错误类型 | 数量 |\n")
            f.write("|----------|------|\n")
            for pattern, count in sorted(compile_patterns.items(), key=lambda x: -x[1]):
                f.write(f"| {pattern} | {count} |\n")
            f.write("\n")

        # 运行时错误分类
        runtime_patterns = {}
        for issue in runtime_issues:
            key = issue.get("desc", "其他")
            runtime_patterns[key] = runtime_patterns.get(key, 0) + 1

        if runtime_patterns:
            f.write("### 运行时错误类型分布\n\n")
            f.write("| 错误类型 | 数量 |\n")
            f.write("|----------|------|\n")
            for pattern, count in sorted(runtime_patterns.items(), key=lambda x: -x[1]):
                f.write(f"| {pattern} | {count} |\n")
            f.write("\n")

        # 按目录统计
        dir_stats = {}
        for issue in stats.issues:
            dir_name = issue.get("dir", "unknown")
            if dir_name not in dir_stats:
                dir_stats[dir_name] = {"COMPILE_FAIL": 0, "MISMATCH": 0, "AOT_RUNTIME": 0, "PHP_FAIL": 0}
            if issue["type"] in ["AOT_TIMEOUT", "AOT_PANIC", "AOT_RUNTIME_ERROR", "AOT_CRASH"]:
                dir_stats[dir_name]["AOT_RUNTIME"] += 1
            else:
                dir_stats[dir_name][issue["type"]] += 1

        if dir_stats:
            f.write("### 问题分布(按目录)\n\n")
            f.write("| 目录 | 编译失败 | 输出不一致 | 运行时错误 | PHP失败 |\n")
            f.write("|------|----------|------------|------------|--------|\n")
            for dir_name, counts in sorted(dir_stats.items()):
                f.write(f"| {dir_name} | {counts['COMPILE_FAIL']} | {counts['MISMATCH']} | {counts['AOT_RUNTIME']} | {counts['PHP_FAIL']} |\n")
            f.write("\n")

        f.write("\n---\n\n")
        f.write(f"*报告生成完成于 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*\n")

def main():
    """主函数"""
    print("=" * 70)
    print("AOT 全面对比测试")
    print("=" * 70)

    # 检查编译器是否存在
    if not AOT_BIN.exists():
        print(f"错误: AOT编译器不存在 {AOT_BIN}")
        print("请先运行 zig build 编译项目")
        return 1

    # 检查PHP
    try:
        result = subprocess.run([PHP_BIN, "-v"], capture_output=True, text=True)
        print(f"PHP版本: {result.stdout.split(chr(10))[0]}")
    except Exception as e:
        print(f"警告: 无法执行PHP {PHP_BIN}: {e}")

    print(f"AOT编译器: {AOT_BIN}")
    print(f"报告文件: {REPORT_FILE}")
    print()

    # 收集测试文件
    test_files = collect_test_files()

    if not test_files:
        print("没有找到测试文件!")
        return 1

    print(f"找到 {len(test_files)} 个测试文件")
    print("=" * 70)
    print()

    # 测试每个文件
    for i, (file_path, dir_name) in enumerate(test_files, 1):
        result = test_file(file_path, dir_name)
        process_result(result)

        # 每20个显示进度
        if i % 20 == 0:
            print(f"\n进度: {i}/{len(test_files)} - 通过:{stats.passed} 编译失败:{stats.failed_compile} 输出不一致:{stats.failed_mismatch} 运行时错误:{stats.failed_runtime}\n")

    # 生成最终报告
    generate_report()

    # 打印总结
    print()
    print("=" * 70)
    print("测试完成!")
    print(f"总计: {stats.total}")
    print(f"通过: {stats.passed}")
    print(f"编译失败: {stats.failed_compile}")
    print(f"输出不一致: {stats.failed_mismatch}")
    print(f"运行时错误: {stats.failed_runtime}")
    print(f"PHP失败: {stats.php_fail}")
    print(f"跳过: {stats.skipped}")
    total_tested = stats.total - stats.skipped - stats.php_fail
    if total_tested > 0:
        pass_rate = stats.passed * 100 / total_tested
        print(f"通过率: {pass_rate:.1f}%")
    print(f"报告: {REPORT_FILE}")
    print("=" * 70)

    return 0

if __name__ == "__main__":
    sys.exit(main())
