#!/usr/bin/env python3
"""
AOT模糊测试框架
遵循宪法：性能至上、零成本抽象、内存安全
"""
import subprocess
import os
import sys
import time
import hashlib
from pathlib import Path
from typing import List, Tuple, Optional
import json

class FuzzyTestRunner:
    def __init__(self):
        self.fuzzy_dir = Path("fuzzy_scripts")
        self.aot_compiler = Path("zig-out/bin/php-interpreter")
        self.error_log = []
        self.passed_count = 0
        self.failed_count = 0
        self.memory_leaks = []
        
    def run_php(self, script_path: Path, timeout: int = 3) -> Tuple[int, str, str]:
        """执行PHP脚本"""
        try:
            result = subprocess.run(
                ["php", str(script_path)],
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return -1, "", "TIMEOUT"
        except Exception as e:
            return -1, "", str(e)
    
    def run_aot(self, script_path: Path, timeout: int = 3) -> Tuple[int, str, str]:
        """执行AOT编译和运行"""
        binary_path = script_path.with_suffix("")
        
        # 编译
        try:
            compile_result = subprocess.run(
                [str(self.aot_compiler), "--compile", str(script_path)],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            # 忽略编译警告，只检查是否生成了二进制文件
            if compile_result.returncode != 0 and not binary_path.exists():
                return compile_result.returncode, "", f"COMPILE_ERROR: {compile_result.stderr}"
            
            # 运行
            if binary_path.exists():
                run_result = subprocess.run(
                    [str(binary_path)],
                    capture_output=True,
                    text=True,
                    timeout=timeout
                )
                
                # 检查内存泄漏
                self.check_memory_leak(binary_path)
                
                # 清理编译产物
                if binary_path.exists():
                    binary_path.unlink()
                
                return run_result.returncode, run_result.stdout, run_result.stderr
            else:
                return -1, "", "BINARY_NOT_FOUND"
                
        except subprocess.TimeoutExpired:
            if binary_path.exists():
                binary_path.unlink()
            return -1, "", "TIMEOUT"
        except Exception as e:
            if binary_path.exists():
                binary_path.unlink()
            return -1, "", str(e)
    
    def check_memory_leak(self, binary_path: Path):
        """使用valgrind检查内存泄漏"""
        try:
            result = subprocess.run(
                ["valgrind", "--leak-check=full", "--error-exitcode=1", str(binary_path)],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode != 0 and "definitely lost" in result.stderr:
                self.memory_leaks.append({
                    "script": binary_path.name,
                    "leak_info": result.stderr
                })
        except:
            pass
    
    def compare_results(self, php_result: Tuple, aot_result: Tuple) -> bool:
        """比较PHP和AOT执行结果"""
        php_code, php_out, php_err = php_result
        aot_code, aot_out, aot_err = aot_result
        
        # 忽略空白差异
        php_out_clean = php_out.strip()
        aot_out_clean = aot_out.strip()
        
        return php_code == aot_code and php_out_clean == aot_out_clean
    
    def log_error(self, script_path: Path, php_result: Tuple, aot_result: Tuple):
        """记录错误"""
        with open(script_path, 'r') as f:
            script_content = f.read()
        
        php_code, php_out, php_err = php_result
        aot_code, aot_out, aot_err = aot_result
        
        self.error_log.append({
            "script": script_path.name,
            "content": script_content,
            "php_output": php_out if php_code == 0 else f"ERROR({php_code}): {php_err}",
            "aot_output": aot_out if aot_code == 0 else f"ERROR({aot_code}): {aot_err}"
        })
    
    def run_all_tests(self):
        """执行所有测试"""
        scripts = sorted(self.fuzzy_dir.glob("test_*.php"))
        total = len(scripts)
        
        print(f"🚀 开始执行 {total} 个模糊测试...")
        
        for i, script in enumerate(scripts, 1):
            print(f"[{i}/{total}] 测试 {script.name}...", end=" ")
            
            # 执行PHP
            php_result = self.run_php(script)
            
            # 执行AOT
            aot_result = self.run_aot(script)
            
            # 比较结果
            if self.compare_results(php_result, aot_result):
                print("✅ PASS")
                self.passed_count += 1
                # 删除通过的脚本
                try:
                    script.unlink()
                except:
                    pass
            else:
                print("❌ FAIL")
                self.failed_count += 1
                self.log_error(script, php_result, aot_result)
                # 保留失败的脚本
        
        self.generate_report()
    
    def generate_report(self):
        """生成测试报告"""
        print("\n" + "="*80)
        print(f"📊 测试报告")
        print("="*80)
        print(f"总计: {self.passed_count + self.failed_count}")
        print(f"通过: {self.passed_count}")
        print(f"失败: {self.failed_count}")
        print(f"通过率: {self.passed_count/(self.passed_count+self.failed_count)*100:.2f}%")
        
        if self.error_log:
            print("\n❌ 失败的测试:")
            print("\n| 脚本 | 脚本内容 | PHP正确结果 | AOT执行结果 |")
            print("|------|----------|-------------|-------------|")
            
            for error in self.error_log:
                content = error['content'].replace('\n', ' ')[:100]
                php_out = error['php_output'].replace('\n', ' ')[:100]
                aot_out = error['aot_output'].replace('\n', ' ')[:100]
                print(f"| {error['script']} | {content} | {php_out} | {aot_out} |")
        
        if self.memory_leaks:
            print(f"\n⚠️  检测到 {len(self.memory_leaks)} 个内存泄漏")
            for leak in self.memory_leaks:
                print(f"  - {leak['script']}")
        
        # 保存详细报告
        with open("fuzzy_test_report.json", "w") as f:
            json.dump({
                "passed": self.passed_count,
                "failed": self.failed_count,
                "errors": self.error_log,
                "memory_leaks": self.memory_leaks
            }, f, indent=2)

if __name__ == "__main__":
    runner = FuzzyTestRunner()
    runner.run_all_tests()
