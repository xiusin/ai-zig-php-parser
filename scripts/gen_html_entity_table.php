<?php
/**
 * Q4：HTML 实体表生成器（html_entity_decode/htmlentities 的数据源）
 *
 * 用法：php scripts/gen_html_entity_table.php > src/aot/html_entity_table_generated.zig
 * 复核：可重跑、可 diff；表内容完全由 PHP 8.5.8 的 get_html_translation_table() 反射导出，
 *       禁止手抄。
 *
 * 四张表对应 ENT_HTML401 / ENT_XHTML / ENT_XML1 / ENT_HTML5。
 * 键 = 含前导 & 的完整实体名（不含分号，分号匹配属解码器职责——PHP 默认严格分号匹配，
 * 实测 `&amp` 无分号不解码）。
 */

$tables = [
    'html401' => get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_HTML401, 'UTF-8'),
    'xhtml'   => get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_XHTML, 'UTF-8'),
    'xml1'    => get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_XML1, 'UTF-8'),
    'html5'   => get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_HTML5, 'UTF-8'),
];

// Zig 字符串字面量逐字节转义（控制字节/引号/反斜杠 ⇒ \xNN；与 gen_builtin_param_table 同规）
function zigStr(string $s): string {
    $out = '';
    for ($i = 0, $n = strlen($s); $i < $n; $i++) {
        $c = ord($s[$i]);
        if ($c >= 0x20 && $c <= 0x7E && $c !== 0x22 && $c !== 0x5C) {
            $out .= $s[$i];
        } else {
            $out .= sprintf('\\x%02x', $c);
        }
    }
    return '"' . $out . '"';
}

$now = date('Y-m-d');
echo <<<ZIG
//! HTML 实体表（生成物，禁止手改）
//!
//! 生成命令：php scripts/gen_html_entity_table.php > src/aot/html_entity_table_generated.zig
//! 数据源：PHP 8.5.8 get_html_translation_table(HTML_ENTITIES, flags, 'UTF-8')
//! 生成日期：{$now}（重跑以 diff 复核）

const std = @import("std");

/// 实体名（含前导 &、不含分号）→ UTF-8 替换字节串

ZIG;

foreach ($tables as $name => $table) {
    echo "pub const {$name} = std.StaticStringMap([]const u8).initComptime(.{\n";
    // 表方向：get_html_translation_table 返回「字符 ⇒ 实体」（编码向），解码需反转为
    // 「实体 ⇒ 字符」。一键多实体（如 '&' 可映 &amp;/&AMP;）时保留**先出现**的实体名
    // （PHP 表序即规范名序）。
    $decoded = [];
    foreach ($table as $char => $entity) {
        $key = substr($entity, 0, -1); // 剥分号
        if (!isset($decoded[$key])) $decoded[$key] = $char;
    }
    ksort($decoded, SORT_STRING | SORT_FLAG_CASE);
    foreach ($decoded as $key => $char) {
        echo '    .{ ', zigStr($key), ', ', zigStr($char), " },\n";
    }
    echo "});\n\n";
}

foreach ($tables as $name => $table) {
    echo "// {$name}: " . count($table) . " entries\n";
}
