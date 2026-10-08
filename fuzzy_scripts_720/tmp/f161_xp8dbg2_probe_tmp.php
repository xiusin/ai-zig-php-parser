<?php
// f161 xp8：xp7 + decl if（复现 xp 完整链路）：xp4 + 属性区（preg_split/isset/preg_match_all/for），二分最后缺陷
class XP8 {
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
                        if ($this->xml[$this->pos] === '?') {
            $end = strpos($this->xml, '?>', $this->pos);
            echo 'E.decl end=' . var_export($end, true) . chr(10);
            $this->pos = $end + 2;
            return $this->parseElement();
        }
        $tagEnd = strpos($this->xml, '>', $this->pos);
        echo "E.tagEnd={$tagEnd} pos={$this->pos}\n";
        $tagContent = substr($this->xml, $this->pos, $tagEnd - $this->pos);
        $this->pos = $tagEnd + 1;
        $parts = preg_split('/\s+/', $tagContent, 2);
        $tagName = $parts[0];
        $attributes = [];
        if (isset($parts[1])) {
            echo "IN guard\n";
            preg_match_all('/(\w+)="([^"]*)"/', $parts[1], $attrMatches);
            echo "E.attr n=" . count($attrMatches[1]) . "\n";
            for ($i = 0; $i < count($attrMatches[1]); $i++) {
                $attributes[$attrMatches[1][$i]] = $attrMatches[2][$i];
            }
        }
        $children = [];
        $guard = 0;
        while ($this->pos < strlen($this->xml)) {
            if (++$guard > 60) { echo "E.LOOPRUNAWAY pos={$this->pos}\n"; break; }
            $this->skipWhitespace();
            if ($this->pos >= strlen($this->xml)) break;
            echo "E.iter pos={$this->pos} ch={$this->xml[$this->pos]}\n";
            if ($this->xml[$this->pos] === '<') {
                if ($this->xml[$this->pos + 1] === '/') {
                    $endTag = strpos($this->xml, '>', $this->pos);
                    echo "E.close endTag={$endTag}\n";
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
$p = new XP8();
$out = $p->parse('<?xml version="1.0"?><catalog>
    <book id="1" lang="en">
        <title>T1</title>
    </book>
</catalog>');
echo "tag={$out['tag']} kids=" . count($out['children']) . "\n";
