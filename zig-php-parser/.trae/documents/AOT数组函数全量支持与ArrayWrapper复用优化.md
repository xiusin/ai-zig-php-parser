## 现状结论
- AOT 数组内建函数有两层：codegen 映射/传参（native_linker.zig）+ AOT runtime 实现（runtime_lib_template.zig）。当前存在“白名单已声明但未映射/未传 allocator”的断链点，以及“模板已实现但 PHP 侧不可达”的缺口。
- runtime/array_wrapper.zig 可作为数组操作语义基座，但其 map/filter 目前不执行 callback，需要与 AOT 的 php_invoke_callable 对接。

## 目标范围（覆盖“PHP所有相关数组函数”）
- 以解释器侧 BuiltinId 的 Array Functions 为最小覆盖基线，并补齐常见 PHP 数组生态：
  - 结构操作：push/pop/shift/unshift/splice/slice/merge/combine/fill/pad/chunk
  - 查询与集合：keys/values/search/in_array/key_exists/unique/flip/intersect/diff
  - 聚合：count/sizeof/sum/product
  - 排序族：sort/rsort/asort/arsort/ksort/krsort + u*sort（带用户比较器）
  - 迭代与指针族：current/next/prev/reset/end/key/each（若解释器支持则对齐）
  - 高阶：map/filter/reduce/walk/column

## 实施方案（AOT为主，DRY优先）
1) 修复 AOT 分发链（P0）
- 在 native_linker.zig：
  - 补全 array_shift/array_unshift/array_key_exists 等到 php_array_* 的映射。
  - 在 functionNeedsAllocator 中补齐所有会分配/拷贝/新建数组的 array_*，避免签名不匹配。
  - 将“isBuiltinFunction 白名单”与“mapToRuntimeFunction 映射表”改为单一数据源（例如编译期表驱动），避免再次出现白名单≠映射。

2) 打通“模板已实现但不可达”的函数（P1）
- 为 runtime_lib_template.zig 已存在的 php_array_reverse/unique/flip/search/column/walk/key_first/key_last/fill 等补齐 PHP 名称入口（native_linker 映射 + allocator 标记）。

3) 补齐解释器存在但 AOT 缺失的函数（P2）
- 在 runtime_lib_template.zig 新增缺失的 php_array_* 实现，并严格对齐 PHP 语义（键处理、返回值类型、稳定性/排序规则、可选参数）。
- 排序族：
  - 无回调的 sort/asort/ksort 等：实现统一排序内核（提取 keys+values -> 排序 -> 重建 PHPArray）。
  - 带用户回调的 usort/uasort/uksort：复用 php_invoke_callable 执行比较器，处理三态返回（<0/0/>0）。

4) 复用/对齐 ArrayWrapper（减少重复、统一语义）
- 新增共享模块（建议 src/shared/array_ops.zig 或类似）把 ArrayWrapper 抽象为“类型参数化”实现：
  - 解释器 runtime 用 runtime/types.zig 实例化。
  - AOT runtime 模板用其内部 Value/PHPArray 实例化。
- 在共享实现中：
  - 保留 push/pop/shift/unshift/reverse/keys/values 等基础操作。
  - 对 map/filter/reduce/walk：不在 wrapper 内硬编码 callback，而是注入一个可调用接口（AOT 绑定到 php_invoke_callable；解释器绑定到其运行时 callable 入口）。

## 验证与门禁
- 单元测试：新增覆盖表格驱动用例（整数键/字符串键混合、空数组、稀疏键、引用计数 retain/release 路径）。
- AOT 端到端：编译一组包含 array_* 的 PHP 样例，确认 codegen 生成的 runtime 符号存在且签名匹配。
- 性能基线：为 push/pop/keys/values/sort/merge 做 micro-bench，对比改造前后（重点关注减少临时分配与避免重复遍历）。

## 交付物
- AOT：native_linker.zig 的映射/allocator 判定表驱动化 + runtime_lib_template.zig 的 php_array_* 全量实现。
- 共享：可被 AOT 与 runtime 同时复用的 ArrayWrapper/array_ops 实现。
- 测试：新增数组函数语义与回调执行的高覆盖测试集。