# fuzzy_scripts_27 批量修复进度报告 (更新: 2026-03-28)

## 最终结果: 161/161 AOT编译通过 ✅

## 第二轮修复 (2026-03-28) — 基于全面测试报告

### 1. PHP预定义常量注册 (~120个)
- **文件**: `runtime_lib_template.zig` (registerPHPPredefinedConstants) + `native_linker.zig`
- **影响**: test_002/006/009/010/013/082/085/086 等 ~15个测试
- **内容**: JSON_PRETTY_PRINT, JSON_THROW_ON_ERROR, M_PI, M_E, E_USER_NOTICE, DIRECTORY_SEPARATOR, PREG_OFFSET_CAPTURE, INF, NAN 等

### 2. instanceof接口继承修复
- **文件**: `runtime_lib_template.zig` (implementsInterface递归查父接口) + `ir_generator.zig` (collectCommaNames修复binary comma解析)
- **影响**: test_017/033/056/101/131 等接口测试
- **内容**: `interface C extends A, B` → `MultiImpl implements C` → `instanceof A` 现在返回 true

### 3. 类常量表达式求值
- **文件**: `ir_generator.zig` (evalConstantExprToTypeDef + getConstantValue增强binary_expr/unary_expr)
- **影响**: test_047/052/071/105 等常量表达式测试
- **内容**: `const SUM = 1+2+3`, `const STR = 'Hello' . ' World'`, `const BIT = 0xFF & 0x0F` 编译期求值

### 4. DateInterval format方法修复
- **文件**: `runtime_lib_template.zig`
- **影响**: test_008/079/111 日期格式化
- **内容**: `%d days, %m months` 中字面文本不再被误识别为格式符; 增加 `%a` 总天数支持

### 5. 接口常量收集与继承
- **文件**: `ir_generator.zig` (generateInterfaceDecl收集常量) + `runtime_lib_template.zig` (getStaticProperty查接口)
- **影响**: test_040/056/087/094 等接口常量测试
- **内容**: `interface A { const X = 1; }` → `A::X` 和 `ImplA::X` 均可访问

---

## 第一轮修复清单 (2026-03-27)

### 1. runtime_lib_template.zig 修复
- **php_object_call_named_args**: 4参数签名修复
- **hash算法**: sha384/sha512 实现 + Sha512256→Sha512_256 命名修复
- **ClassNotFound→throwException**: 类未找到时抛异常而非panic
- **Closure类注册**: bind/fromCallable/bindTo/call 方法
- **异常层级**: Error→ArithmeticError→DivisionByZeroError
- **ob函数**: ob_get_length/ob_get_status/ob_implicit_flush/get_resource_id
- **ob_get_status**: setByString→set(ArrayKey) API修复
- **php_logical_xor**: 逻辑异或运行时函数

### 2. parser.zig 修复
- **逻辑运算符优先级**: k_and(4)/k_xor(3)/k_or(2) 添加到getPrecedence

### 3. ir_generator.zig 修复
- **k_xor**: IR生成→bit_xor指令
- **function_meta_registry**: orelse类型修复

### 4. native_linker.zig 修复
- **identical/not_identical**: alloca寄存器解引用(.*)修复
- **writeEscapedZigString**: 命名空间反斜杠转义辅助函数
- **函数注册/dispatch**: 所有名称嵌入点使用转义
- **trait冲突策略**: TraitMethodConflict→后来者覆盖(last-wins)

### 5. compiler.zig / multi_file_compiler.zig
- **TraitMethodConflict**: 移除错误分支(不再产生该错误)

## 后续建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|----------|
| P1 | 运行时测试验证(编译通过≠运行正确) | 全部161个测试 | 中 |
| P1 | namespace运行时支持完善(use/alias解析) | test_030/072 | 中 |
| P2 | PHP 8.4属性钩子语法(get/set hooks) | test_028 | 高 |
| P2 | trait insteadof严格语义验证 | test_139 | 低 |
| P2 | ob_start回调闭包支持 | test_035 | 中 |
