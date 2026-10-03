<?php
// AOT-CODEGEN-002 复现原文（循环体内两个顺序兄弟 if，无 break）
$x = "a";
for ($i = 0; $i < 2; $i++) {
    if ($i == 0) {
        $x = "b";
    }
    if ($i == 1) {
        $x = "c";
    }
}
echo "K x=" . $x . "\n";
