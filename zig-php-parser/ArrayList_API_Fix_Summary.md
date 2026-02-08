# Zig 0.15.2 ArrayList API 修复总结

## API 变化

### 旧 API (Zig 0.13.x 及更早)
```zig
var list = std.ArrayList(T).init(allocator);
defer list.deinit();
try list.append(item);
```

### 新 API (Zig 0.15.2)
```zig
var list = try std.ArrayList(T).initCapacity(allocator, 0);
defer list.deinit(allocator);
try list.append(allocator, item);
```

## 关键变化

1. **初始化**: `init(allocator)` → `initCapacity(allocator, 0)`
2. **释放**: `deinit()` → `deinit(allocator)`  
3. **追加**: `append(item)` → `append(allocator, item)`
4. **所有操作都需要显式传递 allocator**

## 修复状态

### ❌ 错误的修复方式（我之前使用的）
```zig
var list = std.ArrayList(T){ .allocator = allocator };  // 错误！
defer list.deinit();  // 错误！
```

### ✅ 正确的修复方式
```zig
var list = try std.ArrayList(T).initCapacity(allocator, 0);
defer list.deinit(allocator);
try list.append(allocator, item);
```

## 需要重新修复的文件

所有之前修复的文件都需要重新修复，因为：
1. 初始化方式错误
2. deinit() 缺少 allocator 参数
3. 所有 append/insert 等操作都需要传递 allocator

## 影响范围

这是一个破坏性的 API 变化，影响所有使用 ArrayList 的代码。
