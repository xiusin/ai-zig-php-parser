<?php
/**
 * 永久探针（AOT 动态调用族的「引用形参未装填」定面，任务 #89）
 *
 * 机制（实测锚点，代次 fbe6382a/32797）：
 *   - 引用形参的实参装填（temp alloca + ref_aware_store + make_ref）在
 *     ir_generator.zig:6810-6850 的 else 支，按 **函数名** 三元查表：
 *     module.findFunction(func_name) / function_ref_params.get(func_name) / getBuiltinRefParams(func_name)，
 *     三者都以 `func_name.len > 0` 为前提。
 *   - 动态调用（`indirect_callee`，:6229-6249 设置）无名可查 ⇒ 实参原样透传 ⇒
 *     .call_indirect（:7362）⇒ native_linker.zig:23406-23420 发射 php_invoke_callable(callback, &[_]Value{raw})。
 *   - callee 侧 native_linker.zig:21055 的引用形参支回落 `else &null_val` ⇒ 后续按数组写入 ⇒ 段错误。
 *
 * 用法：每次只跑一个形态（段错误会终止进程，故用 $argv 选路，一次编译多轮运行）。
 *   php  aot_bin vfn | cuf | arrcb | this_cb | ctrl_named | ctrl_walk
 * 期望：PHP 与 AOT 对同一 shape 输出逐字节等值；AOT 若在 vfn/cuf/arrcb 段错误即为该族证据。
 */

function t007dyn_ctrl(array &$a): void
{
    $a[] = 9;
}

$t007dyn_cl = function (array &$a): void {
    $a[] = 42;
};

class T007Dyn
{
    public function cbRef(array &$a): void
    {
        $a[] = 7;
    }

    public function runViaProperty(array &$a): void
    {
        $f = [$this, 'cbRef'];
        $f($a);
    }
}

$shape = $argv[1] ?? 'ctrl_named';
$out = "SHAPE=" . $shape . " ";

switch ($shape) {
    // 对照：具名直接调用（已实测等值，ref 装填生效）
    case 'ctrl_named':
        $v = [1];
        t007dyn_ctrl($v);
        echo $out . "count=" . count($v) . " last=" . $v[1] . "\n";
        break;

    // 对照：内建 array_walk（runtime 侧 make_ref，template:25596）
    case 'ctrl_walk':
        $w = ["a" => 1];
        array_walk($w, static function (mixed &$val, string $key): void {
            $val = $val * 10;
        });
        echo $out . "val=" . $w["a"] . "\n";
        break;

    // ① 变量函数名（字符串名走 registry）
    case 'vfn':
        $f = 't007dyn_ctrl';
        $v = [1];
        $f($v);
        echo $out . "count=" . count($v) . " last=" . $v[1] . "\n";
        break;

    // ② call_user_func + 闭包
    case 'cuf':
        $v = [1];
        call_user_func($t007dyn_cl, $v);
        echo $out . "count=" . count($v) . " last=" . $v[1] . "\n";
        break;

    // ③ 数组下标取闭包后调用
    case 'arrcb':
        $pair = [$t007dyn_cl];
        $v = [1];
        $pair[0]($v);
        echo $out . "count=" . count($v) . " last=" . $v[1] . "\n";
        break;

    // ④ [$obj,'method'] callable 变量
    case 'this_cb':
        $d = new T007Dyn();
        $v = [1];
        $d->runViaProperty($v);
        echo $out . "count=" . count($v) . " last=" . $v[1] . "\n";
        break;

    default:
        echo $out . "unknown\n";
}
