<?php
// 永久探针 C008-P4（红形待定）：同一共因出现在「循环体内」——foreach 里无 else 的 if/elseif 链，
// 臂尾为 echo，链后仍有循环体语句。用于判定本形与 CODEGEN-005/006（循环内 elseif 臂丢失）是否同一承重环。
$k = $argv[1];
foreach (['x', 'y'] as $i) {
    if ($k === 'a') {
        echo "L-1 $i\n";
    } elseif ($k === 'b') {
        echo "L-2 $i\n";
    }
    echo "L-after $i\n";
}
echo "END\n";
