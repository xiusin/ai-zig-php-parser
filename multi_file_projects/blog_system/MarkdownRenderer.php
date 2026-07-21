<?php
// 博客系统 - Markdown 简易渲染器
class MarkdownRenderer {
    public function render(string $markdown): string {
        $html = $markdown;

        // 标题 h1-h6
        $html = preg_replace('/^######\s+(.+)$/m', '<h6>$1</h6>', $html);
        $html = preg_replace('/^#####\s+(.+)$/m', '<h5>$1</h5>', $html);
        $html = preg_replace('/^####\s+(.+)$/m', '<h4>$1</h4>', $html);
        $html = preg_replace('/^###\s+(.+)$/m', '<h3>$1</h3>', $html);
        $html = preg_replace('/^##\s+(.+)$/m', '<h2>$1</h2>', $html);
        $html = preg_replace('/^#\s+(.+)$/m', '<h1>$1</h1>', $html);

        // 粗体和斜体
        $html = preg_replace('/\*\*\*(.+?)\*\*\*/s', '<strong><em>$1</em></strong>', $html);
        $html = preg_replace('/\*\*(.+?)\*\*/s', '<strong>$1</strong>', $html);
        $html = preg_replace('/\*(.+?)\*/s', '<em>$1</em>', $html);

        // 行内代码
        $html = preg_replace('/`([^`]+)`/', '<code>$1</code>', $html);

        // 链接 [text](url)
        $html = preg_replace('/\[([^\]]+)\]\(([^)]+)\)/', '<a href="$2">$1</a>', $html);

        // 图片 ![alt](src)
        $html = preg_replace('/!\[([^\]]*)\]\(([^)]+)\)/', '<img src="$2" alt="$1">', $html);

        // 引用块
        $html = preg_replace('/^>\s+(.+)$/m', '<blockquote>$1</blockquote>', $html);

        // 水平线
        $html = preg_replace('/^---$/m', '<hr>', $html);

        // 无序列表
        $html = preg_replace_callback('/(?:^[-*]\s+.+\n?)+/m', function($m) {
            $items = preg_replace('/^[-*]\s+/m', '', $m[0]);
            $items = preg_replace('/^(.+)$/m', '<li>$1</li>', $items);
            return "<ul>$items</ul>";
        }, $html);

        // 有序列表
        $html = preg_replace_callback('/(?:^\d+\.\s+.+\n?)+/m', function($m) {
            $items = preg_replace('/^\d+\.\s+/m', '', $m[0]);
            $items = preg_replace('/^(.+)$/m', '<li>$1</li>', $items);
            return "<ol>$items</ol>";
        }, $html);

        // 代码块 ```
        $html = preg_replace_callback('/```(\w*)\n(.*?)```/s', function($m) {
            $lang = $m[1] ? " class=\"language-{$m[1]}\"" : '';
            return "<pre><code$lang>" . htmlspecialchars($m[2]) . "</code></pre>";
        }, $html);

        // 段落（连续非空行）
        $html = preg_replace_callback('/(.+)(\n.+)*\n/', function($m) {
            $text = $m[0];
            // 如果已经被其他标签包裹，跳过
            if (preg_match('/^<(h[1-6]|ul|ol|pre|blockquote|hr|img|a)/', trim($text))) return $text;
            return "<p>$text</p>";
        }, $html);

        return $html;
    }

    public function renderArticle(Article $article): string {
        return $this->render($article->content);
    }
}
