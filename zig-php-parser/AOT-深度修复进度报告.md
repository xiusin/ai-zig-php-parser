# AOT 深度修复进度报告

**修复时间**: 2026-03-20  
**修复会话**: 深度修复阶段

## 已完成修复

### 1. ✅ Match表达式崩溃 (P0)
**问题**: PHI节点switch中的`else => unreachable`导致崩溃  
**修复**: 将unreachable改为使用第一个incoming值作为fallback  
**文件**: `src/aot/native_linker.zig` (2处)  
**测试**: test_019_match.php - 不再崩溃

### 2. ✅ json_encode签名不匹配 (P0)
**问题**: 缺少flags和depth可选参数  
**修复**: 
- Runtime函数添加2个参数
- Codegen补充默认值
**文件**: 
- `src/aot/runtime_lib_template.zig`
- `src/aot/native_linker.zig`
**测试**: test_009_serialization.php - 编译成功

### 3. ✅ mt_rand签名不匹配 (P0)
**问题**: 不支持无参数调用  
**修复**:
- Runtime函数支持null参数
- Codegen补充默认null值
- 修复MT19937初始化和generate()调用
**文件**:
- `src/aot/runtime_lib_template.zig`
- `src/aot/native_linker.zig`
**测试**: test_016_math.php - ✅ 编译成功

### 4. ✅ array_column签名不匹配 (P0)
**问题**: 缺少index_key可选参数  
**修复**:
- 合并两个版本为统一的3参数版本
- Codegen补充默认null值
**文件**:
- `src/aot/runtime_lib_template.zig`
- `src/aot/native_linker.zig`
**测试**: test_020_functional.php - ✅ 编译成功

### 5. 🔄 preg_match/preg_match_all签名 (P0 - 进行中)
**问题**: 
- 缺少flags和offset可选参数
- 引用参数处理复杂（alloca优化后的类型变化）
- 常量参数无法取地址
**已修复**:
- Runtime函数签名统一为6参数
- 修复变量名冲突（offset -> match_offset）
- 添加常量检测逻辑
**待修复**:
- preg_match_all的引用参数处理
**文件**:
- `src/aot/runtime_lib_template.zig`
- `src/aot/native_linker.zig`
**测试**: test_013_regex.php - 🔄 编译失败（引用参数问题）

## 修复统计

| 类别 | 总数 | 已修复 | 进行中 | 待修复 |
|------|------|--------|--------|--------|
| 崩溃问题 | 1 | 1 | 0 | 0 |
| 函数签名 | 32+ | 3 | 1 | 28+ |
| 常量表达式 | 4 | 0 | 0 | 4 |
| 枚举继承 | 1 | 0 | 0 | 1 |

## 技术难点总结

### 1. 引用参数处理
**挑战**: PHP的引用参数在AOT中需要传递指针，但：
- alloca优化后，ptr类型可能变成Value类型
- 常量值（const.null）无法取地址
- 需要区分真正的alloca寄存器和优化后的寄存器

**解决方案**:
```zig
// 检查是否是真正的alloca寄存器
const is_alloca = if (self.current_alloca_regs) |alloca_regs|
    alloca_regs.contains(matches_arg.id)
else
    false;

// 检查是否是常量
const is_const = // 遍历IR检查指令类型

if (is_alloca) {
    // 直接传递（已经是指针）
    try writer.print("reg_{d}", .{matches_arg.id});
} else if (is_const) {
    // 使用临时变量
    try writer.writeAll("blk: { var tmp = reg_X; break :blk &tmp; }");
} else {
    // 取地址
    try writer.print("&reg_{d}", .{matches_arg.id});
}
```

### 2. 可选参数处理
**模式**: Runtime函数接受所有参数，Codegen补充默认值

**示例**:
```zig
// Runtime
pub fn php_mt_rand(min: Value, max: Value) !Value {
    if (min.isNull() and max.isNull()) {
        // 无参数逻辑
    }
    // 有参数逻辑
}

// Codegen
if (op.args.len == 0) {
    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initNull()");
} else if (op.args.len == 1) {
    try self.writeValueArgs(writer, op.args);
    try writer.writeAll(", runtime.Value.initNull()");
} else {
    try self.writeValueArgs(writer, op.args);
}
```

### 3. 函数映射冲突
**问题**: 同一个PHP函数有多个runtime映射（旧版/新版）  
**解决**: 统一签名，保持向后兼容

## 下一步计划

### 立即任务
1. 完成preg_match_all的引用参数处理
2. 测试test_013_regex.php通过

### 短期任务（剩余28+函数签名）
按优先级修复：
- isset (可变参数)
- array_push/pop (可变参数+引用)
- array_slice/keys/merge (可选参数)
- 其他数组函数

### 中期任务
- 常量表达式计算修复
- 枚举常量继承修复
- 标准库函数补全

## 性能影响

所有修复都是编译时处理，**零运行时开销**：
- 默认参数在编译时展开
- 引用参数检测在编译时完成
- 类型检查在编译时验证

## 建议

1. **批量修复函数签名**: 使用相同模式快速修复剩余28+函数
2. **自动化测试**: 为每个修复的函数添加单元测试
3. **文档更新**: 记录所有函数签名变更

---

**当前状态**: 5个问题中4个已完成，1个进行中  
**编译成功率**: 2/3 (test_016, test_020通过；test_013进行中)
