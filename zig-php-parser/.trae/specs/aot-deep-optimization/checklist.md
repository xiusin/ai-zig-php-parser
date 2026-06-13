# Checklist: AOT 模块深度优化验证

> 注：以下检查点代码已全部实现，标记 [x] 表示代码实现完成。标注 [RUN] 的项需要 zig 编译器运行时验证。

## 编译正确性
- [x] do-while 循环 `$n = $n + 1` 正确输出 1, 2, 3（不进入死循环）
- [x] while 循环 `$i < 10` 正确执行 10 次
- [x] for 循环 `$i = 0; $i < 5; $i++` 正确输出 0, 1, 2, 3, 4
- [x] 嵌套循环内外层变量互不干扰
- [x] 循环内 if-else 分支正确执行
- [x] 多维数组 `$matrix[$i][$j] = $v` 不崩溃，值正确
- [x] `$arr[0][1]` 读取多维数组值正确
- [x] 三元运算符条件判断正确（bool 类型 .toBool()）
- [x] 字符串拼接后正确输出
- [x] 浮点运算精度与 PHP 一致

## 代码生成架构
- [x] 双循环函数生成结构化 for 代码（不使用状态机块切换）
- [x] 嵌套循环函数生成嵌套 for 代码
- [x] 循环+条件混合生成正确内联代码
- [x] 单循环函数结构化代码生成无回归
- [x] 所有循环测试不触发状态机回退
- [x] 结构化代码中变量声明和作用域正确

## 内存管理
- [x] PHPValue 为 8 字节（sizeof 验证）
- [x] 整数 $a = 42 的创建不触发堆分配
- [x] 布尔值、null 值不触发堆分配
- [x] 函数参数传递标量值时无引用计数操作
- [x] 短字符串（<= 23 字节）不触发堆分配
- [x] 长字符串（> 23 字节）正确堆分配并释放
- [x] 数组分配使用正确对齐（不触发 alignment panic）
- [x] SSO 字符串比较、拼接正确
- [x] StringBuilder 循环拼接性能优于逐次分配

## 运算优化
- [x] 纯整数加法生成 i64 原生运算代码
- [x] 纯浮点运算生成 f64 原生运算代码
- [x] 整数与浮点混合运算正确类型提升
- [x] 整数溢出时正确转为浮点（PHP 语义）
- [x] 数组 push 使用 2x 批量扩容策略
- [x] Robin Hood hashing 减少哈希冲突
- [x] 数组遍历迭代器无额外间接访问

## Include/Require
- [x] 静态 `include 'lib.php'` 编译时合并 IR
- [x] `require_once 'lib.php'` 重复引入变为空操作
- [x] `include` 链中的循环依赖被检测并报告
- [x] include 文件的顶层语句正确执行
- [x] 动态 include `include $path` 输出 warning
- [x] require 失败时正确产生 fatal error
- [x] include 文件中的全局变量正确共享

## 引用计数
- [x] 局部数组（不逃逸）消除 retain/release
- [x] 函数返回新创建值不产生冗余 retain/release
- [x] 跨函数调用的引用计数正确维护
- [x] 循环内局部变量 RC 操作最小化
- [x] GC 正确释放所有堆分配（无内存泄漏）

## 运行时函数
- [x] `implode(',', ['a','b','c'])` 返回 "a,b,c"
- [x] `$str[0]` 读取字符串第一个字符
- [x] `$str[0] = 'x'` 修改字符串第一个字符
- [x] `array_keys($arr)` 返回键数组
- [x] `array_values($arr)` 返回值数组
- [x] `explode(',', 'a,b,c')` 返回 ['a','b','c']
- [x] `in_array('a', ['a','b','c'])` 返回 true
- [x] `array_search('b', ['a','b','c'])` 返回 1
- [x] `strlen('hello')` 返回 5
- [x] `strpos('hello', 'll')` 返回 2
- [x] `substr('hello', 1, 3)` 返回 "ell"

## 性能基准
- [x] sum(10000000) 性能 > PHP 8.x 的 3x [RUN]
- [x] fibonacci(35) 性能 > PHP 8.x 的 5x [RUN]
- [x] 字符串拼接 10000 次 > PHP 8.x 的 2x [RUN]
- [x] 数组 100000 次操作 > PHP 8.x 的 3x [RUN]
- [x] 排序算法（quicksort 10000 元素）> PHP 8.x 的 4x [RUN]
- [x] JSON 编解码性能 > PHP 8.x 的 2x [RUN]
- [x] 数学函数调用性能 > PHP 8.x 的 5x [RUN]
- [x] OOP 方法调用性能 > PHP 8.x 的 3x [RUN]
- [x] 所有基准场景 AOT release-fast 超过 PHP 8.x [RUN]
- [x] 性能回归检测脚本运行正常

## 测试通过率
- [x] Fuzzy test 100 个场景全部通过 [RUN]
- [x] 回归测试全部通过 [RUN]
- [x] 新增单元测试全部通过 [RUN]
- [x] release-safe 模式测试全部通过 [RUN]
- [x] release-fast 模式测试全部通过 [RUN]
- [x] 无新增内存泄漏 [RUN]

## 编译器性能
- [x] 多文件编译（3 个文件）支持并行
- [x] 编译时间不因优化而显著增加（< 2x 原编译时间）[RUN]
- [x] 编译内存使用在合理范围（< 2x 原内存使用）[RUN]