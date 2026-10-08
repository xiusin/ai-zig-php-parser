<?php
/**
 * AOT-REF-004 §7 永久取证探针（勿删）：uasort / uksort / array_map / array_filter 的引用形参**实测**面
 *
 * 为什么另起一枚探针：§7 表只对 7 枚派发器做过实测，`php_uasort`／`php_uksort` 仅有
 *   「函数体无 make_ref」的 grep 结论（§6.1），崩溃面（形 ⑫）仅在 `usort` 一枚上实测过；
 *   `array_map`／`array_filter` 也只测了**只读**形（⑩⑪），「数组引用形参 + 写入」这条
 *   崩溃组合在这两枚派发器上从未量过 ⇒ H 方案（callee 回落改值装 cell）的覆盖面目前是**推断**。
 *
 * 本探针把同一三态判据（① 等值 / ② 静默错值 / ③ rc=139 段错误）扩到未量的派发器，
 *   并加一枚 ctrl_usort 作逐字节对照锚（证明比较器本身在 AOT 可用，排除「内建未实现」混淆）。
 *
 * 选形方式 = $argv[1]（一次编译、N 次运行；崩溃形会杀进程，逐形编译不可行）。共 21 形。
 * 复测：见 docs/known-issues/AOT-REF-004-dynamic-call-byref-arg-not-made.md §5 / §7.2
 *
 * ⚠ 判据（本轮实测得出，必须遵守）：三枚派发器都走 quickSort（`runtime_lib_template.zig`
 *   :22521/:22545/:22566）⇒ **不稳定**，恒返回 0 的比较器同样会打乱顺序。因此「引用形参形」
 *   的输出等于 PHP 真值时**不得**判等值，必须与同输入的 `*_zero3` 控制形比对：
 *   两者相同 ⇒ 比较器在 AOT 侧已退化为恒 0 ⇒ 顺序是分区假象 ⇒ 判**静默错值**。
 */

$shape = $argv[1] ?? 'ctrl_usort';

switch ($shape) {
    // ① 对照锚：usort 按值比较器（无引用形参声明）⇒ 预期与 PHP 逐字节等值
    case 'ctrl_usort':
        $a = [[2], [1]];
        usort($a, function (array $x, array $y): int {
            return $x[0] <=> $y[0];
        });
        echo "SHAPE=ctrl_usort a=" . json_encode($a) . "\n";
        break;

    // ② usort 只读引用形参：声明 array &$x/&$y 但不写 ⇒ 区分「读到 null 使比较失效」
    case 'usort_read':
        $a = [[2], [1]];
        usort($a, function (array &$x, array &$y): int {
            return $x[0] <=> $y[0];
        });
        echo "SHAPE=usort_read a=" . json_encode($a) . "\n";
        break;

    // ③ uasort 只读引用形参：值引用 + 保留键序
    case 'uasort_read':
        $a = ['p' => [2], 'q' => [1]];
        uasort($a, function (array &$x, array &$y): int {
            return $x[0] <=> $y[0];
        });
        echo "SHAPE=uasort_read a=" . json_encode($a) . "\n";
        break;

    // ④ uasort 写回引用形参：崩溃候选（§7 形 ⑫ 的 uasort 对应形）
    case 'uasort_write':
        $a = ['p' => [2], 'q' => [1]];
        uasort($a, function (array &$x, array &$y): int {
            $x[] = 9;
            return $x[0] <=> $y[0];
        });
        echo "SHAPE=uasort_write a=" . json_encode($a) . "\n";
        break;

    // ⑤ uksort 引用形参（键为标量，不可 append）：只读 ⇒ 静默错值候选
    case 'uksort_read':
        $a = ['b' => 1, 'a' => 2];
        uksort($a, function (mixed &$k1, mixed &$k2): int {
            return strcmp((string) $k1, (string) $k2);
        });
        echo "SHAPE=uksort_read a=" . json_encode($a) . "\n";
        break;

    // ⑥ array_map：数组引用形参 + 写入 ⇒ 崩溃候选（§7 形 ⑩ 只测了标量只读）
    case 'map_write':
        $a = [[1], [2]];
        $r = array_map(function (array &$v): array {
            $v[] = 9;
            return $v;
        }, $a);
        echo "SHAPE=map_write r=" . json_encode($r) . " a=" . json_encode($a) . "\n";
        break;

    // ⑦ array_filter：数组引用形参 + 写入 ⇒ 崩溃候选（§7 形 ⑪ 只测了标量只读）
    case 'filter_write':
        $a = [[1], [2]];
        $r = array_filter($a, function (array &$v): bool {
            $v[] = 9;
            return $v[0] > 1;
        });
        echo "SHAPE=filter_write r=" . json_encode($r) . "\n";
        break;

    // ⑧~⑩ 三枚「引用形参 + 3 元素」判别形：输入序刻意不等于真值序
    //     ⇒ 与同输入的 zero 控制形（⑪~⑬）对比，可区分「AOT 比较成功」与
    //        「比较退化为恒 0、顺序只是 quickSort 不稳定分区留下的假象」。
    case 'usort_read3':
        $a = [[3], [1], [2]];
        usort($a, function (array &$x, array &$y): int {
            return $x[0] <=> $y[0];
        });
        echo "SHAPE=usort_read3 a=" . json_encode($a) . "\n";
        break;

    case 'uasort_read3':
        $a = ['p' => [3], 'q' => [1], 'r' => [2]];
        uasort($a, function (array &$x, array &$y): int {
            return $x[0] <=> $y[0];
        });
        echo "SHAPE=uasort_read3 a=" . json_encode($a) . "\n";
        break;

    case 'uksort_read3':
        $a = ['r' => 0, 'p' => 1, 'q' => 2];
        uksort($a, function (mixed &$k1, mixed &$k2): int {
            return strcmp((string) $k1, (string) $k2);
        });
        echo "SHAPE=uksort_read3 a=" . json_encode($a) . "\n";
        break;

    // ⑪~⑬ 同输入、按值、恒返回 0 的控制形（PHP 侧稳定排序 ⇒ 真值 = 输入序）
    case 'usort_zero3':
        $a = [[3], [1], [2]];
        usort($a, function (array $x, array $y): int {
            return 0;
        });
        echo "SHAPE=usort_zero3 a=" . json_encode($a) . "\n";
        break;

    case 'uasort_zero3':
        $a = ['p' => [3], 'q' => [1], 'r' => [2]];
        uasort($a, function (array $x, array $y): int {
            return 0;
        });
        echo "SHAPE=uasort_zero3 a=" . json_encode($a) . "\n";
        break;

    case 'uksort_zero3':
        $a = ['r' => 0, 'p' => 1, 'q' => 2];
        uksort($a, function (mixed $k1, mixed $k2): int {
            return 0;
        });
        echo "SHAPE=uksort_zero3 a=" . json_encode($a) . "\n";
        break;

    // ⑭⑮ 两枚 2 元素 zero 控制：与 uasort_read / uksort_read 同输入
    //     ⇒ 这两枚引用形参形在 AOT 下输出等于真值，须据此判是「真排序」还是「恒 0 分区假象」
    case 'uasort_zero':
        $a = ['p' => [2], 'q' => [1]];
        uasort($a, function (array $x, array $y): int {
            return 0;
        });
        echo "SHAPE=uasort_zero a=" . json_encode($a) . "\n";
        break;

    case 'uksort_zero':
        $a = ['b' => 1, 'a' => 2];
        uksort($a, function (mixed $k1, mixed $k2): int {
            return 0;
        });
        echo "SHAPE=uksort_zero a=" . json_encode($a) . "\n";
        break;

    // ⑯~㉑ 参数级取证形：比较器**恒返回 0**（两侧排序均退化为假象 ⇒ 顺序不再参与判据），
    //     唯一变量 = callee 实际收到什么。reflog 声明引用形参、byvalog 按值声明作对照。
    //     判据：byvalog 的 CB 行含真值 ⇒ 内建确有传参；reflog 的 CB 行含 null ⇒ &null_val 回落实证。
    case 'usort_reflog':
        $a = [[3], [1], [2]];
        usort($a, function (array &$x, array &$y): int {
            echo "CB=" . json_encode([$x, $y]) . "\n";
            return 0;
        });
        echo "SHAPE=usort_reflog done\n";
        break;

    case 'usort_byvalog':
        $a = [[3], [1], [2]];
        usort($a, function (array $x, array $y): int {
            echo "CB=" . json_encode([$x, $y]) . "\n";
            return 0;
        });
        echo "SHAPE=usort_byvalog done\n";
        break;

    case 'uasort_reflog':
        $a = ['p' => [3], 'q' => [1], 'r' => [2]];
        uasort($a, function (array &$x, array &$y): int {
            echo "CB=" . json_encode([$x, $y]) . "\n";
            return 0;
        });
        echo "SHAPE=uasort_reflog done\n";
        break;

    case 'uasort_byvalog':
        $a = ['p' => [3], 'q' => [1], 'r' => [2]];
        uasort($a, function (array $x, array $y): int {
            echo "CB=" . json_encode([$x, $y]) . "\n";
            return 0;
        });
        echo "SHAPE=uasort_byvalog done\n";
        break;

    case 'uksort_reflog':
        $a = ['r' => 0, 'p' => 1, 'q' => 2];
        uksort($a, function (mixed &$k1, mixed &$k2): int {
            echo "CB=" . json_encode([$k1, $k2]) . "\n";
            return 0;
        });
        echo "SHAPE=uksort_reflog done\n";
        break;

    case 'uksort_byvalog':
        $a = ['r' => 0, 'p' => 1, 'q' => 2];
        uksort($a, function (mixed $k1, mixed $k2): int {
            echo "CB=" . json_encode([$k1, $k2]) . "\n";
            return 0;
        });
        echo "SHAPE=uksort_byvalog done\n";
        break;

    default:
        echo "SHAPE=unknown " . $shape . "\n";
        break;
}
