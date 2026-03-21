# AOT 函数签名不匹配修复报告

**修复时间**: 2026-03-20  
**问题**: 32个COMPILE_FAIL由于函数签名不匹配  
**根因**: runtime函数签名与PHP标准不一致，缺少可选参数支持

## 已修复函数

### 1. json_encode ✅
**PHP签名**: `json_encode(mixed $value, int $flags = 0, int $depth = 512): string|false`

**修复前**:
```zig
pub fn php_json_encode(value: Value, allocator: Allocator) !Value
```

**修复后**:
```zig
pub fn php_json_encode(value: Value, flags: Value, depth: Value, allocator: Allocator) !Value {
    const flags_int = if (flags.isInt()) flags.asInt() else 0;
    const depth_int = if (depth.isInt()) depth.asInt() else 512;
    // ...
}
```

**Codegen处理**:
```zig
else if (std.mem.eql(u8, runtime_name, "php_json_encode")) {
    // json_encode(value, flags = 0, depth = 512)
    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
    if (op.args.len > 0) {
        try self.writeValueArgs(writer, op.args);
        if (op.args.len == 1) {
            try writer.writeAll(", runtime.Value.initInt(0), runtime.Value.initInt(512)");
        } else if (op.args.len == 2) {
            try writer.writeAll(", runtime.Value.initInt(512)");
        }
    }
    try writer.writeAll(", runtime.runtime_allocator);\n");
}
```

## 待修复函数清单

### 高优先级（阻塞编译）

| 函数 | PHP签名 | 当前问题 | 测试脚本 |
|------|---------|----------|----------|
| preg_match | `preg_match(string $pattern, string $subject, array &$matches = null, int $flags = 0, int $offset = 0): int\|false` | 参数数量不匹配 | test_013_regex.php |
| mt_rand | `mt_rand(int $min = null, int $max = null): int` | 可选参数处理 | test_016_math.php |
| array_column | `array_column(array $array, int\|string\|null $column_key, int\|string\|null $index_key = null): array` | 缺少index_key参数 | test_020_functional.php |
| isset | `isset(mixed ...$vars): bool` | 可变参数支持 | test_150_isset_empty.php |
| array_push | `array_push(array &$array, mixed ...$values): int` | 可变参数+引用 | test_288_array_funcs.php |
| array_pop | `array_pop(array &$array): mixed` | 引用参数 | test_195_array_push_pop.php |
| array_slice | `array_slice(array $array, int $offset, ?int $length = null, bool $preserve_keys = false): array` | 可选参数 | test_196_array_slice.php |
| array_keys | `array_keys(array $array, mixed $filter_value = null, bool $strict = false): array` | 可选参数 | test_197_array_keys.php |
| array_merge | `array_merge(array ...$arrays): array` | 可变参数 | test_198_array_merge.php |

### 修复策略

#### 策略1: 可选参数（如json_encode）
1. 修改runtime函数签名，添加所有参数
2. 在函数内部处理默认值
3. 在codegen中补充缺失参数

#### 策略2: 可变参数（如isset, array_push）
1. Runtime函数接受`[]const Value`切片
2. Codegen使用`writeValueArgsArray`生成数组字面量

#### 策略3: 引用参数（如preg_match, array_pop）
1. Runtime函数接受`*Value`指针
2. Codegen检测alloca寄存器，传递指针

## 下一步行动

按优先级修复：
1. ✅ json_encode (已完成)
2. 🔄 preg_match (进行中)
3. mt_rand
4. array_column
5. isset
6. array_push/pop
7. array_slice/keys/merge

## 修改文件

- `src/aot/runtime_lib_template.zig` - 函数签名
- `src/aot/native_linker.zig` - Codegen默认参数处理
