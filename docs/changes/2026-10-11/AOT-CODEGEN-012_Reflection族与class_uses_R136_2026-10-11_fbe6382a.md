# AOT-CODEGEN-012 Reflection 族与 class_uses（R-136）_2026-10-11_fbe6382a

## 1. 高层摘要（TL;DR）

1. **Reflection 族取证 9 形**：7 形既有能力绿（newInstance/getMethods/Property/isInstantiable/invoke-with-object）；**3 处新红面修复**：①`ReflectionClass("myclass")` 跨大小写构造后 `getName()` 返回查找拼写（PHP 返回声明拼写）⇒ 构造器规范化；②`hasMethod("gm")` 对声明 `Gm` 漏判 ⇒ 走 `findMethodLookup`（CI+继承链，methods.contains 的超集）；③**`class_uses` 内建缺失** ⇒ 新增（空 array 实现 + trait 记录缺口登记）。
2. **验收**：r1 `MyClass|M` ✅（getName 规范拼写 + hasMethod CI）、r6 `array(0) {}` ✅（与 PHP 一致）、r8 `Gm|3` ✅；`zig build test` 通过；链 XV 主回归见报表。
3. 两轮实现自纠（生成码编译期抓回）：`toString` 返回 `*PHPString` 而非切片（`.data` 取值）；发射器 fmt 的 `{` 未转义（`{{`）。R-131 的 `hasMethod` 锚点首轮未匹配（缩进差异）亦复判定后重做。

## 2. 核心变更

| # | 变更 | 文件:位置 |
|---|---|---|
| 1 | ReflectionClass 构造器规范化 | runtime_lib_template.zig `__construct`（`findClass(name).name`） |
| 2 | hasMethod 走 findMethodLookup | 同文件（methods.contains → findMethodLookup != null） |
| 3 | `php_class_uses` 新内建（空 array）+ builtin_map 注册 | 同文件 + native_linker.zig |

## 3. 遗留与建议

| 优先级 | 事项 |
|---|---|
| P2 | `class_uses` 的 **trait 使用记录**（ClassMeta 无 trait 使用字段——parse 层展开即丢信息；需 R-C1 同款结构增字段，登记） |
| P2 | `ReflectionClass("nonexistent")` 应抛 ReflectionException（当前存原名静默，登记） |
| P2 | ReflectionMethod 对非静态方法 `invoke(null)` 的消息形状（AOT 尾行为空 vs PHP Fatal 同句——登记） |
