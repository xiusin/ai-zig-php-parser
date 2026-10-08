<?php
// 永久探针（任务 #114 → 工单 AOT-CODEGEN-009，2026-10-07）：无父类作用域里的 parent::class
// PHP 真值 = Fatal error: Cannot use "parent" when current class scope has no parent（rc=255）
// 本形必须独立成文件：致命会终止进程，混在多形脚本里会吃掉后续所有断言
class PBase {
    public function p(): string { return 'parent=' . parent::class; }
}
$o = new PBase();
echo "p=" . $o->p() . "\n";
echo "DONE\n";
