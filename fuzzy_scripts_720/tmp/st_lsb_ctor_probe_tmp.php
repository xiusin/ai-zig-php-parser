<?php
// 永久探针（任务 #116 → AOT-RUNTIME-002 §3 G4-e）：f004 的静态属性共享形（实例构造器内的 static:: 自增）
// f004_oop_deep_inheritance_magic.php:2 自述意图即「static属性共享」，:6/:12/:37 为该形的原始出处，
// 但 f004 被官方门 skip-before-compile 排除 ⇒ 本探针把该形从 SKIP 覆盖里回收为可复测资产。
class LsbEnt {
    protected static int $entityCount = 0;
    public function __construct(public readonly string $uuid) {
        static::$entityCount++;
    }
    public static function countViaStatic(): int { return static::$entityCount; }
    public static function countViaSelf(): int { return self::$entityCount; }
    public function __destruct() {}
}
class LsbChildEnt extends LsbEnt {}

$a = new LsbEnt("base-1");
$b = new LsbChildEnt("child-1");
$c = new LsbChildEnt("child-2");
echo "via_static=" . LsbEnt::countViaStatic() . " via_self=" . LsbEnt::countViaSelf() . "\n";
echo "child_static=" . LsbChildEnt::countViaStatic() . " child_self=" . LsbChildEnt::countViaSelf() . "\n";
try {
    echo "direct_base=" . var_export(LsbEnt::$entityCount, true) . "\n";
} catch (Throwable $e) {
    echo "direct_base=" . get_class($e) . ": " . $e->getMessage() . "\n";
}
echo "DONE\n";
