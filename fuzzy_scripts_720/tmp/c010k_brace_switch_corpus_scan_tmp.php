<?php
// 一次性语料扫描器（工单 AOT-CODEGEN-010 §7-15c 花括号 switch 残面取证，2026-10-09，任务 #126）
// 目标：用 PHP 官方分词器穷举**花括号 switch** 的语料暴露面，并逐枚判读
//       「首个 case/default/} 之前是否出现语句 token」⇒ 这是 R-3 批花括号支宽容面（OVER_ACCEPT）
//       在冻结基线里的真实命中面。
// 判据 3/4：扫描器 0 命中 ≠ 语料 0 命中；命中面必须拆「语料内」与「机制可达」两栏。
// 口径参照：c010j_alt_corpus_scan_tmp.php（同一套跳过空白/注释的后继 token 查法）。
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

$roots = array_slice($argv, 1);
if ($roots === []) $roots = ['fuzzy_scripts_720/pass', 'fuzzy_scripts_720/fail_runtime', 'fuzzy_scripts_720/fail_compile', 'fuzzy_scripts', 'fuzzy_scripts_715'];

printf("%-38s %6s %6s %6s %8s %8s\n", 'root', 'files', 'switch', 'brace', 'alt', 'stmthead');
$grand = ['sw' => 0, 'brace' => 0, 'alt' => 0, 'stmthead' => 0];

foreach ($roots as $root) {
    if (!is_dir($root)) { printf("%-38s  (absent)\n", $root); continue; }
    $files = [];
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
    foreach ($it as $f) {
        if ($f->isFile() && strtolower($f->getExtension()) === 'php') $files[] = $f->getPathname();
    }
    sort($files);
    $nSw = $nBrace = $nAlt = $nStmtHead = 0;
    $hits = [];
    foreach ($files as $path) {
        $toks = token_get_all(file_get_contents($path));
        $n = count($toks);
        for ($i = 0; $i < $n; $i++) {
            $t = $toks[$i];
            if (!is_array($t) || $t[0] !== T_SWITCH) continue;
            $nSw++;
            // 跳过括号条件：找到与 '(' 配对的 ')' 之后的第一个有效 token
            $j = nextIdx($toks, $n, $i);
            if ($j === null || $toks[$j] !== '(') { $hits[] = "  NO_PAREN $path:{$t[2]}"; continue; }
            $depth = 0; $close = null;
            for ($p = $j; $p < $n; $p++) {
                $u = $toks[$p];
                if (is_array($u)) continue;
                if ($u === '(') $depth++;
                elseif ($u === ')') { $depth--; if ($depth === 0) { $close = $p; break; } }
            }
            if ($close === null) { $hits[] = "  UNCLOSED_PAREN $path:{$t[2]}"; continue; }
            $k = nextIdx($toks, $n, $close);
            if ($k === null) { $hits[] = "  NO_HEAD $path:{$t[2]}"; continue; }
            $head = is_array($toks[$k]) ? $toks[$k][1] : $toks[$k];
            if ($head === ':') {
                $nAlt++;
                $hits[] = "  ALT_HEAD $path:{$t[2]}";
                continue;
            }
            if ($head !== '{') { $hits[] = "  OTHER_HEAD($head) $path:{$t[2]}"; continue; }
            $nBrace++;
            // 花括号体：首个 case/default/} 之前是否出现任何语句 token
            $m = nextIdx($toks, $n, $k);
            if ($m === null) { $hits[] = "  TRUNC $path:{$t[2]}"; continue; }
            $first = $toks[$m];
            $ftext = is_array($first) ? token_name($first[0]) : $first;
            $isCase = is_array($first) && ($first[0] === T_CASE || $first[0] === T_DEFAULT);
            if (!$isCase && $ftext !== '}') {
                $nStmtHead++;
                $hits[] = sprintf("  STMT_BEFORE_CASE %s:%d first=%s", $path, $t[2], $ftext);
            }
        }
    }
    printf("%-38s %6d %6d %6d %8d %8d\n", $root, count($files), $nSw, $nBrace, $nAlt, $nStmtHead);
    foreach ($hits as $h) echo "$h\n";
    $grand['sw'] += $nSw; $grand['brace'] += $nBrace; $grand['alt'] += $nAlt; $grand['stmthead'] += $nStmtHead;
}
printf("GRAND switch=%d brace=%d alt=%d stmt_before_first_case=%d\n", $grand['sw'], $grand['brace'], $grand['alt'], $grand['stmthead']);
