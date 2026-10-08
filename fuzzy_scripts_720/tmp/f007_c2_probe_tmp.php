<?php
// f007 缺陷2：caesar 仅大写臂生效？
function caesar(string $text, int $shift): string {
    $result = '';
    $len = strlen($text);
    $shift = $shift % 26;
    for ($i = 0; $i < $len; $i++) {
        $c = ord($text[$i]);
        if ($c >= 65 && $c <= 90) {
            $result .= chr((($c - 65 + $shift) % 26 + 26) % 26 + 65);
        } elseif ($c >= 97 && $c <= 122) {
            $result .= chr((($c - 97 + $shift) % 26 + 26) % 26 + 97);
        } else {
            $result .= $text[$i];
        }
    }
    return $result;
}
echo caesar("Hello World", 3) . "\n";
echo "expected: Khoor Zruog\n";
echo "=== done ===\n";
