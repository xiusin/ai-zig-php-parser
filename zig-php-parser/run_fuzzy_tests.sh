#!/bin/bash
# AOT模糊测试主执行脚本

set -e

echo "🚀 AOT模糊测试开始"
echo "=================="

# 1. 编译项目
echo "📦 编译项目..."
zig build

# 2. 生成测试脚本
echo "🔧 生成测试脚本..."
python3 fuzzy_generator.py

# 3. 执行测试
echo "🧪 执行测试..."
python3 fuzzy_test_runner.py

# 4. 显示报告
echo ""
echo "📊 测试完成！查看详细报告："
echo "  - fuzzy_test_report.json"
echo "  - fuzzy_scripts/ (仅保留失败的测试)"

if [ -f fuzzy_test_report.json ]; then
    echo ""
    echo "快速统计："
    python3 -c "
import json
with open('fuzzy_test_report.json') as f:
    data = json.load(f)
    print(f\"  通过: {data['passed']}\")
    print(f\"  失败: {data['failed']}\")
    print(f\"  内存泄漏: {len(data['memory_leaks'])}\")
"
fi
