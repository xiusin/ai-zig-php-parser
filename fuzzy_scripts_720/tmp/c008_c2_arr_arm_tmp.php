<?php
// 永久探针 C008-C2（控制臂，绿）：无 else 链，但臂体以数组追加结尾（非 echo）⇒ 链后 return 正常。
// 语料 f032《ValidationHandler::handle》即此形，故语料 68 枚全绿不等于本形无缺陷（共因之二未满足）。
function fA(array $req): array {
    if (empty($req['d'])) {
        $req['e'][] = 'A';
    } elseif (!isset($req['d'])) {
        $req['e'][] = 'B';
    }
    return $req;
}
echo "A=" . json_encode(fA([])) . "\n";
echo "END\n";
