<?php
// f161 xp9：xp7 去 for 循环，保留 preg_split/isset/preg_match_all
class XP9 {
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
        echo "E.tagEnd={$tagEnd} pos={$this->pos}\n";
        $tagContent = substr($this->xml, $this->pos, $tagEnd - $this->pos);
        $this->pos = $tagEnd + 1;
        $parts = preg_split('/\s+/', $tagContent, 2);
        $tagName = $parts[0];
        $attributes = [];
        if (isset($parts[1])) {
            preg_match_all('/(\w+)="([^"]*)"/', $parts[1], $attrMatches);
            echo "E.attr n=" . count($attrMatches[1]) . "\n";
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
$p = new XP9();
$out = $p->parse('<?xml version="1.0"?><catalog>
    <book id="1" lang="en">
        <title>T1</title>
    </book>
</catalog>');
echo "tag={$out['tag']} kids=" . count($out['children']) . "\n";
