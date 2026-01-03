<?php
echo "=== Channel 通道测试 ===\n\n";

// 测试1: 基本发送和接收
echo "【测试1】基本发送和接收\n";
$ch = new Channel(3);
echo "创建 Channel(3) 成功，容量: " . $ch->capacity() . "\n";

$ch->send(100);
$ch->send(200);
$ch->send(300);
echo "发送了 3 条数据，当前长度: " . $ch->len() . "\n";

$v1 = $ch->recv();
$v2 = $ch->recv();
$v3 = $ch->recv();
echo "接收: $v1, $v2, $v3\n";
echo "接收后长度: " . $ch->len() . "\n";

// 测试2: trySend 和 tryRecv
echo "\n【测试2】非阻塞发送和接收\n";
$ch2 = new Channel(2);
$r1 = $ch2->trySend(10);
$r2 = $ch2->trySend(20);
$r3 = $ch2->trySend(30);
echo "trySend(10): " . ($r1 ? "true" : "false") . "\n";
echo "trySend(20): " . ($r2 ? "true" : "false") . "\n";
echo "trySend(30): " . ($r3 ? "true" : "false") . " (缓冲区满，应该失败)\n";

$v = $ch2->tryRecv();
echo "tryRecv: $v\n";

$empty = $ch2->tryRecv();
$empty2 = $ch2->tryRecv();
echo "清空后 tryRecv: " . ($empty2 === null ? "null" : $empty2) . "\n";

// 测试3: 关闭 Channel
echo "\n【测试3】关闭 Channel\n";
$ch3 = new Channel(1);
echo "isClosed: " . ($ch3->isClosed() ? "true" : "false") . "\n";
$ch3->close();
echo "关闭后 isClosed: " . ($ch3->isClosed() ? "true" : "false") . "\n";

// 测试4: 统计信息
echo "\n【测试4】统计信息\n";
$ch4 = new Channel(5);
$ch4->send("a");
$ch4->send("b");
$ch4->recv();
echo "发送计数: " . $ch4->getSendCount() . " (预期: 2)\n";
echo "接收计数: " . $ch4->getRecvCount() . " (预期: 1)\n";

echo "\n🎉 Channel 测试完成!\n";
