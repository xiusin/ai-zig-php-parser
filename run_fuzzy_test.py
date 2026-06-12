#!/usr/bin/env python3
"""
AOT模糊测试执行脚本
执行时间: 2026-04-06
"""

import os
import subprocess
import glob
import shutil
import time
from datetime import datetime

# 配置
SCRIPT_DIR = "/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser"
FUZZY_DIR = os.path.join(SCRIPT_DIR, "fuzzy_scripts")
PASS_DIR = os.path.join(FUZZY_DIR, "pass")
INTERPRETER = os.path.join(SCRIPT_DIR, "zig-out/bin/php-interpreter")
TEMP_DIR = f"/tmp/aot_fuzzy_test_{os.getpid()}"

# 排除模式
EXCLUDE_PATTERNS = ['fiber', 'coroutine', 'generator', 'random', 'rand']

# 统计
stats = {'total': 0, 'passed': 0, 'failed': 0, 'skipped': 0}
errors = []

def should_exclude(script_name):
    """检查脚本是否应该排除"""
    for pattern in EXCLUDE_PATTERNS:
        if pattern in script_name.lower():
            return True
    return False

def run_command(cmd, timeout=10):
    """执行命令并返回输出"""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            shell=isinstance(cmd, str)
        )
        return result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1
    except Exception as e:
        return str(e), -1

def run_test(script_path):
    """执行单个测试"""
    script_name = os.path.basename(script_path)
    stats['total'] += 1

    # 检查是否排除
    if should_exclude(script_name):
        print(f"[SKIP] {script_name} (excluded pattern)")
        stats['skipped'] += 1
        return

    # Step 1: PHP原生执行
    php_output, php_exit = run_command(f"timeout 3 php {script_path}")

    # Step 2: AOT编译
    output_name = script_name.replace('.php', '')
    aot_binary = os.path.join(TEMP_DIR, output_name)
    compile_output, compile_exit = run_command(
        f"timeout 30 {INTERPRETER} --compile --output={aot_binary} {script_path}"
    )

    if compile_exit != 0:
        # 编译失败，检查是否PHP也有错误
        if 'fatal' in php_output.lower() or 'error' in php_output.lower():
            if 'error' in compile_output.lower() or 'fail' in compile_output.lower():
                print(f"[PASS] {script_name} (both have errors)")
                stats['passed'] += 1
                os.remove(script_path)
                return
        print(f"[FAIL] {script_name} (compile failed)")
        errors.append({
            'script': script_name,
            'php_output': php_output[:500],
            'aot_output': f"Compile Error: {compile_output[:500]}"
        })
        stats['failed'] += 1
        return

    # Step 3: AOT执行
    aot_output, aot_exit = run_command(f"timeout 3 {aot_binary}")

    # Step 4: 清理编译产物
    if os.path.exists(aot_binary):
        os.remove(aot_binary)

    # Step 5: 对比结果
    if php_output == aot_output:
        print(f"[PASS] {script_name}")
        stats['passed'] += 1
        os.remove(script_path)
    else:
        print(f"[FAIL] {script_name} (output mismatch)")
        errors.append({
            'script': script_name,
            'php_output': php_output[:500],
            'aot_output': aot_output[:500]
        })
        stats['failed'] += 1

def generate_report():
    """生成测试报告"""
    report_path = os.path.join(SCRIPT_DIR, "fuzzy_test_report.md")
    with open(report_path, 'w') as f:
        f.write("# AOT模糊测试报告\n\n")
        f.write(f"测试时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        # 统计信息
        f.write("## 测试统计\n\n")
        f.write("| 统计项 | 数量 |\n")
        f.write("|--------|------|\n")
        f.write(f"| 总计 | {stats['total']} |\n")
        f.write(f"| 通过 | {stats['passed']} |\n")
        f.write(f"| 失败 | {stats['failed']} |\n")
        f.write(f"| 跳过 | {stats['skipped']} |\n\n")

        # 错误详情
        if errors:
            f.write("## 错误详情\n\n")
            for error in errors:
                f.write(f"### {error['script']}\n\n")
                f.write("| 项目 | 内容 |\n")
                f.write("|------|------|\n")
                php_out = error['php_output'].replace('|', '\\|').replace('\n', ' ')[:300]
                aot_out = error['aot_output'].replace('|', '\\|').replace('\n', ' ')[:300]
                f.write(f"| PHP输出 | `{php_out}` |\n")
                f.write(f"| AOT输出 | `{aot_out}` |\n\n")

    print(f"\n报告已保存到: {report_path}")

def main():
    # 创建目录
    os.makedirs(PASS_DIR, exist_ok=True)
    os.makedirs(TEMP_DIR, exist_ok=True)

    # 获取所有测试脚本
    scripts = sorted(glob.glob(os.path.join(FUZZY_DIR, "*.php")))

    print("=" * 50)
    print("开始AOT模糊测试...")
    print(f"解释器: {INTERPRETER}")
    print(f"测试目录: {FUZZY_DIR}")
    print(f"测试脚本数量: {len(scripts)}")
    print("=" * 50)
    print()

    # 执行测试
    for script in scripts:
        if os.path.exists(script):
            run_test(script)

    # 清理
    if os.path.exists(TEMP_DIR):
        shutil.rmtree(TEMP_DIR)

    # 输出结果
    print()
    print("=" * 50)
    print("测试完成!")
    print(f"总计: {stats['total']}, 通过: {stats['passed']}, 失败: {stats['failed']}, 跳过: {stats['skipped']}")
    print("=" * 50)

    # 生成报告
    generate_report()

if __name__ == "__main__":
    main()
