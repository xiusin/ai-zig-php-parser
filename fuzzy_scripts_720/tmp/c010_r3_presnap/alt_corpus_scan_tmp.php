<?php
// 一次性语料扫描器 v2（/tmp，不入仓库）：用 PHP 官方分词器统计替代语法的**语法位**暴露面。
// 修正：查找头部后继结构 token 时必须跳过 T_WHITESPACE/T_COMMENT/T_DOC_COMMENT（v1 未跳，导致 openers 恒 0）。
// 补充：T_ENDDECLARE（declare 族关闭标记）。
$closeIds = [
    T_ENDIF => 'endif', T_ENDWHILE => 'endwhile', T_ENDFOR => 'endfor',
    T_ENDFOREACH => 'endforeach', T_ENDSWITCH => 'endswitch',
];
if (defined('T_ENDDECLARE')) $closeIds[constant('T_ENDDECLARE')] = 'enddeclare';
$openIds = [
    T_IF => 'if', T_WHILE => 'while', T_FOR => 'for',
    T_FOREACH => 'foreach', T_SWITCH => 'switch', T_DECLARE => 'declare',
];
$skip = [T_WHITESPACE => 1, T_COMMENT => 1, T_DOC_COMMENT => 1];

$root = $argv[1] ?? 'fuzzy_scripts_720';
$files = [];
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
foreach ($it as $f) {
    if ($f->isFile() && strtolower($f->getExtension()) === 'php') $files[] = $f->getPathname();
}
sort($files);

$totClose = 0; $totOpen = 0; $totBrace = 0;
$closeHits = []; $openHits = [];
foreach ($files as $path) {
    $src = file_get_contents($path);
    $toks = token_get_all($src);
    $n = count($toks);
    for ($i = 0; $i < $n; $i++) {
        $t = $toks[$i];
        if (!is_array($t)) continue;
        $id = $t[0];
        if (isset($closeIds[$id])) {
            $totClose++;
            $closeHits[] = $path . ':' . $t[2] . ' ' . $closeIds[$id];
        }
        if (!isset($openIds[$id])) continue;
        $depth = 0; $kind = null;
        for ($j = $i + 1; $j < $n; $j++) {
            $u = $toks[$j];
            if (is_array($u)) {
                if (isset($skip[$u[0]])) continue;
                $text = $u[1];
            } else {
                $text = $u;
            }
            if ($text === '(') { $depth++; continue; }
            if ($text === ')') { $depth--; if ($depth < 0) $depth = 0; continue; }
            if ($depth === 0) {
                if ($text === ':') $kind = 'alt';
                elseif ($text === '{') $kind = 'brace';
                break;
            }
        }
        if ($kind === 'alt') {
            $totOpen++;
            $openHits[] = $path . ':' . $t[2] . ' ' . $openIds[$id] . '_ALT';
        } elseif ($kind === 'brace') {
            $totBrace++;
        }
    }
}

printf("root=%s php_files=%d\n", $root, count($files));
printf("close_marker_tokens_at_syntax_position=%d\n", $totClose);
foreach ($closeHits as $h) echo "  CLOSE $h\n";
printf("alt_syntax_headers=%d  brace_headers=%d\n", $totOpen, $totBrace);
foreach ($openHits as $h) echo "  OPEN  $h\n";
