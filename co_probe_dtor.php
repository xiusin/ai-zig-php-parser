<?php
// 临时探针：对象析构时机（无协程对照）
class DD {
    public static $log = [];
    public $tag;
    public function __construct($t) {
        $this->tag = $t;
    }
    public function __destruct() {
        DD::$log[] = $this->tag;
    }
}
$o = new DD("x");
unset($o);
echo "after_unset count=" . count(DD::$log) . "\n";
gc_collect_cycles();
echo "after_gc count=" . count(DD::$log) . "\n";
echo "DONE\n";
