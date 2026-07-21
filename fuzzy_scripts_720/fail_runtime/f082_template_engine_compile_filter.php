<?php
// 极度混搭: 模板引擎 + 编译+缓存 + 沙箱安全 + 过滤器链
echo "=== f082: Template Engine + Compile + Filter ===\n";

class TemplateFilter {
    public static function upper(string $s): string { return strtoupper($s); }
    public static function lower(string $s): string { return strtolower($s); }
    public static function trim(string $s): string { return trim($s); }
    public static function escape(string $s): string { return htmlspecialchars($s, ENT_QUOTES); }
    public static function reverse(string $s): string { return strrev($s); }
    public static function default(string $s, string $default = ''): string { return $s === '' ? $default : $s; }
    public static function truncate(string $s, int $len = 10): string {
        return strlen($s) > $len ? substr($s, 0, $len) . '...' : $s;
    }
    public static function repeat(string $s, int $n = 2): string { return str_repeat($s, $n); }
    public static function capitalize(string $s): string { return ucfirst(strtolower($s)); }
    public static function slug(string $s): string {
        return strtolower(preg_replace('/[^a-zA-Z0-9]+/', '-', trim($s)));
    }
}

class TemplateCompiler {
    private array $cache = [];
    private array $filters = [];

    public function __construct() {
        $this->filters = [
            'upper' => [TemplateFilter::class, 'upper'],
            'lower' => [TemplateFilter::class, 'lower'],
            'trim' => [TemplateFilter::class, 'trim'],
            'escape' => [TemplateFilter::class, 'escape'],
            'reverse' => [TemplateFilter::class, 'reverse'],
            'truncate' => [TemplateFilter::class, 'truncate'],
            'repeat' => [TemplateFilter::class, 'repeat'],
            'capitalize' => [TemplateFilter::class, 'capitalize'],
            'slug' => [TemplateFilter::class, 'slug'],
            'default' => [TemplateFilter::class, 'default'],
        ];
    }

    public function compile(string $template): callable {
        $hash = md5($template);
        if (isset($this->cache[$hash])) return $this->cache[$hash];

        $compiled = $this->compileString($template);
        $renderer = fn(array $data) => $this->execute($compiled, $data);
        $this->cache[$hash] = $renderer;
        return $renderer;
    }

    private function compileString(string $template): array {
        $nodes = [];
        $pos = 0; $len = strlen($template);

        while ($pos < $len) {
            // 变量 {{ var }}
            if (substr($template, $pos, 2) === '{{') {
                $end = strpos($template, '}}', $pos);
                if ($end === false) break;
                $expr = trim(substr($template, $pos + 2, $end - $pos - 2));
                $nodes[] = ['type' => 'variable', 'expr' => $expr];
                $pos = $end + 2;
            }
            // 注释 {# comment #}
            elseif (substr($template, $pos, 2) === '{#') {
                $end = strpos($template, '#}', $pos);
                if ($end === false) break;
                $pos = $end + 2;
            }
            // 控制结构 {% if/for/endif/endfor %}
            elseif (substr($template, $pos, 2) === '{%') {
                $end = strpos($template, '%}', $pos);
                if ($end === false) break;
                $stmt = trim(substr($template, $pos + 2, $end - $pos - 2));
                $nodes[] = ['type' => 'control', 'stmt' => $stmt];
                $pos = $end + 2;
            }
            // 纯文本
            else {
                $nextVar = strpos($template, '{{', $pos);
                $nextCtrl = strpos($template, '{%', $pos);
                $nextCmt = strpos($template, '{#', $pos);
                $candidates = array_filter([$nextVar, $nextCtrl, $nextCmt], fn($x) => $x !== false);
                $endPos = empty($candidates) ? $len : min($candidates);
                $text = substr($template, $pos, $endPos - $pos);
                $nodes[] = ['type' => 'text', 'content' => $text];
                $pos = $endPos;
            }
        }
        return $nodes;
    }

    private function execute(array $nodes, array $data): string {
        $output = '';
        $i = 0;
        while ($i < count($nodes)) {
            $node = $nodes[$i];
            switch ($node['type']) {
                case 'text':
                    $output .= $node['content'];
                    $i++;
                    break;
                case 'variable':
                    $output .= $this->evalVariable($node['expr'], $data);
                    $i++;
                    break;
                case 'control':
                    $stmt = $node['stmt'];
                    if (str_starts_with($stmt, 'if ')) {
                        $cond = substr($stmt, 3);
                        $block = [];
                        $j = $i + 1;
                        while ($j < count($nodes) && !($nodes[$j]['type'] === 'control' && $nodes[$j]['stmt'] === 'endif')) {
                            $block[] = $nodes[$j];
                            $j++;
                        }
                        if ($this->evalCondition($cond, $data)) {
                            $output .= $this->execute($block, $data);
                        }
                        $i = $j + 1;
                    } elseif (str_starts_with($stmt, 'for ')) {
                        // for item in items
                        if (preg_match('/for\s+(\w+)\s+in\s+(\w+)/', $stmt, $m)) {
                            $itemVar = $m[1]; $listVar = $m[2];
                            $list = $data[$listVar] ?? [];
                            $block = [];
                            $j = $i + 1;
                            while ($j < count($nodes) && !($nodes[$j]['type'] === 'control' && $nodes[$j]['stmt'] === 'endfor')) {
                                $block[] = $nodes[$j];
                                $j++;
                            }
                            foreach ($list as $item) {
                                $subData = array_merge($data, [$itemVar => $item]);
                                $output .= $this->execute($block, $subData);
                            }
                            $i = $j + 1;
                        } else { $i++; }
                    } else { $i++; }
                    break;
                default:
                    $i++;
            }
        }
        return $output;
    }

    private function evalVariable(string $expr, array $data): string {
        // 支持 var|filter1|filter2(arg)
        $parts = explode('|', $expr);
        $varName = trim(array_shift($parts));
        $value = $data[$varName] ?? '';
        foreach ($parts as $filterExpr) {
            $filterExpr = trim($filterExpr);
            if (preg_match('/(\w+)\((.*)\)/', $filterExpr, $m)) {
                $filterName = $m[1];
                $arg = $m[2];
                $arg = is_numeric($arg) ? (int)$arg : trim($arg, '"\'');
                if (isset($this->filters[$filterName])) {
                    $value = ($this->filters[$filterName])($value, $arg);
                }
            } else {
                if (isset($this->filters[$filterExpr])) {
                    $value = ($this->filters[$filterExpr])($value);
                }
            }
        }
        return (string)$value;
    }

    private function evalCondition(string $cond, array $data): bool {
        if (preg_match('/(\w+)\s*(==|!=|>=|<=|>|<)\s*(.+)/', $cond, $m)) {
            $var = $data[$m[1]] ?? null;
            $val = trim($m[3], '"\'');
            $val = is_numeric($val) ? (float)$val : $val;
            return match($m[2]) {
                '==' => $var == $val, '!=' => $var != $val,
                '>=' => $var >= $val, '<=' => $var <= $val,
                '>' => $var > $val, '<' => $var < $val,
            };
        }
        return (bool)($data[trim($cond)] ?? false);
    }

    public function getCacheSize(): int { return count($this->cache); }
}

// 测试
$compiler = new TemplateCompiler();

echo "--- Variable Substitution ---\n";
$tpl1 = "Hello, {{name}}! You are {{age}} years old.";
$render1 = $compiler->compile($tpl1);
echo $render1(['name' => 'Alice', 'age' => 30]) . "\n";

echo "\n--- Filters ---\n";
$tpl2 = "Upper: {{text|upper}}\nLower: {{text|lower}}\nReverse: {{text|reverse}}\nTruncate: {{text|truncate(5)}}\nRepeat: {{text|repeat(2)}}\nSlug: {{text|slug}}";
$render2 = $compiler->compile($tpl2);
echo $render2(['text' => 'Hello World Foo Bar']) . "\n";

echo "\n--- Conditionals ---\n";
$tpl3 = "{% if age >= 18 %}Adult{% endif %} {% if age < 18 %}Minor{% endif %} (age={{age}})";
$render3 = $compiler->compile($tpl3);
echo $render3(['age' => 25]) . "\n";
echo $render3(['age' => 15]) . "\n";

echo "\n--- Loops ---\n";
$tpl4 = "Items:\n{% for item in items %}- {{item}}\n{% endfor %}";
$render4 = $compiler->compile($tpl4);
echo $render4(['items' => ['apple', 'banana', 'cherry']]) . "\n";

echo "\n--- Complex Template ---\n";
$tpl5 = "Dear {{name|upper}},\n\n{% if count > 0 %}You have {{count}} messages:\n{% for msg in messages %}  [{{msg}}]{% endfor %}{% endif %}{% if count == 0 %}No new messages.{% endif %}\n\nBest regards.";
$render5 = $compiler->compile($tpl5);
echo $render5(['name' => 'bob', 'count' => 3, 'messages' => ['Hello', 'Meeting at 3pm', 'Lunch?']]) . "\n";
echo "---\n";
echo $render5(['name' => 'alice', 'count' => 0, 'messages' => []]) . "\n";

echo "\n--- Template Cache ---\n";
echo "Cache size: " . $compiler->getCacheSize() . " templates\n";

echo "\n--- Escape Filter (XSS prevention) ---\n";
$tpl6 = "Comment: {{comment|escape}}";
$render6 = $compiler->compile($tpl6);
echo $render6(['comment' => '<script>alert("xss")</script>']) . "\n";

echo "=== f082 Done ===\n";
