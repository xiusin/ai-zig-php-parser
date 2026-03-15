#!/usr/bin/env python3
"""
AOT模糊测试对比脚本
对比PHP原生执行与AOT编译执行的结果
"""
import os
import sys
import subprocess
import tempfile
import shutil
from datetime import datetime
from pathlib import Path

# 配置
SCRIPT_DIR = Path("/Users/xiusin/Desktop/ai-zig-php-parser/zig-php-parser")
FUZZY_DIR = SCRIPT_DIR / "fuzzy_scripts"
REPORT_FILE = SCRIPT_DIR / "fuzzy_test_report.md"
PASSED_DIR = FUZZY_DIR / "passed"
FAILED_DIR = FUZZY_DIR / "failed"
PHP_BIN = "/usr/local/bin/php"
AOT_BIN = SCRIPT_DIR / "zig-out/bin/php-interpreter"

# 统计
total = 0
passed = 0
failed = 0
skipped = 0

def run_php(file_path: Path) -> tuple[str, int]:
    """运行PHP原生执行"""
    try:
        result = subprocess.run(
            [PHP_BIN, str(file_path)],
            capture_output=True,
            text=True,
            timeout=3
        )
        output = result.stdout
        if result.stderr:
            output += "\n[STDERR]\n" + result.stderr
        return output, result.returncode
    except subprocess.TimeoutExpired:
        return "[TIMEOUT] Execution exceeded 3 seconds", -1
    except Exception as e:
        return f"[ERROR] {e}", -1

def compile_aot(file_path: Path) -> tuple[Path | None, str]:
    """编译AOT"""
    output_exe = file_path.parent / (file_path.stem)
    try:
        result = subprocess.run(
            [str(AOT_BIN), "--compile", f"--output={output_exe}", str(file_path)],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            return None, f"Compilation failed:\n{result.stderr}"
        return output_exe, ""
    except subprocess.TimeoutExpired:
        return None, "[TIMEOUT] Compilation exceeded 10 seconds"
    except Exception as e:
        return None, f"[ERROR] {e}"

def run_aot(exe_path: Path) -> tuple[str, int]:
    """运行AOT编译后的程序"""
    try:
        result = subprocess.run(
            [str(exe_path)],
            capture_output=True,
            text=True,
            timeout=3
        )
        output = result.stdout
        if result.stderr:
            output += "\n[STDERR]\n" + result.stderr
        return output, result.returncode
    except subprocess.TimeoutExpired:
        return "[TIMEOUT] Execution exceeded 3 seconds", -1
    except Exception as e:
        return f"[ERROR] {e}", -1

def should_skip(file_path: Path) -> tuple[bool, str]:
    """检查是否应该跳过此文件"""
    content = file_path.read_text().lower()
    
    # 跳过包含随机性的测试
    skip_keywords = ['rand(', 'mt_rand', 'random_', 'shuffle', 'str_shuffle']
    for kw in skip_keywords:
        if kw in content:
            return True, f"Contains randomness: {kw}"
    
    return False, ""

def test_file(file_path: Path, report) -> bool:
    """测试单个文件，返回是否通过"""
    global total, passed, failed, skipped
    
    basename = file_path.name
    total += 1
    
    # 检查是否应该跳过
    should_skip_result, skip_reason = should_skip(file_path)
    if should_skip_result:
        skipped += 1
        print(f"  [SKIP] {basename} - {skip_reason}")
        return True
    
    print(f"Testing {basename}...", end=" ", flush=True)
    
    # PHP原生执行
    php_output, php_code = run_php(file_path)
    
    # AOT编译
    exe_path, compile_error = compile_aot(file_path)
    if exe_path is None:
        failed += 1
        print(f"FAIL (compilation)")
        report.write(f"\n## {basename}\n\n")
        report.write(f"**编译失败**\n\n")
        report.write(f"```\n{compile_error}\n```\n\n")
        shutil.copy(file_path, FAILED_DIR / basename)
        return False
    
    # AOT执行
    aot_output, aot_code = run_aot(exe_path)
    
    # 清理编译产物
    if exe_path.exists():
        exe_path.unlink()
    
    # 对比结果
    # 标准化输出（移除尾部空白）
    php_normalized = php_output.rstrip()
    aot_normalized = aot_output.rstrip()
    
    if php_normalized == aot_normalized:
        passed += 1
        print(f"PASS")
        shutil.move(file_path, PASSED_DIR / basename)
        return True
    else:
        failed += 1
        print(f"FAIL (output differs)")
        report.write(f"\n## {basename}\n\n")
        report.write(f"**输出不一致**\n\n")
        report.write(f"### PHP输出 ({php_code}):\n```\n{php_output}\n```\n\n")
        report.write(f"### AOT输出 ({aot_code}):\n```\n{aot_output}\n```\n\n")
        shutil.copy(file_path, FAILED_DIR / basename)
        return False

def main():
    """主函数"""
    global total, passed, failed, skipped
    
    # 创建目录
    PASSED_DIR.mkdir(exist_ok=True)
    FAILED_DIR.mkdir(exist_ok=True)
    
    # 获取所有测试文件
    test_files = sorted(FUZZY_DIR.glob("test_*.php"))
    
    if not test_files:
        print("No test files found!")
        return
    
    print(f"Found {len(test_files)} test files")
    print(f"Starting fuzzy test comparison...")
    print("=" * 60)
    
    # 初始化报告
    with open(REPORT_FILE, "w") as report:
        report.write(f"# AOT模糊测试报告\n\n")
        report.write(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        report.write(f"总计测试文件: {len(test_files)}\n\n")
        report.write("---\n")
        
        # 测试每个文件
        for i, file_path in enumerate(test_files, 1):
            test_file(file_path, report)
            
            if i % 10 == 0:
                print(f"\n进度: {i}/{len(test_files)} - 通过:{passed} 失败:{failed} 跳过:{skipped}\n")
        
        # 写入总结
        report.write("\n## 测试总结\n\n")
        report.write(f"- 总测试数: {total}\n")
        report.write(f"- 通过: {passed}\n")
        report.write(f"- 失败: {failed}\n")
        report.write(f"- 跳过: {skipped}\n")
        if total > 0:
            report.write(f"- 通过率: {passed * 100 / total:.1f}%\n")
    
    # 打印总结
    print("=" * 60)
    print("测试完成!")
    print(f"总计: {total}")
    print(f"通过: {passed}")
    print(f"失败: {failed}")
    print(f"跳过: {skipped}")
    if total > 0:
        print(f"通过率: {passed * 100 / total:.1f}%")
    print(f"报告: {REPORT_FILE}")
    print("=" * 60)

if __name__ == "__main__":
    main()
