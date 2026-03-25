#!/usr/bin/env python3
"""
全面 AOT 测试脚本 - 测试 fuzzy_scripts_27 和 fuzzy_scripts 目录下的所有 PHP 脚本
对比 PHP 原生执行结果和 AOT 编译执行结果，收集问题到文档
"""
import subprocess
import os
import sys
import tempfile
import json
from pathlib import Path
from datetime import datetime
from concurrent.futures import ProcessPoolExecutor, as_completed
import multiprocessing

# 配置
SCRIPT_DIR = Path("/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser")
AOT_BIN = SCRIPT_DIR / "zig-out/bin/php-interpreter"
OUTPUT_DIR = SCRIPT_DIR / "test_results"

# 超时设置（秒）
PHP_TIMEOUT = 10
AOT_COMPILE_TIMEOUT = 60
AOT_RUN_TIMEOUT = 10

# 测试目录
TEST_DIRS = [
    SCRIPT_DIR / "fuzzy_scripts_27/failed",
    SCRIPT_DIR / "fuzzy_scripts_27/pass",
    SCRIPT_DIR / "fuzzy_scripts",
]

# 结果分类
class TestResult:
    def __init__(self):
        self.passed = []           # 完全通过
        self.mismatch = []         # 输出不匹配
        self.compile_fail = []     # AOT 编译失败
        self.php_fail = []         # PHP 原生执行失败
        self.php_timeout = []      # PHP 执行超时
        self.aot_fail = []         # AOT 执行失败
        self.aot_timeout = []      # AOT 执行超时
        self.errors = []           # 其他错误

def run_test(php_file: Path) -> dict:
    """测试单个 PHP 文件，返回结果字典"""
    result = {
        "file": str(php_file.relative_to(SCRIPT_DIR)),
        "status": "unknown",
        "php_output": "",
        "php_stderr": "",
        "php_code": 0,
        "aot_output": "",
        "aot_stderr": "",
        "aot_code": 0,
        "compile_stderr": "",
        "error_msg": "",
    }
    
    tmp_dir = tempfile.mkdtemp()
    bin_path = Path(tmp_dir) / "aot_bin"
    
    try:
        # 1. PHP 原生执行
        try:
            proc = subprocess.run(
                ["php", str(php_file)],
                capture_output=True,
                text=True,
                timeout=PHP_TIMEOUT
            )
            result["php_output"] = proc.stdout
            result["php_stderr"] = proc.stderr
            result["php_code"] = proc.returncode
            
            if proc.returncode != 0:
                result["status"] = "php_fail"
                return result
        except subprocess.TimeoutExpired:
            result["status"] = "php_timeout"
            return result
        except Exception as e:
            result["status"] = "error"
            result["error_msg"] = f"PHP execution error: {e}"
            return result
        
        # 2. AOT 编译
        try:
            proc = subprocess.run(
                [str(AOT_BIN), "--compile", f"--output={bin_path}", str(php_file)],
                capture_output=True,
                text=True,
                timeout=AOT_COMPILE_TIMEOUT
            )
            result["compile_stderr"] = proc.stderr
            
            if proc.returncode != 0:
                result["status"] = "compile_fail"
                return result
        except subprocess.TimeoutExpired:
            result["status"] = "compile_fail"
            result["error_msg"] = "AOT compilation timeout"
            return result
        except Exception as e:
            result["status"] = "compile_fail"
            result["error_msg"] = f"Compilation error: {e}"
            return result
        
        # 3. AOT 执行
        try:
            os.chmod(bin_path, 0o755)
            proc = subprocess.run(
                [str(bin_path)],
                capture_output=True,
                text=True,
                timeout=AOT_RUN_TIMEOUT
            )
            result["aot_output"] = proc.stdout
            result["aot_stderr"] = proc.stderr
            result["aot_code"] = proc.returncode
            
            if proc.returncode != 0:
                result["status"] = "aot_fail"
                return result
        except subprocess.TimeoutExpired:
            result["status"] = "aot_timeout"
            return result
        except Exception as e:
            result["status"] = "aot_fail"
            result["error_msg"] = f"AOT execution error: {e}"
            return result
        
        # 4. 比较结果
        if result["php_output"] == result["aot_output"]:
            result["status"] = "passed"
        else:
            result["status"] = "mismatch"
            
    finally:
        # 清理临时文件
        import shutil
        shutil.rmtree(tmp_dir, ignore_errors=True)
    
    return result

def collect_php_files() -> list:
    """收集所有需要测试的 PHP 文件"""
    files = []
    for test_dir in TEST_DIRS:
        if not test_dir.exists():
            print(f"[WARN] Directory not found: {test_dir}")
            continue
        for php_file in sorted(test_dir.glob("*.php")):
            files.append(php_file)
    return files

def categorize_results(results: list) -> TestResult:
    """分类测试结果"""
    tr = TestResult()
    for r in results:
        status = r["status"]
        if status == "passed":
            tr.passed.append(r)
        elif status == "mismatch":
            tr.mismatch.append(r)
        elif status == "compile_fail":
            tr.compile_fail.append(r)
        elif status == "php_fail":
            tr.php_fail.append(r)
        elif status == "php_timeout":
            tr.php_timeout.append(r)
        elif status == "aot_fail":
            tr.aot_fail.append(r)
        elif status == "aot_timeout":
            tr.aot_timeout.append(r)
        else:
            tr.errors.append(r)
    return tr

def analyze_compile_error(stderr: str) -> str:
    """分析编译错误类型"""
    if not stderr:
        return "Unknown compilation error"
    
    stderr_lower = stderr.lower()
    
    if "panic" in stderr_lower:
        return "Compiler panic/crash"
    elif "error: unimplemented" in stderr_lower or "todo" in stderr_lower:
        return "Unimplemented feature"
    elif "undefined symbol" in stderr_lower or "unknown identifier" in stderr_lower:
        return "Undefined symbol/identifier"
    elif "type mismatch" in stderr_lower or "expected type" in stderr_lower:
        return "Type mismatch"
    elif "syntax" in stderr_lower or "parse" in stderr_lower:
        return "Syntax/Parsing error"
    elif "out of memory" in stderr_lower or "oom" in stderr_lower:
        return "Out of memory"
    elif "file not found" in stderr_lower or "no such file" in stderr_lower:
        return "File not found"
    else:
        return "Other compilation error"

def analyze_aot_error(stderr: str, returncode: int) -> str:
    """分析 AOT 运行时错误类型"""
    if not stderr:
        return f"Runtime error (code={returncode})"
    
    stderr_lower = stderr.lower()
    
    if "segmentation fault" in stderr_lower or "sigsegv" in stderr_lower:
        return "Segmentation fault"
    elif "assertion failed" in stderr_lower:
        return "Assertion failed"
    elif "null pointer" in stderr_lower:
        return "Null pointer dereference"
    elif "out of bounds" in stderr_lower or "index out of range" in stderr_lower:
        return "Index out of bounds"
    elif "stack overflow" in stderr_lower:
        return "Stack overflow"
    elif "division by zero" in stderr_lower:
        return "Division by zero"
    elif "unreachable" in stderr_lower:
        return "Unreachable code reached"
    else:
        return f"Runtime error: {stderr[:200]}"

def generate_report(results: TestResult, total: int, start_time: datetime) -> str:
    """生成测试报告"""
    duration = datetime.now() - start_time
    
    report_lines = []
    report_lines.append("# AOT 全面测试报告")
    report_lines.append(f"\n测试时间: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    report_lines.append(f"测试耗时: {duration}")
    report_lines.append(f"测试文件总数: {total}")
    report_lines.append("")
    
    # 统计摘要
    report_lines.append("## 测试统计摘要\n")
    report_lines.append("| 类别 | 数量 | 百分比 |")
    report_lines.append("|------|------|--------|")
    report_lines.append(f"| ✅ 通过 | {len(results.passed)} | {len(results.passed)/total*100:.1f}% |")
    report_lines.append(f"| ❌ 输出不匹配 | {len(results.mismatch)} | {len(results.mismatch)/total*100:.1f}% |")
    report_lines.append(f"| 🔴 编译失败 | {len(results.compile_fail)} | {len(results.compile_fail)/total*100:.1f}% |")
    report_lines.append(f"| 💥 AOT 执行失败 | {len(results.aot_fail)} | {len(results.aot_fail)/total*100:.1f}% |")
    report_lines.append(f"| ⏱️ AOT 执行超时 | {len(results.aot_timeout)} | {len(results.aot_timeout)/total*100:.1f}% |")
    report_lines.append(f"| ⚠️ PHP 执行失败 | {len(results.php_fail)} | {len(results.php_fail)/total*100:.1f}% |")
    report_lines.append(f"| ⏱️ PHP 执行超时 | {len(results.php_timeout)} | {len(results.php_timeout)/total*100:.1f}% |")
    report_lines.append(f"| 🐛 其他错误 | {len(results.errors)} | {len(results.errors)/total*100:.1f}% |")
    report_lines.append("")
    
    # 编译失败详细分析
    if results.compile_fail:
        report_lines.append("## 🔴 编译失败详细分析\n")
        error_types = {}
        for r in results.compile_fail:
            error_type = analyze_compile_error(r.get("compile_stderr", ""))
            if error_type not in error_types:
                error_types[error_type] = []
            error_types[error_type].append(r)
        
        for error_type, items in sorted(error_types.items(), key=lambda x: -len(x[1])):
            report_lines.append(f"### {error_type} ({len(items)} 个)\n")
            for r in items[:10]:  # 只显示前10个
                report_lines.append(f"- `{r['file']}`")
                if r.get("error_msg"):
                    report_lines.append(f"  - {r['error_msg']}")
                if r.get("compile_stderr"):
                    stderr = r["compile_stderr"][:200].replace("\n", " ")
                    report_lines.append(f"  - stderr: `{stderr}...`")
            if len(items) > 10:
                report_lines.append(f"- ... 还有 {len(items) - 10} 个类似错误")
            report_lines.append("")
    
    # AOT 执行失败详细分析
    if results.aot_fail:
        report_lines.append("## 💥 AOT 执行失败详细分析\n")
        error_types = {}
        for r in results.aot_fail:
            error_type = analyze_aot_error(r.get("aot_stderr", ""), r.get("aot_code", 0))
            if error_type not in error_types:
                error_types[error_type] = []
            error_types[error_type].append(r)
        
        for error_type, items in sorted(error_types.items(), key=lambda x: -len(x[1])):
            report_lines.append(f"### {error_type} ({len(items)} 个)\n")
            for r in items[:10]:
                report_lines.append(f"- `{r['file']}`")
                if r.get("aot_stderr"):
                    stderr = r["aot_stderr"][:200].replace("\n", " ")
                    report_lines.append(f"  - stderr: `{stderr}...`")
            if len(items) > 10:
                report_lines.append(f"- ... 还有 {len(items) - 10} 个类似错误")
            report_lines.append("")
    
    # 输出不匹配详细分析
    if results.mismatch:
        report_lines.append("## ❌ 输出不匹配详细分析\n")
        for r in results.mismatch[:20]:  # 只显示前20个
            report_lines.append(f"### {r['file']}\n")
            report_lines.append("**PHP 输出:**")
            report_lines.append("```")
            report_lines.append(r["php_output"][:500] if r["php_output"] else "(空)")
            report_lines.append("```")
            report_lines.append("**AOT 输出:**")
            report_lines.append("```")
            report_lines.append(r["aot_output"][:500] if r["aot_output"] else "(空)")
            report_lines.append("```")
            report_lines.append("")
        if len(results.mismatch) > 20:
            report_lines.append(f"*还有 {len(results.mismatch) - 20} 个输出不匹配未显示*\n")
    
    # 通过列表
    if results.passed:
        report_lines.append("## ✅ 通过的测试\n")
        report_lines.append(f"共 {len(results.passed)} 个测试通过，部分列表:\n")
        for r in results.passed[:30]:
            report_lines.append(f"- `{r['file']}`")
        if len(results.passed) > 30:
            report_lines.append(f"- ... 还有 {len(results.passed) - 30} 个通过")
        report_lines.append("")
    
    # 建议与后续行动
    report_lines.append("## 建议与后续行动\n")
    
    if results.compile_fail:
        most_common = analyze_compile_error(results.compile_fail[0].get("compile_stderr", ""))
        report_lines.append(f"1. **优先修复编译问题**: 最普遍的编译错误类型是 '{most_common}'")
    
    if results.aot_fail:
        report_lines.append("2. **运行时稳定性**: AOT 执行失败主要集中在段错误和断言失败，需要加强运行时检查")
    
    if results.mismatch:
        report_lines.append("3. **语义一致性**: 输出不匹配表明编译器生成的代码与 PHP 语义存在差异")
    
    report_lines.append("4. **测试覆盖率**: 建议增加边界条件和异常处理测试用例")
    
    return "\n".join(report_lines)

def main():
    print("=" * 70)
    print("全面 AOT 测试 - 对比 PHP 原生执行和 AOT 编译执行")
    print("=" * 70)
    
    start_time = datetime.now()
    
    # 确保输出目录存在
    OUTPUT_DIR.mkdir(exist_ok=True)
    
    # 检查 interpreter 是否存在
    if not AOT_BIN.exists():
        print(f"[ERROR] Interpreter not found: {AOT_BIN}")
        print("请先运行: zig build -Doptimize=ReleaseFast")
        sys.exit(1)
    
    # 收集所有 PHP 文件
    print("\n[1/4] 收集 PHP 测试文件...")
    php_files = collect_php_files()
    print(f"找到 {len(php_files)} 个 PHP 文件待测试")
    
    if not php_files:
        print("[ERROR] 没有找到 PHP 测试文件")
        sys.exit(1)
    
    # 执行测试
    print("\n[2/4] 执行测试 (这可能需要一段时间)...")
    results = []
    
    # 使用多进程加速测试
    max_workers = min(multiprocessing.cpu_count(), 8)
    
    with ProcessPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(run_test, f): f for f in php_files}
        completed = 0
        
        for future in as_completed(futures):
            completed += 1
            if completed % 10 == 0 or completed == len(php_files):
                print(f"  进度: {completed}/{len(php_files)} ({completed/len(php_files)*100:.1f}%)")
            
            try:
                result = future.result()
                results.append(result)
            except Exception as e:
                print(f"[ERROR] Test failed: {e}")
    
    # 分类结果
    print("\n[3/4] 分析测试结果...")
    test_result = categorize_results(results)
    
    # 生成报告
    print("\n[4/4] 生成报告...")
    report = generate_report(test_result, len(php_files), start_time)
    
    # 保存报告
    report_file = OUTPUT_DIR / f"aot_comprehensive_test_report_{start_time.strftime('%Y%m%d_%H%M%S')}.md"
    with open(report_file, 'w', encoding='utf-8') as f:
        f.write(report)
    
    # 保存原始数据
    json_file = OUTPUT_DIR / f"aot_comprehensive_test_data_{start_time.strftime('%Y%m%d_%H%M%S')}.json"
    with open(json_file, 'w', encoding='utf-8') as f:
        json.dump({
            "metadata": {
                "start_time": start_time.isoformat(),
                "total_files": len(php_files),
            },
            "summary": {
                "passed": len(test_result.passed),
                "mismatch": len(test_result.mismatch),
                "compile_fail": len(test_result.compile_fail),
                "php_fail": len(test_result.php_fail),
                "php_timeout": len(test_result.php_timeout),
                "aot_fail": len(test_result.aot_fail),
                "aot_timeout": len(test_result.aot_timeout),
                "errors": len(test_result.errors),
            },
            "results": results
        }, f, indent=2, ensure_ascii=False)
    
    # 打印摘要
    print("\n" + "=" * 70)
    print("测试完成!")
    print("=" * 70)
    print(f"\n总文件数: {len(php_files)}")
    print(f"✅ 通过: {len(test_result.passed)}")
    print(f"❌ 输出不匹配: {len(test_result.mismatch)}")
    print(f"🔴 编译失败: {len(test_result.compile_fail)}")
    print(f"💥 AOT 执行失败: {len(test_result.aot_fail)}")
    print(f"⏱️ AOT 执行超时: {len(test_result.aot_timeout)}")
    print(f"⚠️ PHP 执行失败: {len(test_result.php_fail)}")
    print(f"⏱️ PHP 执行超时: {len(test_result.php_timeout)}")
    print(f"🐛 其他错误: {len(test_result.errors)}")
    print(f"\n报告已保存: {report_file}")
    print(f"数据已保存: {json_file}")

if __name__ == "__main__":
    main()
