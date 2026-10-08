<?php
echo "=== single-stmt-if probes ===\n";

$op = 'ret';
$args = ['a', 'b'];

$used = [];
if ($op === 'ret') foreach ($args as $a) $used[$a] = true;
echo "P1 if-no-brace + foreach-no-brace: count=" . count($used) . " (expect 2)\n";

$used2 = [];
if ($op === 'ret') { foreach ($args as $a) $used2[$a] = true; }
echo "P2 if-brace + foreach-no-brace: count=" . count($used2) . " (expect 2)\n";

$used3 = [];
if ($op === 'ret') {
    foreach ($args as $a) { $used3[$a] = true; }
}
echo "P3 all braces: count=" . count($used3) . " (expect 2)\n";

$consts = ['t2' => 21];
$argList = ['t2', 'zz'];
$count = 0; $out = [];
foreach ($argList as $arg) {
    if (isset($consts[$arg])) { $out[] = (string)$consts[$arg]; $count++; }
    else $out[] = $arg;
}
echo "P4 two-stmt then + no-brace else: count=$count out=" . implode(',', $out) . " (expect 1 out=21,zz)\n";

$count5 = 0; $out5 = [];
foreach ($argList as $arg) {
    if (isset($consts[$arg])) { $out5[] = (string)$consts[$arg]; $count5++; }
}
echo "P5 two-stmt then no else: count=$count5 out=" . implode(',', $out5) . " (expect 1 out=21)\n";

$count6 = 0; $out6 = [];
foreach ($argList as $arg) {
    if (isset($consts[$arg])) { $count6++; $out6[] = (string)$consts[$arg]; }
    else $out6[] = $arg;
}
echo "P6 increment first: count=$count6 out=" . implode(',', $out6) . " (expect 1 out=21,zz)\n";

$n7 = 0;
if ($op === 'ret') $n7++;
echo "P7 if-no-brace ++ only: n7=$n7 (expect 1)\n";

$sum8 = 0;
foreach ($args as $a) if ($a === 'a') $sum8 = $sum8 + 10;
echo "P8 foreach body = if-no-brace: sum8=$sum8 (expect 10)\n";

echo "=== done ===\n";
