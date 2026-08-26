<?php
// AOT-PHI-001 复现: 循环中多个 if 修改同一变量
$result = "";
for ($i = 0; $i < 5; $i++) {
    if ($i % 2 == 0) {
        $result = $result . "even";
    } else {
        $result = $result . "odd";
    }
    if ($i < 4) {
        $result = $result . ",";
    }
}
echo $result . "\n"; // 期望 even,odd,even,odd,even
?>