<?php
// 永久探针 C008-C4（控制臂，绿）：臂尾最后一条语句是「无返回语义的用户函数调用」（非 echo）⇒ 链后语句正常。
// 排除「任何被忽略结果语句做臂尾」这一更宽假设，把共因锁死在 echo 语句本身。
function noop(): void {}
function fG(array $req): array {
    if (empty($req['d'])) {
        noop();
    } elseif (!isset($req['d'])) {
        $req['e'][] = 'B';
    }
    $req['tail'] = 1;
    return $req;
}
echo "G=" . json_encode(fG([])) . "\n";
echo "END\n";
