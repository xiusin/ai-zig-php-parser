# AOT编译器下一步行动计划

## 🎯 当前状态

- **通过率**: 54.1% (前50个脚本)
- **已知问题**: 3个（已文档化）
- **最大阻塞**: 问题1 (foreach+try-catch, 42%影响)

## 📋 优先级排序

### P0 - 阻塞性问题（必须解决）

#### 问题1: foreach内部try-catch unreachable
- **影响**: 42%的脚本
- **难度**: 🔴 非常高
- **建议方案**:
  1. **短期**: 文档化Workaround（✅ 已完成）
  2. **中期**: 尝试升级Zig版本
  3. **长期**: 重构变量管理系统

### P1 - 重要问题（应该解决）

#### 问题2: 数组迭代器integer overflow
- **影响**: 1%的脚本
- **难度**: 🟡 高
- **建议方案**:
  1. 使用Valgrind深入调试
  2. 检查ArrayHashMap的内存管理
  3. 添加capacity边界检查

### P2 - 优化项（可选）

#### 问题3: StringTooLarge限制
- **影响**: 2%的脚本
- **难度**: 🟢 低
- **建议方案**:
  1. 增加限制到500MB
  2. 添加配置选项
  3. 优化字符串拼接性能

## 🔧 具体行动步骤

### 步骤1: 尝试升级Zig版本（推荐）

**目标**: 验证问题1是否是Zig 0.15.2的bug

**步骤**:
```bash
# 1. 备份当前版本
git commit -am "backup: 当前版本 (Zig 0.15.2)"

# 2. 升级Zig到最新版本
brew upgrade zig

# 3. 重新编译
zig build

# 4. 测试前50个脚本
# (使用之前的测试脚本)

# 5. 对比通过率
```

**预期结果**:
- 如果通过率提升 > 10%: 说明是Zig bug，继续使用新版本
- 如果通过率不变: 说明是我们的代码问题，回退版本

**时间**: 30分钟

---

### 步骤2: 深入调试问题2（如果步骤1失败）

**目标**: 找到integer overflow的根本原因

**步骤**:
```bash
# 1. 使用Valgrind调试
valgrind --leak-check=full --track-origins=yes \
  /tmp/test_0007 2>&1 | tee valgrind.log

# 2. 添加调试日志
# 在runtime_lib_template.zig的iterator()中添加:
std.debug.print("capacity: {d}\n", .{m.capacity()});

# 3. 检查ArrayHashMap的状态
# 在convertToMixed()后验证capacity

# 4. 添加边界检查
if (m.capacity() > 1000000) {
    @panic("capacity too large");
}
```

**预期结果**:
- 找到capacity被错误设置的位置
- 修复内存破坏问题

**时间**: 2-3小时

---

### 步骤3: 替换HashMap为ArrayList（备选方案）

**目标**: 如果问题1和问题2都无法修复，使用更简单的数据结构

**步骤**:
```zig
// 1. 修改Elements结构
pub const Elements = struct {
    // 替换mixed为简单的ArrayList
    vars: std.ArrayList(struct { name: []const u8, reg: u32 }),
    
    // 2. 修改put/get/remove方法
    pub fn put(self: *Elements, name: []const u8, reg: u32) !void {
        // 线性查找
        for (self.vars.items) |*v| {
            if (std.mem.eql(u8, v.name, name)) {
                v.reg = reg;
                return;
            }
        }
        try self.vars.append(.{ .name = name, .reg = reg });
    }
};
```

**优点**:
- 简单，不容易出错
- 没有HashMap的复杂性

**缺点**:
- 性能下降（O(n) vs O(1)）
- 但对于小规模变量表（<100个变量）影响不大

**时间**: 1-2小时

---

### 步骤4: 重构变量管理（长期方案）

**目标**: 设计更健壮的变量管理系统

**设计**:
```zig
// 1. 独立的作用域管理
pub const ScopeManager = struct {
    scopes: std.ArrayList(Scope),
    
    pub const Scope = struct {
        vars: std.StringHashMap(u32),
        parent: ?*Scope,
    };
    
    // 2. foreach使用独立的作用域
    pub fn enterForeach(self: *ScopeManager) !void {
        const new_scope = Scope{
            .vars = std.StringHashMap(u32).init(self.allocator),
            .parent = self.currentScope(),
        };
        try self.scopes.append(new_scope);
    }
    
    // 3. try-catch也使用独立的作用域
    pub fn enterTryCatch(self: *ScopeManager) !void {
        // 类似enterForeach
    }
};
```

**优点**:
- 清晰的作用域管理
- 避免HashMap冲突
- 更符合PHP的语义

**缺点**:
- 需要大量重构
- 可能引入新的bug

**时间**: 1-2天

---

## 🎯 推荐路径

### 路径A: 快速验证（推荐）
1. ✅ 步骤1: 升级Zig版本（30分钟）
2. 如果成功 → 完成
3. 如果失败 → 路径B

### 路径B: 深入修复
1. ✅ 步骤2: 调试问题2（2-3小时）
2. ✅ 步骤3: 替换HashMap（1-2小时）
3. 测试通过率
4. 如果通过率 > 90% → 完成
5. 如果通过率 < 90% → 路径C

### 路径C: 长期重构
1. ✅ 步骤4: 重构变量管理（1-2天）
2. 全面测试
3. 完成

---

## 📊 预期结果

### 路径A成功
- **通过率**: 95%+
- **时间**: 30分钟
- **风险**: 低

### 路径B成功
- **通过率**: 90%+
- **时间**: 3-5小时
- **风险**: 中

### 路径C成功
- **通过率**: 98%+
- **时间**: 1-2天
- **风险**: 高

---

## 💡 建议

**立即行动**: 尝试路径A（升级Zig版本）

**理由**:
1. 时间成本最低（30分钟）
2. 风险最小（可以回退）
3. 如果成功，可以一次性解决多个问题
4. Zig 0.15.2已经比较老了，升级是必然的

**如果路径A失败**: 考虑路径B（替换HashMap）

**理由**:
1. 时间成本可控（3-5小时）
2. 可以解决大部分问题
3. 不需要大规模重构

**避免路径C**: 除非前两个路径都失败

**理由**:
1. 时间成本太高（1-2天）
2. 风险太大（可能引入新bug）
3. 性价比低

---

**创建时间**: 2026-03-08 09:35
**当前通过率**: 54.1%
**目标通过率**: 95%+
**推荐路径**: A → B → C
