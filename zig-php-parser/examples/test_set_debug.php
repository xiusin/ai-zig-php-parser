<?php
$shared = new SharedData();
echo "创建成功\n";
$s = $shared->size();
echo "size: $s\n";
$shared->set("key", "value");
echo "set 完成\n";
$s2 = $shared->size();
echo "size after set: $s2\n";
