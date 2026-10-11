<?php
// 一次性语料扫描器 v2（任务 #126 第二维，2026-10-09）：穷举 switch 的两枚**新面孔**语料暴露面。
//   维度 A = `default` 臂**非末臂**（其后仍有 case 臂）⇒ 对应门 K 的 k_default_first
//            （DIFF_PHP_OK_AOT_DIFF；机制＝ir_generator.zig:3210-3214 按 case_blocks 下标链入、
//             default 恒当末臂，:3238-3240 default 体尾恒跳 merge）。
//   维度 B = **switch 体内** `case expr;` / `default;` 分号终结符（PHP 8 Deprecated 但 rc=0）
//            ⇒ 对应门 K 的五枚 AOT_ONLY_RED_COMPILE（机制＝parser.zig:3571/:3583 硬 eat(.colon)）。
//
// ★ v1→v2 修 scanner（v1 读数全废，禁止引用）：v1 把**全树**的 T_CASE/T_DEFAULT 都当 switch 臂，
//   且只以 `:`/`;` 为终止边界 ⇒ 两枚假阳性 ——
//     ① enum 体 `case Hearts = 'hearts';`（带值）与 `case Hearts;`（无值）；
//     ② match 臂 `default => "…"`（`=>` 不在 v1 的终止集内 ⇒ 越过臂尾直到语句 `;`）。
//   v1 实测 semi_terminator=87（pass/20 + fail_runtime/46 + fail_compile/1 + 旧语料 3 + 715/17）
//   全部为这两族，**switch 分号臂 0 枚** ⇒ v2 改为
//     (a) 先扫出 **switch 体** 与 **enum 体** 的 token 下标区间，只对落在 switch 区间内的臂分类；
//     (b) 终止集扩为 `:` / `;` / `=` / `=>` / `,`，其中仅 `;` 计 SEMI_TERM，其余计其它面孔；
//     (c) 括号/方括号深度非 0 时的 `:`/`;` 跳过（三元、数组下标、match 臂内的 `:`）。
//   控制臂（自检必过，缺一即扫描器坏）：f048:15（match default）不得记 SEMI、
//     f154:71（enum 带值 case）不得记 SEMI、合成形 `switch(1){case 1;}` 必须记 SEMI。
//
// 判据 3/4：命中必须分词器口径（排除字符串/注释），「语料内」与「机制可达」分栏。
// 保守边界（已知低估面）：体扫描遇到**嵌套 T_SWITCH** 即停 ⇒ 外层臂序列不完整；
//   嵌套 switch 自身会作为独立 switch 再计一次，故维度 A 的「非末臂」判定对嵌套内层仍准确。
$skip = [T_WHITESPACE => 1, T_COMMENT => 1, T_DOC_COMMENT => 1];

function nextIdx(array $toks, int $n, int $i): ?int
{
    for ($j = $i + 1; $j < $n; $j++) {
        $t = $toks[$j];
        if (is_array($t) && isset($GLOBALS['skip'][$t[0]])) continue;
        return $j;
    }
    return null;
}

// 返回 [startIdx, endIdx]：该 token 之后第一个深度 0 的 '{' 到其配对 '}'
function braceRange(array $toks, int $n, int $from): ?array
{
    $j = nextIdx($toks, $n, $from);
    if ($j === null || !(is_string($toks[$j]) && $toks[$j] === '{')) return null;
    $d = 0;
    for ($p = $j; $p < $n; $p++) {
        $u = $toks[$p];
        if (is_string($u)) {
            if ($u === '{') $d++;
            elseif ($u === '}') { $d--; if ($d === 0) return [$j, $p]; }
        }
    }
    return [$j, $n - 1];
}

function switchRanges(array $toks, int $n): array
{
    $out = [];
    for ($i = 0; $i < $n; $i++) {
        $t = $toks[$i];
        if (!is_array($t) || $t[0] !== T_SWITCH) continue;
        $j = nextIdx($toks, $n, $i);
        if ($j === null) continue;
        if (is_string($toks[$j]) && $toks[$j] === '(') {
            $depth = 0; $close = null;
            for ($p = $j; $p < $n; $p++) {
                $u = $toks[$p];
                if (is_array($u)) continue;
                if ($u === '(') $depth++;
                elseif ($u === ')') { $depth--; if ($depth === 0) { $close = $p; break; } }
            }
            if ($close === null) continue;
            $j = nextIdx($toks, $n, $close);
            if ($j === null) continue;
        }
        $head = $toks[$j];
        if (is_string($head) && $head === '{') {
            $r = braceRange($toks, $n, $j - 1);
            if ($r !== null) { $out[] = [$r[0], $r[1], 'brace', $t[2]]; continue; }
        }
        if (is_string($head) && $head === ':') {
            $k = $j;
            for (;$k < $n; $k++) {
                $u = $toks[$k];
                if (is_array($u) && $u[0] === T_ENDSWITCH) break;
            }
            $out[] = [$j, min($k, $n - 1), 'alt', $t[2]];
        }
    }
    return $out;
}

function enumRanges(array $toks, int $n): array
{
    $out = [];
    for ($i = 0; $i < $n; $i++) {
        $t = $toks[$i];
        if (!is_array($t) || $t[0] !== T_ENUM) continue;
        // 找到 enum 名之后的 '{'
        $j = nextIdx($toks, $n, $i);
        if ($j === null) continue;
        $k = $j;
        while ($k < $n) {
            $u = $toks[$k];
            if (is_string($u) && $u === '{') break;
            if (is_string($u) && ($u === ';' || $u === '(')) { $k = $n; break; }
            $k = nextIdx($toks, $n, $k) ?? $n;
        }
        if ($k >= $n) continue;
        $r = braceRange($toks, $n, $k - 1);
        if ($r !== null) $out[] = [$r[0], $r[1]];
    }
    return $out;
}

function inRanges(int $idx, array $ranges): bool
{
    foreach ($ranges as $r) {
        if ($idx > $r[0] && $idx < $r[1]) return true;
    }
    return false;
}

$roots = array_slice($argv, 1);
if ($roots === []) {
    $roots = ['fuzzy_scripts_720/pass', 'fuzzy_scripts_720/fail_runtime', 'fuzzy_scripts_720/fail_compile', 'fuzzy_scripts', 'fuzzy_scripts_715'];
}

printf("%-40s %5s %6s %6s %14s %10s %8s\n", 'root', 'files', 'switch', 'brace', 'nonlast_dflt', 'semi_arm', 'colon_arm');
$g = ['sw' => 0, 'br' => 0, 'd' => 0, 'semi' => 0, 'colon' => 0];

foreach ($roots as $root) {
    if (!is_dir($root)) { printf("%-40s  (absent)\n", $root); continue; }
    $files = [];
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
    foreach ($it as $f) {
        if ($f->isFile() && strtolower($f->getExtension()) === 'php') $files[] = $f->getPathname();
    }
    sort($files);
    $nSw = $nBrace = $nNonLast = $nSemi = $nColon = 0;
    $hits = [];
    foreach ($files as $path) {
        $toks = token_get_all(file_get_contents($path));
        $n = count($toks);
        $swRanges = switchRanges($toks, $n);
        $enRanges = enumRanges($toks, $n);

        // 维度 B：仅 switch 区间内的 T_CASE / T_DEFAULT 终结符
        for ($i = 0; $i < $n; $i++) {
            $t = $toks[$i];
            if (!is_array($t)) continue;
            if ($t[0] !== T_CASE && $t[0] !== T_DEFAULT) continue;
            if (!inRanges($i, $swRanges) || inRanges($i, $enRanges)) continue;   // enum / match / 其它上下文 ⇒ 排除
            $depth = 0; $term = null;
            for ($j = $i + 1; $j < $n; $j++) {
                $u = $toks[$j];
                if (is_array($u)) {
                    if (isset($skip[$u[0]])) continue;
                    if ($u[0] === T_CASE || $u[0] === T_DEFAULT) break;
                    if ($u[0] === T_CURLY_OPEN || $u[0] === T_DOLLAR_OPEN_CURLY_BRACES || $u[0] === T_STRING_VARNAME) break;
                    continue;
                }
                if ($u === '(' || $u === '[') { $depth++; continue; }
                if ($u === ')' || $u === ']') { $depth--; continue; }
                if ($depth !== 0) continue;
                if ($u === '{' || $u === '}') break;
                if ($u === ':' || $u === ';' || $u === '=>' || $u === ',' || $u === '=') { $term = $u; break; }
            }
            if ($term === ';') {
                $nSemi++;
                $hits[] = sprintf("  SEMI_ARM %s:%d %s", $path, $t[2], token_name($t[0]));
            } elseif ($term === ':' || $term === null) {
                $nColon++;
            } else {
                $hits[] = sprintf("  OTHER_TERM(%s) %s:%d %s", (string)$term, $path, $t[2], token_name($t[0]));
            }
        }

        // 维度 A + 头型统计
        foreach ($swRanges as $r) {
            $nSw++;
            if ($r[2] === 'brace') $nBrace++;
            $arms = [];
            $depth = 0;
            $want = $r[2] === 'brace' ? 1 : 0;   // 花括号区间：'{' 本身使 depth=1；替代语法区间无外层花括号
            for ($p = $r[0]; $p <= $r[1]; $p++) {
                $u = $toks[$p];
                if (is_array($u)) {
                    if ($u[0] === T_CURLY_OPEN || $u[0] === T_DOLLAR_OPEN_CURLY_BRACES) $depth++;
                    elseif ($depth === $want && $u[0] === T_CASE) $arms[] = 'C';
                    elseif ($depth === $want && $u[0] === T_DEFAULT) $arms[] = 'D';
                    continue;
                }
                if ($u === '{') { $depth++; continue; }
                if ($u === '}') { $depth--; continue; }
            }
            $posD = array_search('D', $arms, true);
            if ($posD !== false && in_array('C', array_slice($arms, $posD + 1), true)) {
                $nNonLast++;
                $hits[] = sprintf("  NONLAST_DEFAULT %s:%d arms=%s head=%s", $path, $r[3], implode('', $arms), $r[2]);
            }
        }
    }
    printf("%-40s %5d %6d %6d %13d %9d %10d\n", $root, count($files), $nSw, $nBrace, $nNonLast, $nSemi, $nColon);
    foreach ($hits as $h) echo "$h\n";
    $g['sw'] += $nSw; $g['br'] += $nBrace; $g['d'] += $nNonLast; $g['semi'] += $nSemi; $g['colon'] += $nColon;
}
printf("GRAND switch=%d brace=%d nonlast_default=%d semi_arm=%d colon_arm=%d\n", $g['sw'], $g['br'], $g['d'], $g['semi'], $g['colon']);
