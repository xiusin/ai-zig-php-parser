<?php
// f161 超时组探针：SimpleXmlParser 挂起点二分（echo 标记法）
class XP {
    private string $xml;
    private int $pos = 0;

    public function parse(string $xml): array {
        echo "P.enter\n";
        $this->xml = trim($xml);
        $this->pos = 0;
        $r = $this->parseElement();
        echo "P.done\n";
        return $r;
    }

    private function parseElement(): array {
        echo "E.enter pos={$this->pos}\n";
        $this->skipWhitespace();
        if ($this->xml[$this->pos] !== '<') { echo "E.nolt pos={$this->pos}\n"; return []; }
        $this->pos++;
        if ($this->xml[$this->pos] === '?') {
            $end = strpos($this->xml, '?>', $this->pos);
            echo "E.decl end=" . var_export($end, true) . "\n";
            $this->pos = $end + 2;
            return $this->parseElement();
        }
        $tagEnd = strpos($this->xml, '>', $this->pos);
        echo "E.tagEnd=" . var_export($tagEnd, true) . " pos={$this->pos}\n";
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
            if (++$guard > 60) { echo "E.LOOPRUNAWAY pos={$this->pos}\n"; break; }
            $this->skipWhitespace();
            if ($this->pos >= strlen($this->xml)) break;
            echo "E.iter pos={$this->pos} ch={$this->xml[$this->pos]}\n";
            if ($this->xml[$this->pos] === '<') {
                if ($this->xml[$this->pos + 1] === '/') {
                    $endTag = strpos($this->xml, '>', $this->pos);
                    echo "E.close endTag=" . var_export($endTag, true) . "\n";
                    $this->pos = $endTag + 1;
                    break;
                }
                $children[] = $this->parseElement();
            } else {
                $textEnd = strpos($this->xml, '<', $this->pos);
                if ($textEnd === false) $textEnd = strlen($this->xml);
                $text .= substr($this->xml, $this->pos, $textEnd - $this->pos);
                $this->pos = $textEnd;
            }
        }
        return ['tag' => $tagName, 'attributes' => $attributes, 'children' => $children, 'text' => trim($text)];
    }

    private function skipWhitespace(): void {
        $n = 0;
        while ($this->pos < strlen($this->xml) && ctype_space($this->xml[$this->pos])) {
            $this->pos++;
            if (++$n > 200) { echo "W.LOOPRUNAWAY pos={$this->pos} ch={$this->xml[$this->pos]}\n"; break; }
        }
    }
}
$xml = '<?xml version="1.0"?>
<catalog>
    <book id="1" lang="en">
        <title>T1</title>
    </book>
</catalog>';
$p = new XP();
$out = $p->parse($xml);
echo "tag={$out['tag']} kids=" . count($out['children']) . "\n";
