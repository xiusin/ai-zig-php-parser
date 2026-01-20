#!/usr/bin/env python3
"""
修复 AOT API 中的 allocator 引用问题
"""

import re
import sys

def fix_allocator_references(content):
    """修复方法中的 allocator 引用"""
    
    # 在 generateDebugAbbrev, generateDebugLine, generateDebugAranges 等方法中
    # 将 allocator 替换为 self.allocator
    
    # 但要小心不要替换函数参数中的 allocator
    # 只替换 encodeULEB128 和 encodeSLEB128 调用中的 allocator
    
    content = re.sub(
        r'try encodeULEB128\(&buf, allocator,',
        r'try encodeULEB128(&buf, self.allocator,',
        content
    )
    
    content = re.sub(
        r'try encodeSLEB128\(&buf, allocator,',
        r'try encodeSLEB128(&buf, self.allocator,',
        content
    )
    
    return content

def main():
    file_path = 'src/aot/dwarf_debug_info.zig'
    
    print(f"正在修复 {file_path} 中的 allocator 引用...")
    
    # 读取文件
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 应用修复
    original_content = content
    content = fix_allocator_references(content)
    
    # 检查是否有变化
    if content == original_content:
        print("没有需要修复的内容")
        return 0
    
    # 写回文件
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✅ 修复完成！")
    print(f"   - 修复了 allocator 引用")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
