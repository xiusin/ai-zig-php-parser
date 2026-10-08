<?php
// 永久探针 C008-P2（红形）：函数作用域，无 else 链 + echo 结尾臂 + 链后 return
// 实测：链后 `return "R\n"` 零发射 ⇒ 函数落出末尾返回隐式 null，主调拿到空串，rc=0。
// 与 P1 同机制，证明本形不限于 __main__，函数/方法同理（语料 f032 即「方法内无 else 链 + 链后 return」，
// 但其臂体以数组追加结尾故不触发，见 C2）。
function fB(string $k): string {
    if ($k === 'a') {
        echo "1\n";
    } elseif ($k === "b") {
        echo "2\n";
    }
    return "R\n";
}
echo "B=" . fB($argv[1]);
echo "END\n";
