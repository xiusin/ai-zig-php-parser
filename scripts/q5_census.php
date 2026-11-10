<?php
/**
 * Q5：AOT 内建函数覆盖普查
 * 口径：语料（fuzzy_scripts_720）全部「自由函数调用名」（token 级，排除 -> :: 与语言构造）
 *   A = 已覆盖（编译期 builtin_map ∪ 运行期 registry）
 *   B = 未覆盖但确为 PHP 内建（在 builtin_param_table_generated.zig 反射表里）
 *   C = 未覆盖且不在反射表（误识别/动态名/用户函数）
 * 输出：分布计数 + B 类按语料频次降序清单（仍不覆盖清单）。
 */

$root = dirname(__DIR__); // 自动定位项目根（scripts/ 上一级）
$corpus = $root . '/fuzzy_scripts_720';

// 已覆盖集合：builtin_map 键 + registry 键
$covered = [];
foreach (file($root . '/src/aot/native_linker.zig') as $line) {
    if (preg_match('/\.\{ "([a-zA-Z0-9_]+)",\s*(?:bi\()?\.\{ \.runtime_name/', $line, $m)) {
        $covered[strtolower($m[1])] = true;
    }
}
foreach (file($root . '/src/aot/runtime_lib_template.zig') as $line) {
    if (preg_match('/\.\{ "([a-zA-Z0-9_]+)", wrapBuiltin_/', $line, $m)) {
        $covered[strtolower($m[1])] = true;
    }
}

// 反射表（PHP 内建全集）：生成表里的函数名键
$builtin = [];
$gen = file_get_contents($root . '/src/aot/builtin_param_table_generated.zig');
// 形态：.{ "name", ... } 在 StaticStringMap 里
if (preg_match_all('/\.\{ "([a-zA-Z0-9_]+)", \./', $gen, $mm)) {
    foreach ($mm[1] as $n) $builtin[strtolower($n)] = true;
}

// 语言构造/伪函数白名单（不算函数调用）
$constructs = array_flip(['echo','print','isset','unset','empty','include','include_once','require','require_once','list','array','fn','function','if','elseif','else','while','do','for','foreach','switch','case','default','try','catch','finally','throw','new','clone','return','yield','match','declare','goto','break','continue','global','static','class','interface','trait','enum','extends','implements','use','namespace','const','instanceof','or','and','xor','not','die','exit','eval','__halt_compiler']);

// 语料扫描
$calls = []; // name => count
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($corpus, FilesystemIterator::SKIP_DOTS));
foreach ($it as $f) {
    if ($f->getExtension() !== 'php') continue;
    $code = file_get_contents($f->getPathname());
    // @：语料内的怪字面量（如 \777 八进制溢出）在 token 化时由 PHP 发 Warning——属语料固有噪音，非普查信号
    $tokens = @token_get_all($code);
    $n = count($tokens);
    for ($i = 0; $i < $n; $i++) {
        $t = $tokens[$i];
        if (!is_array($t) || $t[0] !== T_STRING) continue;
        // 后面紧跟（
        $j = $i + 1;
        while ($j < $n && is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) $j++;
        if ($j >= $n || $tokens[$j] !== '(') continue;
        // 前面不是 -> / :: / function（定义）/ new
        $k = $i - 1;
        while ($k >= 0 && is_array($tokens[$k]) && $tokens[$k][0] === T_WHITESPACE) $k--;
        if ($k >= 0 && is_array($tokens[$k]) && in_array($tokens[$k][0], [T_OBJECT_OPERATOR, T_NULLSAFE_OBJECT_OPERATOR, T_DOUBLE_COLON, T_FUNCTION, T_NEW], true)) continue;
        $name = strtolower($t[1]);
        if (isset($constructs[$name])) continue;
        $calls[$name] = ($calls[$name] ?? 0) + 1;
    }
}
arsort($calls);

$a = [];
$b = [];
$c = [];
foreach ($calls as $name => $cnt) {
    if (isset($covered[$name])) $a[$name] = $cnt;
    elseif (isset($builtin[$name])) $b[$name] = $cnt;
    else $c[$name] = $cnt;
}

printf("== 覆盖普查（Q5，语料 fuzzy_scripts_720）==\n");
printf("语料自由函数调用名总数（去重）: %d（调用点 %d）\n", count($calls), array_sum($calls));
printf("A 已覆盖: %d 名（%d 点）\n", count($a), array_sum($a));
printf("B 内建未覆盖: %d 名（%d 点）\n", count($b), array_sum($b));
printf("C 非内建未覆盖: %d 名（%d 点）\n", count($c), array_sum($c));

echo "\n== B 类仍不覆盖清单（按频次降序，全量）==\n";
foreach ($b as $name => $cnt) printf("%5d  %s\n", $cnt, $name);

echo "\n== C 类（非内建/误识别，前 20）==\n";
$i = 0;
foreach ($c as $name => $cnt) {
    printf("%5d  %s\n", $cnt, $name);
    if (++$i >= 20) break;
}
