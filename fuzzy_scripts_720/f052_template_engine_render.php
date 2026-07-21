<?php
// 极度混搭: 模板引擎 + 变量替换 + 条件渲染 + 循环渲染 + 过滤器
echo "=== f052: Template Engine + Variable + Condition + Loop ===\n";

class TemplateEngine {
    private array $filters = [];

    public function __construct() {
        $this->registerFilter('upper', fn($v) => strtoupper((string)$v));
        $this->registerFilter('lower', fn($v) => strtolower((string)$v));
        $this->registerFilter('title', fn($v) => ucwords((string)$v));
        $this->registerFilter('trim', fn($v) => trim((string)$v));
        $this->registerFilter('reverse', fn($v) => strrev((string)$v));
        $this->registerFilter('length', fn($v) => strlen((string)$v));
        $this->registerFilter('default', fn($v, $d = '') => empty($v) ? $d : $v);
        $this->registerFilter('truncate', function($v, $len = 50, $suffix = '...') {
            $v = (string)$v;
            if (strlen($v) <= $len) return $v;
            return substr($v, 0, $len - strlen($suffix)) . $suffix;
        });
        $this->registerFilter('repeat', fn($v, $n = 2) => str_repeat((string)$v, $n));
        $this->registerFilter('replace', fn($v, $search, $replace) => str_replace($search, $replace, (string)$v));
        $this->registerFilter('json', fn($v) => json_encode($v));
    }

    public function registerFilter(string $name, callable $fn): void {
        $this->filters[$name] = $fn;
    }

    public function render(string $template, array $data): string {
        // 处理条件块 {{if condition}}...{{else}}...{{endif}}
        $template = $this->renderConditions($template, $data);
        // 处理循环块 {{foreach items as item}}...{{endforeach}}
        $template = $this->renderLoops($template, $data);
        // 处理变量 {{variable|filter:arg}}
        $template = $this->renderVariables($template, $data);
        return $template;
    }

    private function renderConditions(string $template, array $data): string {
        while (preg_match('/\{\{if\s+(\w+)\}\}(.*?)\{\{else\}\}(.*?)\{\{endif\}\}/s', $template, $m)) {
            $condition = $data[$m[1]] ?? false;
            $replacement = $condition ? $m[2] : $m[3];
            $template = str_replace($m[0], $replacement, $template);
        }
        // 无else的条件
        while (preg_match('/\{\{if\s+(\w+)\}\}(.*?)\{\{endif\}\}/s', $template, $m)) {
            $condition = $data[$m[1]] ?? false;
            $replacement = $condition ? $m[2] : '';
            $template = str_replace($m[0], $replacement, $template);
        }
        return $template;
    }

    private function renderLoops(string $template, array $data): string {
        while (preg_match('/\{\{foreach\s+(\w+)\s+as\s+(\w+)\}\}(.*?)\{\{endforeach\}\}/s', $template, $m)) {
            $arrayVar = $m[1];
            $itemVar = $m[2];
            $body = $m[3];
            $array = $data[$arrayVar] ?? [];
            $replacement = '';
            foreach ($array as $item) {
                $itemData = array_merge($data, [$itemVar => $item]);
                $replacement .= $this->renderVariables($body, $itemData);
            }
            $template = str_replace($m[0], $replacement, $template);
        }
        return $template;
    }

    private function renderVariables(string $template, array $data): string {
        // 匹配 {{variable|filter:arg|filter2:arg2}}
        return preg_replace_callback('/\{\{(\w+)((?:\|\w+(?::[^|}]+)*)*)\}\}/', function($m) use ($data) {
            $varName = $m[1];
            $filters = $m[2];
            $value = $data[$varName] ?? '';

            if (!empty($filters)) {
                $filterParts = explode('|', trim($filters, '|'));
                foreach ($filterParts as $filterPart) {
                    if (str_contains($filterPart, ':')) {
                        [$filterName, $arg] = explode(':', $filterPart, 2);
                        $args = explode(',', $arg);
                        if (isset($this->filters[$filterName])) {
                            $value = ($this->filters[$filterName])($value, ...$args);
                        }
                    } else {
                        if (isset($this->filters[$filterPart])) {
                            $value = ($this->filters[$filterPart])($value);
                        }
                    }
                }
            }
            return (string)$value;
        }, $template);
    }
}

// 测试
$tpl = new TemplateEngine();

// 简单变量替换
echo $tpl->render("Hello, {{name}}!", ['name' => 'World']) . "\n";
echo $tpl->render("Name: {{name|upper}}, Age: {{age}}", ['name' => 'alice', 'age' => 30]) . "\n";

// 过滤器
echo $tpl->render("{{name|upper}}", ['name' => 'hello']) . "\n";
echo $tpl->render("{{name|lower}}", ['name' => 'HELLO']) . "\n";
echo $tpl->render("{{name|title}}", ['name' => 'hello world']) . "\n";
echo $tpl->render("{{name|reverse}}", ['name' => 'hello']) . "\n";
echo $tpl->render("{{name|truncate:8}}", ['name' => 'Hello World']) . "\n";
echo $tpl->render("{{name|default:Anonymous}}", ['name' => '']) . "\n";
echo $tpl->render("{{name|replace:hello:hi}}", ['name' => 'hello world']) . "\n";
echo $tpl->render("{{data|json}}", ['data' => ['a' => 1, 'b' => 2]]) . "\n";

// 条件
echo $tpl->render(
    "{{if show}}Visible{{else}}Hidden{{endif}}",
    ['show' => true]
) . "\n";
echo $tpl->render(
    "{{if show}}Visible{{else}}Hidden{{endif}}",
    ['show' => false]
) . "\n";

// 循环
$loopTpl = "{{foreach users as user}}- {{user|upper}}\n{{endforeach}}";
echo $tpl->render($loopTpl, ['users' => ['alice', 'bob', 'charlie']]);

// 组合模板
$fullTpl = "=== Report ===\n{{foreach items as item}}[{{item.id}}] {{item.name|title}} - {{item.price}}\n{{foreach item.tags as tag}}  #{{tag}}\n{{endforeach}}{{endforeach}}";
$data = [
    'items' => [
        ['id' => 1, 'name' => 'widget', 'price' => 9.99, 'tags' => ['new', 'sale']],
        ['id' => 2, 'name' => 'gadget', 'price' => 19.99, 'tags' => ['popular']],
    ],
];
echo $tpl->render($fullTpl, $data);

echo "=== f052 Done ===\n";
