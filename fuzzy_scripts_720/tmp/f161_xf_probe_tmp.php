<?php
// f161 xf：xp 全结构 + 文本累加 $text .= 与 trim 输出的活体回显（针对 f161 文本节点为空的二分）
class XF {
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
        if ($this->xml[$this->pos] !== '<') { echo "E.nolt pos={$this->pos}\n"; return []; }
        $this->pos++;
        if ($this->xml[$this->pos] === '?') {
            $end = strpos($this->xml, '?>', $this->pos);
            echo "E.decl end=" . $end . "\n";
            $this->pos = $end + 2;
            return $this->parseElement();
        }
        $tagEnd = strpos($this->xml, '>', $this->pos);
        echo "E.tagEnd=" . $tagEnd . " pos={$this->pos}\n";
        $tagContent = substr($this->xml, $this->pos, $tagEnd - $this->pos);
        $this->pos = $tagEnd + 1;
        $parts = preg_split('/\s+/', $tagContent, 2);
        $tagName = $parts[0];
        $attributes = [];
        if (isset($parts[1])) {
            preg_match_all('/(\w+)="([^"]*)"/', $parts[1], $attrMatches);
            echo "E.attr n=" . count($attrMatches[1]) . "\n";
            for ($i = 0; $i < count($attrMatches[1]); $i++) {
                $attributes[$attrMatches[1][$i]] = $attrMatches[2][$i];
            }
        }
        if (str_ends_with($tagContent, '/')) {
            return ['tag' => $tagName, 'attributes' => $attributes, 'children' => [], 'text' => ''];
        }
        $children = [];
        $text = '';
        $guard = 0;
        while ($this->pos < strlen($this->xml)) {
            if (++$guard > 80) { echo "E.LOOPRUNAWAY pos={$this->pos}\n"; break; }
            $this->skipWhitespace();
            if ($this->pos >= strlen($this->xml)) break;
            echo "E.iter pos={$this->pos} ch={$this->xml[$this->pos]} text=[$text]\n";
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
                $chunk = substr($this->xml, $this->pos, $textEnd - $this->pos);
                echo "E.text {$this->pos}-{$textEnd} chunk=[$chunk]\n";
                $text .= $chunk;
                $this->pos = $textEnd;
            }
        }
        echo "E.leave tag={$tagName} kids=" . count($children) . " text=[$text]\n";
        return ['tag' => $tagName, 'attributes' => $attributes, 'children' => $children, 'text' => trim($text)];
    }

    private function skipWhitespace(): void {
        while ($this->pos < strlen($this->xml) && ctype_space($this->xml[$this->pos])) {
            $this->pos++;
        }
    }
}
$xml = '<?xml version="1.0"?>
<catalog>
    <book id="1" lang="en">
        <title>T1</title>
    </book>
</catalog>';
$p = new XF();
$out = $p->parse($xml);
function dump(array $n, string $ind): void {
    echo "{$ind}tag={$n['tag']} text=[{$n['text']}]\n";
    foreach ($n['children'] as $c) dump($c, $ind . "  ");
}
dump($out, "");
