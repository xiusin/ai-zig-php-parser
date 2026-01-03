<?php
// 测试echo函数是否自动追加换行符
echo "Hello";
echo " ";
echo "World";
echo "\n"; // 手动添加换行符

echo "This should be on a new line without automatic newline\n";
echo "Another line";
echo " - ";
echo "continued\n";

echo "Final test: ";
echo "no auto newline";
echo " - ";
echo "works correctly\n";
