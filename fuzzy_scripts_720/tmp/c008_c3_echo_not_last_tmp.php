<?php
// 永久探针 C008-C3（控制臂，绿）：臂内 echo 存在但「不是臂的最后一条语句」⇒ 链后语句正常。
// 与 P3 唯一差异是臂尾多了一条数组追加 ⇒ 判据精确到「臂尾最后一条语句是否为 echo」。
function fE(array $req): array {
    if (empty($req['d'])) {
        echo "arm1\n";
        $req['e'][] = 'A';
    } elseif (!isset($req['d'])) {
        $req['e'][] = 'B';
    }
    $req['tail'] = 1;
    return $req;
}
echo "E=" . json_encode(fE([])) . "\n";
echo "END\n";
