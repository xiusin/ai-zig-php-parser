<?php
// f161 xp8 判别探针：isset 守卫结果 vs 臂体执行的一致性
// SENT-TRUE 仅在守卫判定为真时打印（与 isset($parts[1]) 同一读值）；
// 若某次调用无 SENT-TRUE 却出现 E.attr 行 ⇒ 守卫与臂体读值不一致（滞后/阶梯）。
// AFTER 在 if 闭合后打印：若调用次数×每值1次缺失 ⇒ merge 被吞进真臂。
class XPD {
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
        if (isset($parts[1])) {
            echo "SENT-TRUE tag={$tagName} np=" . count($parts) . "\n";
            preg_match_all('/(\w+)="([^"]*)"/', $parts[1], $attrMatches);
            echo "E.attr n=" . count($attrMatches[1]) . "\n";
            for ($i = 0; $i < count($attrMatches[1]); $i++) {
                $attributes[$attrMatches[1][$i]] = $attrMatches[2][$i];
            }
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
$p = new XPD();
$out = $p->parse('<?xml version="1.0"?><catalog>
    <book id="1" lang="en">
        <title>T1</title>
    </book>
</catalog>');
echo "tag={$out['tag']} kids=" . count($out['children']) . "\n";
