<?php
// 模板引擎：变量替换、条件、循环、布局继承、区块
class TemplateEngine {
    private string $templateDir;
    private array $sections = [];
    private ?string $layout = null;

    public function __construct(string $templateDir = 'templates') {
        $this->templateDir = $templateDir;
    }

    public function render(string $template, array $data = []): string {
        $content = $this->getTemplateContent($template);
        return $this->compile($content, $data);
    }

    private function getTemplateContent(string $template): string {
        // 内置模板（不依赖文件系统，用字符串模拟）
        $templates = [
            'layout' => '<!DOCTYPE html><html><head><title>{block title}Default Title{/block}</title></head><body>{block content}{/block}</body></html>',
            'home' => '{extends layout}{block title}Home Page{/block}{block content}<h1>{$title}</h1><ul>{foreach $items as $item}<li>{$item}</li>{/foreach}</ul><p>Total: {count($items)}</p>{/block}',
            'user_list' => '{extends layout}{block title}Users{/block}{block content}<h1>Users</h1><table><tr><th>ID</th><th>Name</th><th>Email</th></tr>{foreach $users as $user}<tr><td>{$user.id}</td><td>{$user.name}</td><td>{$user.email}</td></tr>{/foreach}</table><p>Total users: {count($users)}</p>{/block}',
            'user_detail' => '{extends layout}{block title}User {$user.name}{/block}{block content}<h1>{$user.name}</h1><p>ID: {$user.id}</p><p>Email: {$user.email}</p><p>Role: {$user.role}</p>{if $user.role == "admin"}<p class="badge">Administrator</p>{/if}{/block}',
            'error' => '{extends layout}{block title}Error {$code}{/block}{block content}<h1>Error {$code}</h1><p>{$message}</p>{/block}',
        ];
        return $templates[$template] ?? "<!-- Template '$template' not found -->";
    }

    private function compile(string $content, array $data): string {
        // 处理继承
        if (preg_match('/\{extends\s+(\w+)\}/', $content, $m)) {
            $this->layout = $m[1];
            $content = preg_replace('/\{extends\s+\w+\}/', '', $content);
        }

        // 提取区块
        preg_match_all('/\{block\s+(\w+)\}(.*?)\{\/block\}/s', $content, $blocks);
        $blockNames = $blocks[1];
        $blockContents = $blocks[2];
        for ($i = 0; $i < count($blockNames); $i++) {
            $this->sections[$blockNames[$i]] = $blockContents[$i];
        }
        $content = preg_replace('/\{block\s+\w+\}.*?\{\/block\}/s', '', $content);

        // 如果有布局，用布局包裹
        if ($this->layout !== null) {
            $layoutContent = $this->getTemplateContent($this->layout);
            foreach ($this->sections as $name => $blockContent) {
                $layoutContent = preg_replace('/\{block\s+' . $name . '\}.*?\{\/block\}/s', $blockContent, $layoutContent);
            }
            $content = $layoutContent;
        }

        // 处理条件
        $content = $this->compileConditions($content, $data);

        // 处理循环
        $content = $this->compileLoops($content, $data);

        // 处理函数调用 {count($var)}
        $content = preg_replace_callback('/\{([a-zA-Z_]+)\(([^)]+)\)\}/', function($m) use ($data) {
            $func = $m[1];
            $arg = $m[2];
            $arg = ltrim($arg, '$');
            $val = $data[$arg] ?? [];
            if (function_exists($func)) {
                return (string)$func($val);
            }
            return (string)count($val);
        }, $content);

        // 处理变量 {$var} 和 {$obj.property}
        $content = preg_replace_callback('/\{\$([a-zA-Z_][a-zA-Z0-9_.]*)\}/', function($m) use ($data) {
            $path = $m[1];
            $parts = explode('.', $path);
            $val = $data[$parts[0]] ?? '';
            for ($i = 1; $i < count($parts); $i++) {
                if (is_array($val)) {
                    $val = $val[$parts[$i]] ?? '';
                } elseif (is_object($val)) {
                    $val = $val->{$parts[$i]} ?? '';
                } else {
                    $val = '';
                }
            }
            return (string)$val;
        }, $content);

        // 清理未处理的标签
        $content = preg_replace('/\{[^}]*\}/', '', $content);

        return $content;
    }

    private function compileConditions(string $content, array $data): string {
        // {if condition} ... {/if}
        $content = preg_replace_callback('/\{if\s+([^}]+)\}(.*?)(?:\{else\}(.*?))?\{\/if\}/s', function($m) use ($data) {
            $cond = $m[1];
            $truePart = $m[2];
            $falsePart = $m[3] ?? '';
            $cond = $this->evalCondition($cond, $data);
            return $cond ? $truePart : $falsePart;
        }, $content);
        return $content;
    }

    private function evalCondition(string $cond, array $data): bool {
        // 解析 $var == "value" 或 $var != "value" 格式（不使用 eval）
        if (preg_match('/\$([a-zA-Z_.]+)\s*(==|!=)\s*"([^"]*)"/', $cond, $m)) {
            $path = $m[1];
            $op = $m[2];
            $expected = $m[3];
            $parts = explode('.', $path);
            $val = $data[$parts[0]] ?? '';
            for ($i = 1; $i < count($parts); $i++) {
                if (is_array($val)) $val = $val[$parts[$i]] ?? '';
            }
            if ($op === '==') return (string)$val === $expected;
            return (string)$val !== $expected;
        }
        // 解析 $var 格式（真值判断）
        if (preg_match('/\$([a-zA-Z_.]+)/', $cond, $m)) {
            $path = $m[1];
            $parts = explode('.', $path);
            $val = $data[$parts[0]] ?? '';
            for ($i = 1; $i < count($parts); $i++) {
                if (is_array($val)) $val = $val[$parts[$i]] ?? '';
            }
            return !empty($val);
        }
        return false;
    }

    private function compileLoops(string $content, array $data): string {
        // {foreach $items as $item} ... {/foreach}
        $content = preg_replace_callback('/\{foreach\s+\$([a-zA-Z_]+)\s+as\s+\$([a-zA-Z_]+)\}(.*?)\{\/foreach\}/s', function($m) use ($data) {
            $listVar = $m[1];
            $itemVar = $m[2];
            $body = $m[3];
            $list = $data[$listVar] ?? [];
            $result = '';
            foreach ($list as $item) {
                $itemData = array_merge($data, [$itemVar => $item]);
                $itemBody = $body;
                // 替换 {$item.property}
                $itemBody = preg_replace_callback('/\{\$' . $itemVar . '\.([a-zA-Z_]+)\}/', function($m2) use ($item) {
                    if (is_array($item)) return (string)($item[$m2[1]] ?? '');
                    if (is_object($item)) return (string)($item->{$m2[1]} ?? '');
                    return '';
                }, $itemBody);
                // 替换 {$item}
                $itemBody = str_replace('{$' . $itemVar . '}', (string)$item, $itemBody);
                $result .= $itemBody;
            }
            return $result;
        }, $content);
        return $content;
    }
}
