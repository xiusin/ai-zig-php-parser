#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PHP AOT 模糊测试运行器
批量执行测试脚本，对比AOT和PHP原生结果，生成报告
"""

import os
import sys
import subprocess
import time
import json
import re
from datetime import datetime
from pathlib import Path

# 配置
BASE_DIR = Path(__file__).parent
PROJECT_ROOT = BASE_DIR.parent
AOT_INTERPRETER = PROJECT_ROOT / "zig-out" / "bin" / "php-interpreter"
FAILED_SCRIPTS_DIR = BASE_DIR / "failed_scripts"
REPORT_FILE = PROJECT_ROOT / "docs" / "aot_fuzzy_test_report.md"
TIMEOUT_SCRIPT = 3  # 脚本执行超时(秒)
TIMEOUT_COMPILE = 30  # AOT编译超时(秒)
TIMEOUT_NATIVE = 10  # PHP原生执行超时(秒)

# 测试统计
stats = {
    "total": 0,
    "passed": 0,
    "failed": 0,
    "errors": 0,
    "compile_errors": 0,
    "runtime_errors": 0,
    "mismatches": 0,
    "memory_leaks": 0,
    "start_time": None,
    "end_time": None
}

# 失败记录
failures = []

def run_command(cmd, timeout, cwd=None):
    """执行命令并返回结果"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd
        )
        return {
            "success": True,
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "error": "timeout",
            "returncode": -1,
            "stdout": "",
            "stderr": "Command timed out"
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "returncode": -1,
            "stdout": "",
            "stderr": str(e)
        }

def run_php_native(script_path):
    """使用原生PHP执行脚本"""
    result = run_command(f"php -n {script_path}", TIMEOUT_NATIVE)
    return result

def compile_aot(script_path, output_path):
    """AOT编译脚本"""
    cmd = f"{AOT_INTERPRETER} --compile --output={output_path} {script_path}"
    result = run_command(cmd, TIMEOUT_COMPILE)
    return result

def run_aot_binary(binary_path):
    """执行AOT编译的二进制文件"""
    result = run_command(binary_path, TIMEOUT_SCRIPT)
    return result

def clean_binary(binary_path):
    """删除编译产物"""
    try:
        if os.path.exists(binary_path):
            os.remove(binary_path)
        # 删除可能的.dylib文件
        dylib_path = binary_path + ".dylib"
        if os.path.exists(dylib_path):
            os.remove(dylib_path)
    except Exception:
        pass

def normalize_output(output):
    """标准化输出以便比较"""
    # 移除首尾空白
    output = output.strip()
    # 标准化换行符
    output = output.replace('\r\n', '\n').replace('\r', '\n')
    # 移除多余的空行
    lines = [line.rstrip() for line in output.split('\n')]
    return '\n'.join(lines)

def check_memory_leak(stderr):
    """检查内存泄漏"""
    leak_patterns = [
        r'leak',
        r'memory leak',
        r'bytes leaked',
        r'LEAK',
        r'Allocations not freed',
        r'detected memory leaks'
    ]
    for pattern in leak_patterns:
        if re.search(pattern, stderr, re.IGNORECASE):
            return True
    return False

def save_failed_script(script_path, script_content, php_output, aot_output, error_type):
    """保存失败的脚本"""
    os.makedirs(FAILED_SCRIPTS_DIR, exist_ok=True)
    
    # 复制脚本到失败目录
    script_name = os.path.basename(script_path)
    dest_path = FAILED_SCRIPTS_DIR / script_name
    
    with open(dest_path, 'w') as f:
        f.write(script_content)
    
    # 保存错误信息
    info_path = FAILED_SCRIPTS_DIR / f"{script_name}.info"
    with open(info_path, 'w') as f:
        f.write(f"Error Type: {error_type}\n")
        f.write(f"{'='*50}\n")
        f.write(f"PHP Output:\n{php_output}\n")
        f.write(f"{'='*50}\n")
        f.write(f"AOT Output:\n{aot_output}\n")

def delete_script(script_path):
    """删除测试通过的脚本"""
    try:
        if os.path.exists(script_path):
            os.remove(script_path)
    except Exception:
        pass

def test_script(script_path):
    """测试单个脚本"""
    stats["total"] += 1
    
    # 读取脚本内容
    with open(script_path, 'r', encoding='utf-8') as f:
        script_content = f.read()
    
    # 忽略生成器和随机数相关测试
    if 'yield' in script_content or 'random' in script_content.lower():
        delete_script(script_path)
        return None
    
    # PHP原生执行
    php_result = run_php_native(script_path)
    php_output = normalize_output(php_result.get("stdout", ""))
    php_stderr = php_result.get("stderr", "")
    
    # AOT编译
    binary_path = script_path.replace('.php', '_aot')
    compile_result = compile_aot(script_path, binary_path)
    
    if not compile_result["success"] or compile_result["returncode"] != 0:
        stats["failed"] += 1
        stats["compile_errors"] += 1
        error_info = compile_result.get("stderr", compile_result.get("error", "Unknown error"))
        
        failures.append({
            "script": os.path.basename(script_path),
            "content": script_content[:200] + "..." if len(script_content) > 200 else script_content,
            "php_output": php_output,
            "aot_output": f"COMPILE ERROR: {error_info}",
            "error_type": "compile_error"
        })
        
        save_failed_script(script_path, script_content, php_output, 
                          f"COMPILE ERROR: {error_info}", "compile_error")
        clean_binary(binary_path)
        return False
    
    # AOT执行
    aot_result = run_aot_binary(binary_path)
    aot_output = normalize_output(aot_result.get("stdout", ""))
    aot_stderr = aot_result.get("stderr", "")
    
    # 清理编译产物
    clean_binary(binary_path)
    
    # 检查内存泄漏
    if check_memory_leak(aot_stderr):
        stats["memory_leaks"] += 1
    
    # 比较结果
    if php_output == aot_output:
        stats["passed"] += 1
        delete_script(script_path)
        return True
    else:
        stats["failed"] += 1
        stats["mismatches"] += 1
        
        # 记录失败
        failures.append({
            "script": os.path.basename(script_path),
            "content": script_content[:200] + "..." if len(script_content) > 200 else script_content,
            "php_output": php_output,
            "aot_output": aot_output if aot_output else f"RUNTIME ERROR: {aot_stderr}",
            "error_type": "mismatch"
        })
        
        save_failed_script(script_path, script_content, php_output, aot_output, "mismatch")
        return False

def generate_report():
    """生成测试报告"""
    duration = stats["end_time"] - stats["start_time"]
    
    report = f"""# AOT 模糊测试报告

## 测试概览

| 指标 | 值 |
|------|-----|
| 测试时间 | {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} |
| 总耗时 | {duration:.2f} 秒 |
| 总测试数 | {stats['total']} |
| 通过数 | {stats['passed']} |
| 失败数 | {stats['failed']} |
| 通过率 | {(stats['passed']/stats['total']*100) if stats['total'] > 0 else 0:.2f}% |
| 编译错误 | {stats['compile_errors']} |
| 运行时错误 | {stats['runtime_errors']} |
| 结果不一致 | {stats['mismatches']} |
| 内存泄漏 | {stats['memory_leaks']} |

## 失败详情

以下表格记录所有失败的测试用例：

| 脚本 | 脚本内容 | PHP正确结果 | AOT执行结果/错误信息 |
|------|----------|-------------|---------------------|
"""
    
    for f in failures:
        script = f["script"]
        content = f["content"].replace('\n', '\\n').replace('|', '\\|')[:100]
        php_out = f["php_output"].replace('\n', '\\n').replace('|', '\\|')[:100]
        aot_out = f["aot_output"].replace('\n', '\\n').replace('|', '\\|')[:200]
        
        report += f"| {script} | `{content}` | `{php_out}` | `{aot_out}` |\n"
    
    report += f"""
## 错误分类统计

### 编译错误 ({stats['compile_errors']})

"""
    
    compile_errors = [f for f in failures if f["error_type"] == "compile_error"]
    if compile_errors:
        for e in compile_errors[:20]:  # 只显示前20个
            report += f"- **{e['script']}**: {e['aot_output'][:150]}\n"
    else:
        report += "无编译错误\n"
    
    report += f"""
### 结果不一致 ({stats['mismatches']})

"""
    
    mismatches = [f for f in failures if f["error_type"] == "mismatch"]
    if mismatches:
        for e in mismatches[:20]:  # 只显示前20个
            report += f"- **{e['script']}**:\n  - PHP: `{e['php_output'][:100]}`\n  - AOT: `{e['aot_output'][:100]}`\n"
    else:
        report += "无结果不一致\n"
    
    report += f"""
## 结论与建议

1. **总体通过率**: {(stats['passed']/stats['total']*100) if stats['total'] > 0 else 0:.2f}%
2. **主要问题**: 
   - 编译错误: {stats['compile_errors']} 个
   - 运行时错误: {stats['runtime_errors']} 个
   - 结果不一致: {stats['mismatches']} 个
3. **内存泄漏**: 检测到 {stats['memory_leaks']} 个可能的内存泄漏

---
*报告生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*
"""
    
    return report

def main():
    """主测试流程"""
    # 检查AOT解释器存在
    if not AOT_INTERPRETER.exists():
        print(f"错误: AOT解释器不存在: {AOT_INTERPRETER}")
        print("请先运行: zig build")
        sys.exit(1)
    
    # 创建失败脚本目录
    os.makedirs(FAILED_SCRIPTS_DIR, exist_ok=True)
    
    # 清空之前的失败脚本
    for f in FAILED_SCRIPTS_DIR.glob("*.php"):
        os.remove(f)
    for f in FAILED_SCRIPTS_DIR.glob("*.php.info"):
        os.remove(f)
    
    # 获取所有测试脚本
    scripts = sorted(BASE_DIR.glob("test_*.php"))
    
    if not scripts:
        print("没有找到测试脚本，请先运行 generate_tests.py")
        sys.exit(1)
    
    print(f"找到 {len(scripts)} 个测试脚本")
    print("=" * 60)
    
    stats["start_time"] = time.time()
    
    # 执行测试
    for idx, script in enumerate(scripts, 1):
        script_path = str(script)
        
        if idx % 50 == 0:
            passed_rate = (stats["passed"] / idx * 100) if idx > 0 else 0
            print(f"[{idx}/{len(scripts)}] 通过: {stats['passed']}, 失败: {stats['failed']}, 通过率: {passed_rate:.1f}%")
        
        test_script(script_path)
    
    stats["end_time"] = time.time()
    
    # 生成报告
    print("\n" + "=" * 60)
    print("测试完成，生成报告...")
    
    report = generate_report()
    
    # 保存报告
    os.makedirs(PROJECT_ROOT / "docs", exist_ok=True)
    with open(REPORT_FILE, 'w', encoding='utf-8') as f:
        f.write(report)
    
    print(f"\n报告已保存到: {REPORT_FILE}")
    print(f"失败脚本保存在: {FAILED_SCRIPTS_DIR}")
    
    # 打印摘要
    print("\n" + "=" * 60)
    print("测试摘要:")
    print(f"  总测试数: {stats['total']}")
    print(f"  通过: {stats['passed']}")
    print(f"  失败: {stats['failed']}")
    print(f"  通过率: {(stats['passed']/stats['total']*100) if stats['total'] > 0 else 0:.2f}%")
    print(f"  耗时: {stats['end_time'] - stats['start_time']:.2f} 秒")
    
    return stats["failed"] == 0

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
