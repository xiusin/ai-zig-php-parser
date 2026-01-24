#!/usr/bin/env python3
"""
修复剩余的编译问题
"""
import re
from pathlib import Path

def fix_aot_test_multi_file():
    """修复 test_multi_file_compiler.zig"""
    filepath = Path("src/aot/test_multi_file_compiler.zig")
    if not filepath.exists():
        return
        
    content = filepath.read_text(encoding='utf-8')
    original = content
    
    # 替换所有 const compiler = try MultiFileCompiler 为 const multi_compiler
    content = re.sub(
        r'const compiler = try MultiFileCompiler\.init',
        'const multi_compiler = try MultiFileCompiler.init',
        content
    )
    
    # 替换所有 defer fc.deinit() 为 defer multi_compiler.deinit()
    # 但只在 MultiFileCompiler 上下文中
    lines = content.split('\n')
    new_lines = []
    in_multi_file_test = False
    
    for i, line in enumerate(lines):
        if 'MultiFileCompiler.init' in line:
            in_multi_file_test = True
        elif 'defer fc.deinit()' in line and in_multi_file_test:
            line = line.replace('defer fc.deinit()', 'defer multi_compiler.deinit()')
            in_multi_file_test = False
        elif 'compiler.' in line and in_multi_file_test:
            # 替换 compiler. 为 multi_compiler.
            line = re.sub(r'\bcompiler\.', 'multi_compiler.', line)
        
        new_lines.append(line)
    
    content = '\n'.join(new_lines)
    
    if content != original:
        filepath.write_text(content, encoding='utf-8')
        print(f"✓ 修复: {filepath}")

def fix_aot_multi_file():
    """修复 multi_file_compiler.zig"""
    filepath = Path("src/aot/multi_file_compiler.zig")
    if not filepath.exists():
        return
        
    content = filepath.read_text(encoding='utf-8')
    original = content
    
    # 在测试函数中替换
    content = re.sub(
        r'const compiler = try MultiFileCompiler\.init',
        'const multi_compiler = try MultiFileCompiler.init',
        content
    )
    
    # 替换 defer fc.deinit()
    lines = content.split('\n')
    new_lines = []
    
    for i, line in enumerate(lines):
        if 'defer fc.deinit()' in line:
            # 查找前面的变量声明
            for j in range(i-1, max(0, i-10), -1):
                if 'multi_compiler' in lines[j]:
                    line = line.replace('defer fc.deinit()', 'defer multi_compiler.deinit()')
                    break
        elif 'compiler.' in line and i > 0:
            # 检查前面是否有 multi_compiler 声明
            context = '\n'.join(lines[max(0, i-20):i])
            if 'multi_compiler = try MultiFileCompiler' in context:
                line = re.sub(r'\bcompiler\.', 'multi_compiler.', line)
        
        new_lines.append(line)
    
    content = '\n'.join(new_lines)
    
    if content != original:
        filepath.write_text(content, encoding='utf-8')
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
    
    # 移除无用的 _ = vm; 行（在使用 vm 之前）
    lines = content.split('\n')
    new_lines = []
    skip_next_discard = False
    
    for i, line in enumerate(lines):
        # 检查是否是 _ = vm; 且下一行使用了 vm
        if '_ = vm;' in line.strip():
            # 查看接下来的几行是否使用了 vm
            uses_vm = False
            for j in range(i+1, min(i+5, len(lines))):
                if 'vm' in lines[j] and '@ptrCast' in lines[j]:
                    uses_vm = True
                    break
            if uses_vm:
                # 跳过这个 discard
                continue
        
        new_lines.append(line)
    
    content = '\n'.join(new_lines)
    
    if content != original:
        filepath.write_text(content, encoding='utf-8')
        print(f"✓ 修复: {filepath}")

def fix_crash_handler():
    """修复 crash_handler.zig 中的重复函数"""
    filepath = Path("src/runtime/crash_handler.zig")
    if not filepath.exists():
        return
        
    content = filepath.read_text(encoding='utf-8')
    original = content
    
    # 查找重复的 extractFramePointer 函数
    # 保留第一个，删除第二个
    lines = content.split('\n')
    new_lines = []
    found_first = False
    in_duplicate = False
    brace_count = 0
    
    for i, line in enumerate(lines):
        if 'fn extractFramePointer(ucontext: *anyopaque) usize {' in line:
            if not found_first:
                found_first = True
                new_lines.append(line)
            else:
                # 这是重复的函数，开始跳过
                in_duplicate = True
                brace_count = 1
                continue
        elif in_duplicate:
            # 计算大括号以找到函数结束
            brace_count += line.count('{')
            brace_count -= line.count('}')
            if brace_count == 0:
                in_duplicate = False
            continue
        else:
            new_lines.append(line)
    
    content = '\n'.join(new_lines)
    
    if content != original:
        filepath.write_text(content, encoding='utf-8')
        print(f"✓ 修复: {filepath}")

def main():
    """主函数"""
    print("修复 test_multi_file_compiler...")
    fix_aot_test_multi_file()
    
    print("\n修复 multi_file_compiler...")
    fix_aot_multi_file()
    
    print("\n修复 debugger...")
    fix_debugger()
    
    print("\n修复 builtin_time...")
    fix_builtin_time()
    
    print("\n修复 crash_handler...")
    fix_crash_handler()
    
    print("\n完成!")

if __name__ == "__main__":
    main()
