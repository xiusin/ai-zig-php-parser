#!/usr/bin/env python3
"""
批量修复 Zig 模块导入问题
"""
import re
import os
from pathlib import Path

def fix_file(filepath):
    """修复单个文件的导入"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    
    # 修复跨目录导入
    content = re.sub(r'@import\("\.\./compiler/([^"]+)"\)', r'@import("compiler").\1', content)
    content = re.sub(r'@import\("\.\./runtime/([^"]+)"\)', r'@import("runtime").\1', content)
    content = re.sub(r'@import\("\.\./bytecode/([^"]+)"\)', r'@import("bytecode").\1', content)
    content = re.sub(r'@import\("\.\./jit/([^"]+)"\)', r'@import("jit").\1', content)
    content = re.sub(r'@import\("\.\./extension/([^"]+)"\)', r'@import("extension").\1', content)
    
    # 修复 var compiler = 变量名冲突
    content = re.sub(r'\bvar compiler = FastCompiler', 'var fast_compiler = FastCompiler', content)
    content = re.sub(r'\bcompiler\.(emit|deinit|compile)', r'fast_compiler.\1', content)
    
    # 修复 token. 引用
    content = re.sub(r'\btoken\.Tag\.', 'Token.Tag.', content)
    
    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"✓ 修复: {filepath}")
        return True
    return False

def main():
    """主函数"""
    src_dir = Path("src")
    fixed_count = 0
    
    # 遍历所有 .zig 文件
    for filepath in src_dir.rglob("*.zig"):
        if fix_file(filepath):
            fixed_count += 1
    
    print(f"\n总共修复了 {fixed_count} 个文件")

if __name__ == "__main__":
    main()
