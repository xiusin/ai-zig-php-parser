#!/usr/bin/env python3
"""
批量修复 AOT API 问题的脚本
"""

import re
import sys

def fix_add_attribute_calls(content):
    """修复 addAttribute 调用，添加 self.allocator 参数"""
    
    # 匹配模式：try xxx.addAttribute(.{
    patterns = [
        (r'try cu\.addAttribute\(\.\{', r'try cu.addAttribute(self.allocator, .{'),
        (r'try func_die\.addAttribute\(\.\{', r'try func_die.addAttribute(self.allocator, .{'),
        (r'try param_die\.addAttribute\(\.\{', r'try param_die.addAttribute(self.allocator, .{'),
        (r'try var_die\.addAttribute\(\.\{', r'try var_die.addAttribute(self.allocator, .{'),
        (r'try type_die\.addAttribute\(\.\{', r'try type_die.addAttribute(self.allocator, .{'),
    ]
    
    for pattern, replacement in patterns:
        content = re.sub(pattern, replacement, content)
    
    return content

def fix_encode_calls(content):
    """修复 encodeULEB128 和 encodeSLEB128 调用"""
    
    # 修复 encodeULEB128 调用
    content = re.sub(
        r'try encodeULEB128\(&buf, (\d+)\)',
        r'try encodeULEB128(&buf, allocator, \1)',
        content
    )
    
    # 修复 encodeSLEB128 调用
    content = re.sub(
        r'try encodeSLEB128\(&buf, (@as\(i64, @intCast\([^)]+\)\))\)',
        r'try encodeSLEB128(&buf, allocator, \1)',
        content
    )
    
    return content

def main():
    file_path = 'src/aot/dwarf_debug_info.zig'
    
    print(f"正在修复 {file_path}...")
    
    # 读取文件
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 应用修复
    original_content = content
    content = fix_add_attribute_calls(content)
    content = fix_encode_calls(content)
    
    # 检查是否有变化
    if content == original_content:
        print("没有需要修复的内容")
        return 0
    
    # 写回文件
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✅ 修复完成！")
    print(f"   - 修复了 addAttribute 调用")
    print(f"   - 修复了 encode 函数调用")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
