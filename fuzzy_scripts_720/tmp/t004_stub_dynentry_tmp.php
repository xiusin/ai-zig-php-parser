<?php
// AOT-REF-004 §7.4 补充探针（永久，勿删）：动态入口 → **含引用形参的类方法**（方法表桩路径）的触发面实测。
// 背景：§1 的形 ①–⑤ 测的是「动态入口 → 闭包 / 具名全局函数」；绿语料实测的动态入口（f042 的 $fn($item)）
//       目标均无引用形参 ⇒ 唯一未量面 = 「callee 帧内含 `&null_val` 回落句」且「经动态入口进入」。
// 用法：aot_compile_t004_stub_dynentry_tmp <shape>
//   ctrl_static   具名直调（对照：应等值，caller 侧 make_ref 已装填）
//   cuf_string    call_user_func('RefStub::take', $a)          字符串名派发
//   cuf_array     call_user_func([new RefStub, 'takeP'], $a)   数组 callable 派发
//   varfunc_str   $f = 'RefStub::take'; $f($a);                变量函数（字符串名）
//   inst_dyn      $o = new RefStub; $m = 'takeP'; $o->$m($a);  动态方法名（实例侧）
// 每形输出同句式：SHAPE=x before=[..] ret=N after=[..] ⇒ after 变长 = 写回成功；after==before 且 ret==2 = 按值/null。

class RefStub
{
    public static function take(array &$a): int
    {
        $a[] = 99;
        return count($a);
    }

    public function takeP(array &$a): int
    {
        $a[] = 7;
        return count($a);
    }
}

function report(string $tag, array $before, array $after, int $ret): void
{
    echo $tag . ' before=' . json_encode($before)
        . ' ret=' . $ret
        . ' after=' . json_encode($after) . "\n";
}

$shape = $argv[1] ?? 'ctrl_static';
$a = [1, 2];
$before = $a;
$ret = 0;

switch ($shape) {
    case 'ctrl_static': {
        $ret = RefStub::take($a);
        break;
    }
    case 'cuf_string': {
        $ret = call_user_func('RefStub::take', $a);
        break;
    }
    case 'cuf_array': {
        $ret = call_user_func([new RefStub, 'takeP'], $a);
        break;
    }
    case 'varfunc_str': {
        $f = 'RefStub::take';
        $ret = $f($a);
        break;
    }
    case 'inst_dyn': {
        $o = new RefStub();
        $m = 'takeP';
        $ret = $o->$m($a);
        break;
    }
    default: {
        echo "SHAPE=unknown usage: ctrl_static|cuf_string|cuf_array|varfunc_str|inst_dyn\n";
        exit(0);
    }
}

report('SHAPE=' . $shape, $before, $a, $ret);
