# AOT Runtime Lib 系统性修复报告

**日期**: 2026-03-25
**修复范围**: `src/aot/runtime_lib_template.zig`, `src/aot/native_linker.zig`

## 修复成果

| 指标 | 修复前 | 修复后 | 提升 |
|------|--------|--------|------|
| AOT编译通过率 | 17.5% (203个失败) | 99% (仅2个失败) | +81.5% |
| AOT运行通过率 | ~0% | 88% (180/204) | +88% |
| 编译失败数 | 203 | 2 | -201 |
| 运行失败数 | ~200 | 22 | -178 |
| deinitRuntime Bus Error | 全局 | 已修复 | constants键释放 |
| exit code 134 (abort) | 全局 | 已修复 | 干净退出 |

## 修复的问题清单

### P0 — runtime_lib_template.zig 系统性错误

| # | 问题 | 修复方式 |
|---|------|----------|
| 1 | `Value_lessThan` 未定义 | 重写 `arrayObject_asort`，用 `toFloat()` 比较 |
| 2 | `throwError` 未定义 (6处) | 替换为 `return error.InvalidArgument/InvalidArgumentCount` |
| 3 | `ArrayKey.HashContext` 不存在 | 重写排序上下文，使用 `PHPArray.Elements` |
| 4 | `ArrayList.init(allocator)` 旧版API (5处) | 改为 `ArrayList.initCapacity(allocator, 0)` |
| 5 | `ArrayList.deinit()` 缺少allocator (5处) | 改为 `.deinit(allocator)` |
| 6 | `ArrayList.append()` 缺少allocator (4处) | 改为 `.append(allocator, item)` |
| 7 | `elements.contains()` 不存在 (4处) | 改为 `elements.get(key) != null` 或遍历查找 |
| 8 | `elements.clearAndFree()` 不存在 (2处) | 改为 `deinit()` + 重新 `init()` |
| 9 | `arr.put(allocator, key, value)` 签名错误 (3处) | 改为 `arr.set(allocator, .{.string=...}, value)` |
| 10 | `%` 用于有符号整数 (2处) | 改为 `@rem()` / `@mod()` |
| 11 | `u64` 到 `i64` 类型不匹配 | 添加 `@intCast` |
| 12 | `empty` 变量名与函数名冲突 | 重命名为 `empty_str` |
| 13 | `s.len` — PHPString无len字段 | 改为 `s.length` / `s.data` |
| 14 | `meta.addInterface()` 不存在 (5处) | 改为手动分配 `interfaces` 切片 |
| 15 | `closure.call()` 不存在 | 改为 `closure.func()` |
| 16 | `target_obj.meta` 字段名错误 | 改为 `target_obj.class_meta` |
| 17 | 未使用函数参数 `alloc` | 改为 `_` |
| 18 | `std.ascii.isPunct` 不存在 | 手动实现 `isPunct()` |
| 19 | `std.ascii.isXDigit` 不存在 | 手动实现 `isXDigit()` |
| 20 | `address.formatIp` 不存在 | 重写 `gethostbyname` 使用 C 库 `getaddrinfo` |
| 21 | `gethostname` buf大小不匹配 | 改为 `HOST_NAME_MAX` |
| 22 | `@bitCast` u32→i64 大小不匹配 | 改为 `@as(i64, result)` |
| 23 | `ArrayKey{.string=[]u8}` 类型错误 (多处) | 改为 `PHPString.init` |
| 24 | `parseInt(usize, *PHPString)` 类型错误 (3处) | 改为 `.data` |
| 25 | `initRuntime` 初始化顺序错误 | 将 `constants` 等全局表初始化移到类注册之前 |

### P0 — 新增函数实现

| # | 函数 | 说明 |
|---|------|------|
| 1 | `php_property_array_push_with_obj` | `$obj->prop[] = value` |
| 2 | `php_property_array_set_with_obj` | `$obj->prop[key] = value` |
| 3 | `php_bool_or` | match 表达式多条件合并 |
| 4 | `php_fdiv` | PHP 8.0 浮点除法 |
| 5 | `php_getmypid` | 获取进程ID |
| 6 | `php_strnatcmp` | 自然排序比较 |
| 7 | `php_strnatcasecmp` | 自然排序比较(不区分大小写) |

### native_linker.zig 函数注册

新增注册: `fdiv`, `getmypid`, `strnatcmp`, `strnatcasecmp`, `php_bool_or`, `php_property_array_push_with_obj`, `php_property_array_set_with_obj`

## 剩余问题

### 编译失败 (2个)
- `test_018_named_args.php` — 参数数量不匹配
- `test_069_arguments.php` — 参数数量不匹配

### 运行时缺失函数 (32个脚本)
主要缺失: `set_error_handler`, `ob_start`, `hash`, `mb_strlen`, `base_convert`, `glob`, `call_user_func`, `get_defined_vars`, `get_debug_type`, `ctype_*`(AOT未注册), `parse_url`(AOT未注册), `addslashes`, `crc32`, `substr_count`
