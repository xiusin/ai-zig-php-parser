<?php
// f161 xp8 三分叉判别：preg_split 数组内容 vs count vs isset vs 守卫
// 分支1: var_dump 显示数组真实内容（若出现 [1]=>"" 幽灵元素 → preg_split 运行时缺陷）
// 分支2: count/isset 不一致（isset true 但 count=1 且 var_dump 只 1 元素 → php_array_isset 缺陷）
// 分支3: 各项一致但守卫进臂（→ 链接器控制流缺陷）
class DISC2 {
    private string $xml;
    private int $pos = 0;

    public function go(string $xml): string {
        $this->xml = $xml;
        $this->pos = 0;
        $tagEnd = strpos($this->xml, '>', $this->pos);
        $tagContent = substr($this->xml, $this->pos, $tagEnd - $this->pos);
        $this->pos = $tagEnd + 1;
        $parts = preg_split('/\s+/', $tagContent, 2);
        echo "VD:";
        var_dump($parts);
        echo "NP=" . count($parts) . "\n";
        echo "IS=" . var_export(isset($parts[1]), true) . "\n";
        if (isset($parts[1])) {
            echo "IN-GUARD\n";
        }
        $x = $this->inner("<plain>");
        return "done" . $tagEnd . $x;
    }

    private function inner(string $t): string {
        $end = strpos($t, '>', 0);
        $content = substr($t, 1, $end - 1);
        $p2 = preg_split('/\s+/', $content, 2);
        echo "VD2:";
        var_dump($p2);
        echo "IS2=" . var_export(isset($p2[1]), true) . "\n";
        if (isset($p2[1])) {
            echo "IN-GUARD2\n";
        }
        return $content;
    }
}
$d = new DISC2();
echo $d->go("<catalog attrs>x</catalog>") . "\n";
echo "---no-attr case---\n";
$d2 = new DISC2();
echo $d2->go("<catalog>") . "\n";
