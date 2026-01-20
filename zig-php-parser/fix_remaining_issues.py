#!/usr/bin/env python3
"""
修复剩余的编译问题
"""
import re
from pathlib import Path

def fix_aot_files():
    """修复 AOT 文件中的 fast_compiler 引用"""
    aot_files = [
        "src/aot/compiler.zig",
        "src/aot/multi_file_compiler.zig",
        "src/aot/test_multi_file_compiler.zig"
    ]
    
    for filepath in aot_files:
        path = Path(filepath)
        if not path.exists():
            continue
            
        content = path.read_text(encoding='utf-8')
        original = content
        
        # 查找 var fast_compiler = 并替换为 var fc =
        content = re.sub(r'\bvar fast_compiler = FastCompiler', 'var fc = FastCompiler', content)
        content = re.sub(r'\bfast_compiler\.(deinit|compile|emit)', r'fc.\1', content)
        content = re.sub(r'\bdefer fast_compiler\.deinit\(\);', 'defer fc.deinit();', content)
        
        if content != original:
            path.write_text(content, encoding='utf-8')
            print(f"✓ 修复: {filepath}")

def fix_debugger():
    """修复 debugger.zig 中的语法错误"""
    filepath = Path("src/runtime/debugger.zig")
    if not filepath.exists():
        return
        
    content = filepath.read_text(encoding='utf-8')
    original = content
    
    # 修复缺少分号的问题
    content = re.sub(r'const MAX_WATCHES: usize = 128\n', 'const MAX_WATCHES: usize = 128;\n', content)
    
    if content != original:
        filepath.write_text(content, encoding='utf-8')
        print(f"✓ 修复: {filepath}")

def fix_builtin_time():
    """修复 builtin_time.zig 中的未使用参数"""
    filepath = Path("src/runtime/builtin_time.zig")
    if not filepath.exists():
        return
        
    content = filepath.read_text(encoding='utf-8')
    original = content
    
    # 移除无用的 _ = vm; 行
    lines = content.split('\n')
    new_lines = []
    for i, line in enumerate(lines):
        if '_ = vm;' in line and i + 1 < len(lines):
            # 检查下一行是否使用了 vm
            next_line = lines[i + 1]
            if 'vm' in next_line and '@ptrCast' in next_line:
                # 跳过这一行
                continue
        new_lines.append(line)
    
    content = '\n'.join(new_lines)
    
    if content != original:
        filepath.write_text(content, encoding='utf-8')
        print(f"✓ 修复: {filepath}")

def main():
    """主函数"""
    print("修复 AOT 文件...")
    fix_aot_files()
    
    print("\n修复 debugger...")
    fix_debugger()
    
    print("\n修复 builtin_time...")
    fix_builtin_time()
    
    print("\n完成!")

if __name__ == "__main__":
    main()
