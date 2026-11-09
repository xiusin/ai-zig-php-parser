<?php
// 最小化 a 段：for 循环内 Zig\Select::select + null 判断 + break
function feeder($ch) {
    $i = 0;
    while (true) {
        try {
            $ch->send($i);
            $i++;
        } catch (Throwable $e) {
            return;
        }
    }
}
$ch1 = new Channel(1);
$ch2 = new Channel(1);
go('feeder', $ch1);
go('feeder', $ch2);
$cnt = [0, 0];
for ($i = 0; $i < 2000; $i++) {
    $r = Zig\Select::select([[$ch1, 0], [$ch2, 0]], null);
    if ($r === null) {
        break;
    }
    $cnt[$r[0]]++;
}
$ch1->close();
$ch2->close();
go_wait_all();
echo "dist={$cnt[0]},{$cnt[1]}\n";
