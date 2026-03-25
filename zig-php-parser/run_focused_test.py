#!/usr/bin/env python3
"""
AOT测试执行器 - 执行单个测试并输出结果
"""
import subprocess
import sys
import os
from pathlib import Path

SCRIPT_DIR = Path("/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser")
AOT_BIN = SCRIPT_DIR / "zig-out/bin/php-interpreter"

def test_single(php_file):
    """测试单个文件"""
    print(f"\n{'='*60}")
    print(f"测试文件: {php_file}")
    print('='*60)
    
    # PHP执行
    print("\n[PHP原生执行]")
    try:
        result = subprocess.run(
            ["php", php_file],
            capture_output=True,
            text=True,
            timeout=10
        )
        print(f"退出码: {result.returncode}")
        print(f"输出:\n{result.stdout[:1500]}")
        if result.stderr:
            print(f"错误:\n{result.stderr[:500]}")
    except Exception as e:
        print(f"执行错误: {e}")
        return
    
    # AOT编译
    print("\n[AOT编译]")
    output_exe = f"/tmp/aot_test_{os.getpid()}"
    try:
        result = subprocess.run(
            [str(AOT_BIN), "--compile", f"--output={output_exe}", php_file],
            capture_output=True,
            text=True,
            timeout=30
        )
        print(f"退出码: {result.returncode}")
        if result.returncode != 0:
            print(f"编译错误:\n{result.stderr[:1500]}")
            return
        print("编译成功!")
    except Exception as e:
        print(f"编译错误: {e}")
        return
    
    # AOT执行
    print("\n[AOT执行]")
    try:
        os.chmod(output_exe, 0o755)  # 确保执行权限
        result = subprocess.run(
            [output_exe],
            capture_output=True,
            text=True,
            timeout=10
        )
        print(f"退出码: {result.returncode}")
        print(f"输出:\n{result.stdout[:1500]}")
        if result.stderr:
            print(f"错误:\n{result.stderr[:500]}")
    except Exception as e:
        print(f"执行错误: {e}")
    finally:
        if os.path.exists(output_exe):
            os.unlink(output_exe)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        test_single(sys.argv[1])
    else:
        # 默认测试几个典型问题脚本
        test_files = [
            "fuzzy_scripts_27/failed/test_007_enums.php",
            "fuzzy_scripts_27/failed/test_019_match.php",
            "fuzzy_scripts_27/failed/test_031_nullsafe.php",
        ]
        for f in test_files:
            full_path = SCRIPT_DIR / f
            if full_path.exists():
                test_single(str(full_path))
