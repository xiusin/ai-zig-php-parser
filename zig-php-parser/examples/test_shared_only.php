<?php
echo "测试 SharedData\n";

$shared = new SharedData();
echo "SharedData 创建成功\n";

echo "初始 size: " . $shared->size() . "\n";

$shared->set("test", "value");
echo "set('test', 'value') 完成\n";

echo "设置后 size: " . $shared->size() . "\n";

$has = $shared->has("test");
echo "has('test'): " . ($has ? "true" : "false") . "\n";

$value = $shared->get("test");
echo "get('test'): $value\n";

echo "完成\n";
