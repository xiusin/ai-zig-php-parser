<?php
class LsbBase {
    public static int $counter = 0;
    public static string $who = 'none';
    public static function bump(): void {
        static::$counter = static::$counter + 1;
        static::$who = static::class;
    }
    public static function readSelf(): string {
        return "self=" . gettype(self::$counter) . "/" . var_export(self::$counter, true)
             . " who=" . var_export(self::$who, true) . "\n";
    }
    public static function readStatic(): string {
        return "static=" . gettype(static::$counter) . "/" . var_export(static::$counter, true)
             . " who=" . var_export(static::$who, true) . "\n";
    }
}
class LsbChild extends LsbBase {}

echo "-- bump via child (static:: 解析为 called class), 再按声明类读回\n";
LsbChild::bump();
LsbChild::bump();
echo LsbBase::readSelf();
echo LsbBase::readStatic();
echo "-- 再经父类名直接写、子类名读\n";
LsbBase::$counter = 100;
echo "child_read=" . var_export(LsbChild::$counter, true) . " parent_read=" . var_export(LsbBase::$counter, true) . "\n";
echo "DONE\n";
