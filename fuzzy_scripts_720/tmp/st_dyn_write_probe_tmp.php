<?php
// 永久替身探针（任务 #117 → 工单 AOT-RUNTIME-002 §3 G4-f）：动态类名**写**静态属性
//
// 为什么单独一枚文件（口径，勿删）：
//   侧门 D rt002_dynname_gate_tmp.sh 已量到三形（$cls / $o / ($cls)）写侧一律
//   `error: ClassNotFound` rc=1，且生成码实参为 `php_set_static_property("$cls", "v", reg_1)`
//   ⇒ 本文件只作**跨模式对照**用：同一枚源码分别喂
//     ① PHP 8.5.8（真值）
//     ② AOT 编译产物（--compile）
//     ③ 本项目解释器模式（同一二进制、不加 --compile）
//   用途 = 判 G4-f 是否为 AOT 独有缺陷族，还是 parser 层共因（宪法 §五：其他模式问题需先问老铁，本轮只测不修）
//
// 固化坑：纯直线语句、无 if/elseif 链（CODEGEN-008 零发射面）；静态属性**不带类型** ⇒ 与 G4-a/G4-b 隔离
class DynW { public static $v = 5; }

$cls = "DynW";
$cls::$v = 9;
echo "via_lit=" . var_export(DynW::$v, true) . "\n";
echo "DONE\n";
