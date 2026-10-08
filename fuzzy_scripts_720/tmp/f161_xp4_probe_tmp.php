<?php
// f161 xp3：xp 最小化——去 decl/属性/文本节点，只保留 while + `<` if-else + 内层 `/` if + 递归
class XP4 {
    private string $xml;
    private int $pos = 0;

    public function parse(string $xml): array {
        $this->xml = trim($xml);
        $this->pos = 0;
        return $this->parseElement();
    }

    private function parseElement(): array {
        echo "E.enter pos={$this->pos}\n";
        $this->skipWhitespace();
        if ($this->xml[$this->pos] !== '<') { echo "E.nolt\n"; return []; }
        $this->pos++;
        $tagEnd = strpos($this->xml, '>', $this->pos);
        echo "E.tagEnd=" . $tagEnd . " pos={$this->pos}\n";
        $tagName = substr($this->xml, $this->pos, $tagEnd - $this->pos);
        $this->pos = $tagEnd + 1;
        $children = [];
        $guard = 0;
        while ($this->pos < strlen($this->xml)) {
            if (++$guard > 20) { echo "E.LOOPRUNAWAY pos={$this->pos}\n"; break; }
            $this->skipWhitespace();
            if ($this->pos >= strlen($this->xml)) break;
            echo "E.iter pos={$this->pos} ch={$this->xml[$this->pos]}\n";
            if ($this->xml[$this->pos] === '<') {
                if ($this->xml[$this->pos + 1] === '/') {
                    $endTag = strpos($this->xml, '>', $this->pos);
                    echo "E.close endTag=" . $endTag . "\n";
                    $this->pos = $endTag + 1;
                    break;
                }
                $children[] = $this->parseElement();
            } else {
                $textEnd = strpos($this->xml, '<', $this->pos);
                if ($textEnd === false) $textEnd = strlen($this->xml);
                echo "E.text {$this->pos}-{$textEnd}\n";
                $this->pos = $textEnd;
            }
        }
        echo "E.leave tag={$tagName} kids=" . count($children) . "\n";
        return ['tag' => $tagName, 'children' => $children];
    }

    private function skipWhitespace(): void {
        while ($this->pos < strlen($this->xml) && ctype_space($this->xml[$this->pos])) {
            $this->pos++;
        }
    }
}
$p = new XP4();
$out = $p->parse('<catalog>
    <book>
        <title>T1</title>
    </book>
</catalog>');
echo "tag={$out['tag']} kids=" . count($out['children']) . "\n";
