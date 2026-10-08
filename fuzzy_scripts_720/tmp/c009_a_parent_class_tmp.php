<?php
// 永久探针（任务 #114 → 工单 AOT-CODEGEN-009，2026-10-07）：parent::class 未解析
// 直线语句、无 if/elseif 链 ⇒ 排除 CODEGEN-008 发射丢失干扰；每形独立文件独立编译（argv 派发链会吃掉自己的臂）
// 覆盖：三层继承链上的 parent::class / self::class / static::class（LSB）/ 字面量 ::class
class GRoot {
    public function names(): string { return 'self=' . self::class . ' static=' . static::class . ' lit=' . GRoot::class; }
}
class GMid extends GRoot {
    public function up(): string { return 'parent=' . parent::class; }
}
class GLeaf extends GMid {
    public function up(): string { return 'parent=' . parent::class; }
}
$r = new GRoot();
$m = new GMid();
$l = new GLeaf();
echo "root=" . $r->names() . "\n";
echo "mid=" . $m->names() . "\n";
echo "leaf=" . $l->names() . "\n";
echo "midup=" . $m->up() . "\n";
echo "leafup=" . $l->up() . "\n";
echo "DONE\n";
