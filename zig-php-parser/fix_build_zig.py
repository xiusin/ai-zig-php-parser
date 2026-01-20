#!/usr/bin/env python3
"""
为 build.zig 中的所有测试和可执行文件添加模块导入
"""

import re

def add_module_imports(content):
    """在每个 linkLibC() 后添加模块导入"""
    
    # 模块导入代码
    imports = """
    // 添加模块导入
    {var}.root_module.addImport("compiler", compiler_mod);
    {var}.root_module.addImport("runtime", runtime_mod);
    {var}.root_module.addImport("bytecode", bytecode_mod);
    {var}.root_module.addImport("jit", jit_mod);
    {var}.root_module.addImport("extension", extension_mod);"""
    
    # 查找所有 linkLibC() 调用，并在其后添加模块导入
    # 匹配模式：变量名.linkLibC();
    pattern = r'(\w+)\.linkLibC\(\);'
    
    def replace_func(match):
        var_name = match.group(1)
        # 检查后面是否已经有模块导入
        return match.group(0) + imports.format(var=var_name)
    
    # 只替换还没有添加模块导入的地方
    lines = content.split('\n')
    result_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        result_lines.append(line)
        
        # 检查是否是 linkLibC() 调用
        match = re.search(r'(\w+)\.linkLibC\(\);', line)
        if match:
            var_name = match.group(1)
            # 检查下一行是否已经有模块导入
            if i + 1 < len(lines) and 'addImport' not in lines[i + 1]:
                # 添加模块导入
                result_lines.append(f'    // 添加模块导入')
                result_lines.append(f'    {var_name}.root_module.addImport("compiler", compiler_mod);')
                result_lines.append(f'    {var_name}.root_module.addImport("runtime", runtime_mod);')
                result_lines.append(f'    {var_name}.root_module.addImport("bytecode", bytecode_mod);')
                result_lines.append(f'    {var_name}.root_module.addImport("jit", jit_mod);')
                result_lines.append(f'    {var_name}.root_module.addImport("extension", extension_mod);')
        
        i += 1
    
    return '\n'.join(result_lines)

def main():
    file_path = 'build.zig'
    
    print(f"正在修复 {file_path}...")
    
    # 读取文件
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 应用修复
    original_content = content
    content = add_module_imports(content)
    
    # 检查是否有变化
    if content == original_content:
        print("没有需要修复的内容")
        return 0
    
    # 写回文件
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✅ 修复完成！")
    print(f"   - 为所有测试和可执行文件添加了模块导入")
    
    return 0

if __name__ == '__main__':
    import sys
    sys.exit(main())
