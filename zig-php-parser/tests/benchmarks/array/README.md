# 数组操作性能测试

本目录包含数组操作性能测试的 PHP 对比脚本。

## 测试覆盖

本测试套件覆盖 60+ PHP 数组函数，分为以下类别：

### 1. 数组创建与初始化
- `array_create` - 数组创建
- `range` - 范围数组
- `array_fill` - 填充数组
- `array_fill_keys` - 键填充数组

### 2. 数组访问与修改
- `array_push` - 尾部添加
- `array_pop` - 尾部删除
- `array_shift` - 头部删除
- `array_unshift` - 头部添加
- `array_slice` - 数组切片
- `array_splice` - 数组拼接

### 3. 数组搜索
- `array_search` - 搜索值
- `in_array` - 值是否存在
- `array_key_exists` - 键是否存在

### 4. 数组排序
- `sort` - 升序排序
- `rsort` - 降序排序

### 5. 数组过滤与映射
- `array_filter` - 过滤数组
- `array_map` - 映射数组

### 6. 数组合并与分割
- `array_merge` - 合并数组
- `array_chunk` - 分块数组

### 7. 数组统计
- `array_sum` - 求和
- `array_product` - 求积
- `array_unique` - 去重

### 8. 数组键值操作
- `array_keys` - 获取键
- `array_values` - 获取值
- `array_flip` - 键值翻转

### 9. 数组集合操作
- `array_diff` - 差集
- `array_intersect` - 交集

### 10. 其他数组函数
- `array_reverse` - 反转
- `array_pad` - 填充
- `array_replace` - 替换

## 运行测试

### 运行 Zig-PHP 测试

```bash
cd zig-php-parser
zig build run-array-benchmark
```

### 运行 PHP 对比测试

```bash
cd tests/benchmarks/array
php array_create.php
php range.php
php array_fill.php
# ... 运行其他测试脚本
```

### 批量运行所有 PHP 测试

```bash
cd tests/benchmarks/array
for file in *.php; do
    echo "Running $file..."
    php "$file"
done
```

## 测试配置

- **迭代次数**: 5,000 次
- **测试数据大小**: 根据函数特性调整（10-100 个元素）
- **性能目标**: 达到原生 PHP 的 105-120%

## 结果分析

测试完成后，会生成以下文件：

1. `array_benchmark_results.json` - JSON 格式的详细结果
2. 控制台输出 - 包含每个测试的性能数据

### 性能指标

- **操作/秒 (ops/s)**: 每秒可执行的操作次数
- **总时间 (ms)**: 完成所有迭代的总时间
- **平均时间 (ns)**: 单次操作的平均时间

## 需求验证

本测试验证以下需求：

- **需求 6.4**: 测试数组操作时，覆盖所有 60+ 数组函数
- **性能目标**: 所有数组函数性能达到原生 PHP 的 105-120%

## 注意事项

1. 确保系统有足够的内存运行测试
2. 关闭其他占用 CPU 的程序以获得准确结果
3. 多次运行测试以获得稳定的平均值
4. PHP 版本应为 8.5.0 或更高版本以确保对比公平
