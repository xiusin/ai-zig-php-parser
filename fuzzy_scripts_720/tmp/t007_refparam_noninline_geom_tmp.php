<?php
/**
 * 永久探针（AOT-CODEGEN-007 §7.2：COW 支缺 isPointerReg 判别在「非内联几何」下能否触达）
 *
 * 被检几何：一枚 `.param` 指令的 result 寄存器 IR 类型为 `.ptr`（⇒ native_linker.zig:5496-5499
 *   的第一支把它声明为 `*runtime.Value`），但发射时 is_ref_param 判别（:21042-21049，按
 *   `func.ref_params` 比对 `op.index`）为 false ⇒ 落入「普通参数 COW」支（:21134 起，
 *   仅按 is_alloca 判别目标类型 ⇒ 向 *Value 写 Value ⇒ Zig 类型错误）。
 *
 * 三径 index 编号口径（静态实读，本探针复验）：
 *   - ref_params 写入 = `param_index = func.params.items.len`（ir_generator.zig:1083/1092-1094）
 *   - `.param` 指令写入 = `i + param_offset`，param_offset = current_has_this_param ? 1 : 0
 *     （简单径 :1147/1157；默认值径 all_present 块 :1178/1208、has_missing 块 :1223-1258）
 *   - 非静态方法在 generateParameters 之前把 `this` addParam 到 index 0（:2510-2517）⇒ 两径同基
 *   - 闭包/箭头函数自建 Function 且 params 为空、current_has_this_param=false（:8706-8729/:8834-8844）⇒ 两径同基
 * ⇒ 静态结论：非内联时 `.ptr` 型 `.param` 必命中 ref_params ⇒ 该缺口不可达。
 *
 * 本探针在**默认档**（release_small ⇒ function_inlining=false）编译运行，直接复验上述结论；
 * 若任一行输出与 PHP 不等值或编译失败，则 §7.2 的「非内联面」成立，需把修复项 D 从 P2 升级。
 */

class T007Box
{
    // ① 实例方法 + 引用形参（this 偏移 = 1，简单径）
    public function mRef(array &$a): void
    {
        $a[] = 9;
    }

    // ② 实例方法 + 引用形参 + 默认值（默认值径：select/phi + 临时 alloca）
    public function mRefDefault(?array &$a = null): string
    {
        if ($a === null) {
            return "null-default";
        }
        $a["k"] = "v";
        return "set";
    }

    // ③ 静态方法 + 引用形参（无 this，偏移 = 0）
    public static function sRef(string &$s): void
    {
        $s = $s . "|static-ref";
    }

    // ④ 实例方法：引用形参 + 普通形参混排（两型 .param 同帧共存）
    public function mixedRef(array &$a, int $n): int
    {
        for ($i = 0; $i < $n; $i++) {
            $a[] = $i;
        }
        return count($a);
    }

    // ⑤ 实例方法：两个引用形参互换（同一 *Value 双槽）
    public function swapRef(string &$x, string &$y): void
    {
        $t = $x;
        $x = $y;
        $y = $t;
    }
}

$b = new T007Box();

$a1 = [1, 2];
$b->mRef($a1);
echo "M1 count=" . count($a1) . " last=" . $a1[2] . "\n";

$a2 = [7];
$r2 = $b->mRefDefault($a2);
echo "M2 " . $r2 . " k=" . $a2["k"] . "\n";
$a2b = null;
$r2b = $b->mRefDefault($a2b);
echo "M2b " . $r2b . " isnull=" . var_export($a2b === null, true) . "\n";

$s3 = "S";
T007Box::sRef($s3);
echo "M3=" . $s3 . "\n";

$a4 = [];
echo "M4 n=" . $b->mixedRef($a4, 3) . " sum=" . ($a4[0] + $a4[1] + $a4[2]) . "\n";

$x5 = "AAAA";
$y5 = "BBBB";
$b->swapRef($x5, $y5);
echo "M5 x=" . $x5 . " y=" . $y5 . "\n";

// ⑥ 闭包 + 引用形参（独立 Function，偏移 0）
$c6 = function (array &$a): void {
    $a[] = 42;
};
$a6 = [1];
$c6($a6);
echo "M6 count=" . count($a6) . " last=" . $a6[1] . "\n";

echo "DONE\n";
