# AOT 最小复现脚本（解释器 vs AOT）

这些脚本用于把“解释器已支持，但 AOT（native_linker 路径）可能不支持/语义不一致”的点固定为可回归的最小样例。

## 目录说明
- `oop_method_args.php`：类方法参数传递（AOT wrapper 当前可能忽略 args）。
- `oop_construct_args.php`：构造函数多参数（AOT wrapper 当前可能只取前 2 个参数）。
- `builtin_file_get_contents.php`：常见文件类 builtin（解释器有更完整 builtin 集合，AOT 白名单/实现可能缺失）。
- `callback_array_map.php`：字符串回调/内建回调查表（AOT runtime template 的 callable 白名单较小）。

## 期望
- 解释器模式下（tree/bytecode/fast）应能运行并输出预期结果。
- AOT 模式下如果失败，应给出明确错误（而不是静默错误/错误结果）。

