<?php

echo "测试简单 break:\n";
for range 5 as $i {
    echo "i = " . $i . "\n";
    break;
    echo "这行不应该执行\n";
}
echo "循环结束\n";
