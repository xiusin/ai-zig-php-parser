<?php
// 测试22: 位运算与二进制操作
$a = 0b10101010; // 170
$b = 0b11001100; // 204

echo "a = $a (" . decbin($a) . ")\n";
echo "b = $b (" . decbin($b) . ")\n";

// 位运算
$and = $a & $b;
$or = $a | $b;
$xor = $a ^ $b;
$not = ~$a;
$leftShift = $a << 2;
$rightShift = $a >> 2;

echo "AND: $and (" . decbin($and) . ")\n";
echo "OR: $or (" . decbin($or) . ")\n";
echo "XOR: $xor (" . decbin($xor) . ")\n";
echo "NOT: $not (" . decbin($not & 0xFF) . ")\n";
echo "Left shift: $leftShift (" . decbin($leftShift) . ")\n";
echo "Right shift: $rightShift (" . decbin($rightShift) . ")\n";

// 权限系统示例
const PERM_READ = 1 << 0;   // 1
const PERM_WRITE = 1 << 1;  // 2
const PERM_EXEC = 1 << 2;   // 4
const PERM_DELETE = 1 << 3; // 8

$userPerms = PERM_READ | PERM_WRITE | PERM_EXEC;
echo "User permissions: $userPerms\n";
echo "Can read: " . (($userPerms & PERM_READ) ? "yes" : "no") . "\n";
echo "Can delete: " . (($userPerms & PERM_DELETE) ? "yes" : "no") . "\n";

// 添加权限
$userPerms |= PERM_DELETE;
echo "After adding delete: $userPerms\n";

// 移除权限
$userPerms &= ~PERM_WRITE;
echo "After removing write: $userPerms\n";
echo "Can write: " . (($userPerms & PERM_WRITE) ? "yes" : "no") . "\n";

// 切换权限
$userPerms ^= PERM_EXEC;
echo "After toggling exec: $userPerms\n";

// 位移边界
$big = PHP_INT_MAX;
$overflow = $big << 1;
echo "Left shift overflow: $overflow\n";
?>