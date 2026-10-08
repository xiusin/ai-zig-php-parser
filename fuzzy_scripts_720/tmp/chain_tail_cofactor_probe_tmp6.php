<?php
// 永久探针：无 else 的 if/elseif 链「链后语句丢失」共因二分（v6）
// 已实测最小复现（m3/m6）：链无 else 臂时，命中任一臂后链后语句零发射（rc=0 静默截断，
//   函数链后 return 丢失 ⇒ 隐式 null）。
// 但语料 f032 同样「无 else 的 if/elseif 链 + 链后 return」却全绿 ⇒ 必存在共因。
// 本探针单次编译并列五形，分离：作用域（顶层/函数/方法）、臂体语句类型（echo/数组追加）、
// 链后语句类型（echo/return）、是否在循环体内。

class Twin {
    public function arrArms(array $req): array {
        if (empty($req['data'])) {
            $req['errors'][] = 'A';
        } elseif (!isset($req['data'])) {
            $req['errors'][] = 'B';
        }
        return $req;
    }
}

function echoArmsRetOnly(string $k): string {
    if ($k === 'a') {
        echo "1\n";
    } elseif ($k === 'b') {
        echo "2\n";
    }
    return "R\n";
}

function arrArmsRetOnly(array $req): array {
    if (empty($req['data'])) {
        $req['errors'][] = 'A';
    } elseif (!isset($req['data'])) {
        $req['errors'][] = 'B';
    }
    return $req;
}

function loopTail(string $k): void {
    foreach ([1, 2] as $i) {
        if ($k === 'a') {
            echo "L-1 $i\n";
        } elseif ($k === 'b') {
            echo "L-2 $i\n";
        }
        echo "L-after $i\n";
    }
}

$k = isset($argv[1]) ? $argv[1] : 'x';
$v = isset($argv[2]) ? $argv[2] : 'z';
echo "K=$k\n";

if ($k === 'method_arr') {
    $t = new Twin();
    $r = $v === 'empty' ? [] : ['data' => 'D'];
    echo "OUT=" . json_encode($t->arrArms($r)) . "\n";
} elseif ($k === 'fn_echo_ret') {
    echo "RET=" . echoArmsRetOnly($v === 'a' ? 'a' : 'b') . "\n";
} elseif ($k === 'fn_arr_ret') {
    echo "RET=" . json_encode(arrArmsRetOnly($v === 'empty' ? [] : ['x' => 1])) . "\n";
} elseif ($k === 'loop_tail') {
    loopTail($v === 'a' ? 'a' : 'b');
}
echo "END\n";
