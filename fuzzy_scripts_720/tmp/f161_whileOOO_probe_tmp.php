<?php
// f161 缺陷B 的 while 形 OOO（乱序共享 merge）证据探针：
// 与 f161_xp8disc4_probe_tmp.php 同形，仅把臂内 for 循环改写为 while。
// 该形态下 while 的假出口同样汇入位于循环头之前的外层 if 共享 merge 块。
// generateWhileFromLabels 已有无条件 OOO 守卫（exit_idx < cond_idx 即留块交还），
// 本探针用于证明 while 侧无需与 for 侧对称补闸门：结果必须与 PHP 逐字节一致（MATCH）。
class WOD {
    private string $xml;
    private int $pos = 0;

    public function parse(string $xml): array {
        $this->xml = trim($xml);
        $this->pos = 0;
        return $this->parseElement();
    }

    private function parseElement(): array {
        $this->skipWhitespace();
        if ($this->xml[$this->pos] !== '<') { return []; }
        $this->pos++;
        if ($this->xml[$this->pos] === '?') {
            $end = strpos($this->xml, '?>', $this->pos);
            $this->pos = $end + 2;
            return $this->parseElement();
        }
        $tagEnd = strpos($this->xml, '>', $this->pos);
        $tagContent = substr($this->xml, $this->pos, $tagEnd - $this->pos);
        $this->pos = $tagEnd + 1;
        $parts = preg_split('/\s+/', $tagContent, 2);
        $tagName = $parts[0];
        $attributes = [];
        echo "VD> " . json_encode($parts) . " c=" . count($parts) . " ak=" . var_export(array_key_exists(1, $parts), true) . " is=" . var_export(isset($parts[1]), true) . "\n";
        if (isset($parts[1])) {
            echo "VD-IN2 is=" . var_export(isset($parts[1]), true) . "\n";
            echo "SENT-TRUE tag={$tagName} np=" . count($parts) . "\n";
            preg_match_all('/(\w+)="([^"]*)"/', $parts[1], $attrMatches);
            echo "E.attr n=" . count($attrMatches[1]) . "\n";
            $i = 0;
            while ($i < count($attrMatches[1])) {
                $attributes[$attrMatches[1][$i]] = $attrMatches[2][$i];
                $i++;
            }
            echo "ATTRS=" . json_encode($attributes) . "\n";
        }
        echo "AFTER tag={$tagName}\n";
        $children = [];
        $guard = 0;
        while ($this->pos < strlen($this->xml)) {
            if (++$guard > 60) { echo "LOOPRUNAWAY\n"; break; }
            $this->skipWhitespace();
            if ($this->pos >= strlen($this->xml)) break;
            if ($this->xml[$this->pos] === '<') {
                if ($this->xml[$this->pos + 1] === '/') {
                    $endTag = strpos($this->xml, '>', $this->pos);
                    $this->pos = $endTag + 1;
                    break;
                }
                $children[] = $this->parseElement();
            } else {
                $textEnd = strpos($this->xml, '<', $this->pos);
                if ($textEnd === false) $textEnd = strlen($this->xml);
                $this->pos = $textEnd;
            }
        }
        return ['tag' => $tagName, 'children' => $children];
    }

    private function skipWhitespace(): void {
        while ($this->pos < strlen($this->xml) && ctype_space($this->xml[$this->pos])) {
            $this->pos++;
        }
    }
}
$p = new WOD();
$out = $p->parse('<?xml version="1.0"?><catalog>
    <book id="1" lang="en">
        <title>T1</title>
    </book>
</catalog>');
echo "tag={$out['tag']} kids=" . count($out['children']) . "\n";
