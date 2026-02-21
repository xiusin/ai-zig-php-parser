# P0 阶段验证指南

## 快速验证

```bash
cd /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser

# 给脚本执行权限
chmod +x tests/aot/verify_p0.sh

# 运行 P0 验证
bash tests/aot/verify_p0.sh
```

## 验证内容

### P0-1: 类型转换修复（7 个用例）
- 05_foreach_break
- 34_bool
- 41_nested_break_levels
- 44_do_while_nested
- 47_deep_nesting
- 50_mixed_break_continue
- 51_unset_iter_consistency

**验证点**：
- ✅ 编译成功（无类型错误）
- ✅ 运行成功（exit 0）
- ✅ 输出匹配 PHP

### P0-2: panic 修复（5 个用例）
- 42_nested_continue_levels
- 43_mixed_control_flow
- 45_match_in_loop
- 46_complex_nesting
- 49_recursive_with_loops

**验证点**：
- ✅ 编译成功
- ✅ 运行不 panic（exit ≠ 134）
- ⚠️  可能超时或输出不匹配（P1 阶段修复）

### P0-3: unset 语义（1 个用例）
- 52_foreach_by_ref

**验证点**：
- ✅ 编译成功（无 undeclared identifier 错误）
- ✅ 运行成功
- ✅ 输出匹配 PHP
- ✅ 无内存泄漏（live_allocs=0）

## 预期结果

### 最佳情况
```
编译成功率: 100% (13/13)
运行成功率: 100% (13/13)
输出匹配率: 100% (13/13)
```

### 可接受情况
```
编译成功率: 100% (13/13)  ← P0 目标
运行成功率: 60-80%        ← P0-2 可能有超时
输出匹配率: 60-80%        ← P1-2 修复
```

### 不可接受情况
```
编译成功率: < 100%        ← P0 失败
```

## 手动验证（如果脚本失败）

### 单个用例测试
```bash
# 1. 编译
tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/05_foreach_break.php

# 2. 运行
ZIGPHP_ALLOC_STATS=1 tests/aot/timeout.sh 4 ./05_foreach_break

# 3. 对比输出
php tests/aot/suite/05_foreach_break.php
```

### 检查编译错误
```bash
# 如果编译失败，查看详细错误
zig-out/bin/php-interpreter --compile tests/aot/suite/05_foreach_break.php 2>&1 | grep "error:"
```

### 检查运行时错误
```bash
# 如果运行失败，查看详细输出
./05_foreach_break 2>&1 | head -20
```

## 故障排查

### 编译失败
1. 检查 Zig 版本：`zig version`（需要 0.15.2+）
2. 清理构建：`rm -rf zig-cache zig-out .zigphp_aot_build`
3. 重新编译：`zig build -Doptimize=ReleaseFast install`

### 运行 panic (exit 134)
- 说明 P0-2 修复未生效
- 检查生成的代码：`cat .zigphp_aot_build/main.zig | grep "else =>"`
- 应该看到错误处理而非 `unreachable`

### 输出不匹配
- 这是预期的（P1-2 阶段修复）
- 只要不 panic 就算 P0-2 成功

### 内存泄漏
- 检查 alloc stats：`grep "live_allocs" output.log`
- P0-3 应该无泄漏
- 其他用例可能有泄漏（P1-3 修复）

## 验证报告

验证完成后，请记录：

1. **编译成功率**：___ / 13
2. **运行成功率**：___ / 13
3. **输出匹配率**：___ / 13
4. **失败用例**：
   - 编译失败：___
   - 运行失败：___
   - 输出不匹配：___

## 下一步

### 如果 P0 全部通过
- ✅ 继续 P1-1（do-while 超时）
- ✅ 继续 P1-2（输出不匹配）
- ✅ 继续 P1-3（内存泄漏）

### 如果 P0 部分失败
- ❌ 分析失败原因
- ❌ 修复编译错误
- ❌ 重新验证

---

**验证时间**：2026-02-20  
**验证人员**：xiusin  
**预计耗时**：5-10 分钟
