<?php
// f161 xh：极简文本节点累加复现——flat 文档 `<a>hello</a>`，无声明/属性/自闭合分支
class XH {
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
        $text = '';
        $guard = 0;
        while ($this->pos < strlen($this->xml)) {
            if (++$guard > 30) { echo "E.LOOPRUNAWAY pos={$this->pos}\n"; break; }
            echo "E.iter pos={$this->pos} ch={$this->xml[$this->pos]} text=[$text]\n";
            if ($this->xml[$this->pos] === '<') {
                $endTag = strpos($this->xml, '>', $this->pos);
                echo "E.close endTag=" . $endTag . "\n";
                $this->pos = $endTag + 1;
                break;
            } else {
                $textEnd = strpos($this->xml, '<', $this->pos);
                if ($textEnd === false) $textEnd = strlen($this->xml);
                echo "E.text {$this->pos}-{$textEnd}\n";
                $text .= substr($this->xml, $this->pos, $textEnd - $this->pos);
                $this->pos = $textEnd;
            }
        }
        echo "E.leave tag={$tagName} text=[$text]\n";
        return ['tag' => $tagName, 'text' => trim($text)];
    }

    private function skipWhitespace(): void {
        while ($this->pos < strlen($this->xml) && ctype_space($this->xml[$this->pos])) {
            $this->pos++;
        }
    }
}
$p = new XH();
$out = $p->parse('<a>hello</a>');
echo "tag={$out['tag']} text=[{$out['text']}]\n";
