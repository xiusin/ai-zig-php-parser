<?php
// 博客系统入口 - 多文件 AOT 测试
echo "============================================\n";
echo "Blog System Multi-File AOT Test\n";
echo "============================================\n\n";

require_once 'Database.php';
require_once 'User.php';
require_once 'Article.php';
require_once 'Comment.php';
require_once 'Tag.php';
require_once 'MarkdownRenderer.php';

$db = BlogDB::getInstance();
$md = new MarkdownRenderer();

// === 初始化用户 ===
echo "--- Initialize Users ---\n";
$admin = BlogUser::create('Admin', 'admin@blog.com', 'admin_pass', 'admin');
$editor = BlogUser::create('Editor', 'editor@blog.com', 'editor_pass', 'editor');
$author = BlogUser::create('Author', 'author@blog.com', 'author_pass', 'author');
$reader = BlogUser::create('Reader', 'reader@blog.com', 'reader_pass', 'reader');
echo "  Users created: {$admin->id}, {$editor->id}, {$author->id}, {$reader->id}\n";

echo "  Admin permissions: create_post=" . ($admin->can('create_post') ? 'Y' : 'N')
   . " manage_users=" . ($admin->can('manage_users') ? 'Y' : 'N') . "\n";
echo "  Reader permissions: create_post=" . ($reader->can('create_post') ? 'Y' : 'N')
   . " create_comment=" . ($reader->can('create_comment') ? 'Y' : 'N') . "\n";

// === 登录验证 ===
echo "\n--- Login Test ---\n";
$loginUser = BlogUser::findByEmail('admin@blog.com');
echo "  Login admin: " . ($loginUser && $loginUser->verifyPassword('admin_pass') ? 'SUCCESS' : 'FAIL') . "\n";
echo "  Wrong password: " . ($loginUser && $loginUser->verifyPassword('wrong') ? 'SUCCESS' : 'FAIL') . "\n";

// === 创建标签 ===
echo "\n--- Create Tags ---\n";
$tagPhp = Tag::create('PHP', 'PHP programming language');
$tagZig = Tag::create('Zig', 'Zig programming language');
$tagWeb = Tag::create('Web Development', 'Web development articles');
$tagAOT = Tag::create('AOT', 'Ahead-of-Time compilation');
echo "  Tags: {$tagPhp->name}({$tagPhp->id}), {$tagZig->name}({$tagZig->id}), {$tagWeb->name}({$tagWeb->id}), {$tagAOT->name}({$tagAOT->id})\n";
echo "  Slug: php=" . Tag::findBySlug('php')?->name . ", zig=" . Tag::findBySlug('zig')?->name . "\n";

// === 创建文章 ===
echo "\n--- Create Articles ---\n";
$article1 = Article::create(
    'Getting Started with PHP AOT',
    "# Introduction\n\nPHP AOT compilation is **awesome**. It allows you to *compile* PHP code ahead of time.\n\n## Features\n\n- Fast execution\n- Type safety\n- No interpreter overhead\n\n```php\n<?php\necho 'Hello AOT!';\n```\n\nVisit [PHP.net](https://php.net) for more info.",
    $admin->id,
    'published'
);
$article1->attachTag($tagPhp->id);
$article1->attachTag($tagAOT->id);
echo "  Article 1: {$article1->title} (id={$article1->id})\n";
echo "  Excerpt: {$article1->excerpt}\n";

$article2 = Article::create(
    'Zig Language for Systems Programming',
    "# Why Zig?\n\nZig is a **general-purpose** programming language designed for *robustness* and *performance*.\n\n## Key Points\n\n1. No hidden control flow\n2. No hidden memory allocation\n3. Manual memory management\n\n> Zig competes with C rather than Rust.",
    $editor->id,
    'published'
);
$article2->attachTag($tagZig->id);
echo "  Article 2: {$article2->title} (id={$article2->id})\n";

$article3 = Article::create(
    'Web Development Best Practices',
    "Best practices for modern web development.\n\n- Use HTTPS\n- Validate input\n- Sanitize output\n- Use CSP headers",
    $author->id,
    'draft'
);
$article3->attachTag($tagWeb->id);
echo "  Article 3: {$article3->title} (id={$article3->id}, status=draft)\n";

// === 文章列表与分页 ===
echo "\n--- Published Articles (Page 1) ---\n";
$published = Article::published(1, 10);
echo "  Total published: " . count($published) . "\n";
foreach ($published as $art) {
    echo "  [{$art->id}] {$art->title} by {$art->author()?->name} (views: {$art->views})\n";
    $tags = $art->tags();
    $tagNames = array_map(fn($t) => $t->name, $tags);
    echo "    Tags: " . implode(', ', $tagNames) . "\n";
}

// === 搜索 ===
echo "\n--- Search: 'PHP' ---\n";
$results = Article::search('PHP');
foreach ($results as $r) echo "  Found: [{$r->id}] {$r->title}\n";

echo "--- Search: 'Zig' ---\n";
$results = Article::search('Zig');
foreach ($results as $r) echo "  Found: [{$r->id}] {$r->title}\n";

// === Markdown 渲染 ===
echo "\n--- Markdown Rendering (Article 1) ---\n";
$html = $md->renderArticle($article1);
echo substr($html, 0, 300) . "...\n";

// === 评论系统（嵌套） ===
echo "\n--- Comments (Nested) ---\n";
$c1 = Comment::create($article1->id, $reader->id, 'Great article!');
$c2 = Comment::create($article1->id, $author->id, 'Thanks! I learned a lot.');
$c3 = Comment::create($article1->id, $admin->id, 'Glad you found it useful.', $c1->id); // 回复 c1
$c4 = Comment::create($article1->id, $editor->id, 'Could you add more examples?', $c2->id); // 回复 c2
$c5 = Comment::create($article1->id, $reader->id, 'Here is a nested reply.', $c3->id); // 回复 c3

$tree = Comment::getTree($article1->id);
echo "  Comment tree for article {$article1->id}:\n";
function printCommentTree(array $tree, int $depth = 0): void {
    foreach ($tree as $node) {
        $comment = $node['comment'];
        $author = $comment->author();
        $indent = str_repeat('  ', $depth + 2);
        echo "{$indent}[{$comment->id}] {$author?->name}: {$comment->content}\n";
        if (!empty($node['children'])) {
            printCommentTree($node['children'], $depth + 1);
        }
    }
}
printCommentTree($tree);

// === 浏览量 ===
echo "\n--- View Count ---\n";
$article1->incrementViews();
$article1->incrementViews();
$article1->incrementViews();
$refreshed = Article::find($article1->id);
echo "  Article 1 views: {$refreshed->views}\n";

// === 标签文章统计 ===
echo "\n--- Tag Statistics ---\n";
foreach (Tag::all() as $tag) {
    $tag->recalculateCount();
    echo "  {$tag->name} (slug: {$tag->slug}): {$tag->count} articles\n";
}

// === 作者文章列表 ===
echo "\n--- Articles by Admin ---\n";
$adminArticles = Article::byAuthor($admin->id);
foreach ($adminArticles as $a) echo "  [{$a->id}] {$a->title} ({$a->status})\n";

// === 更新文章 ===
echo "\n--- Update Article ---\n";
$article3->status = 'published';
$article3->save();
echo "  Article 3 status updated to: {$article3->status}\n";

// === 删除评论 ===
echo "\n--- Delete Comment (cascade) ---\n";
echo "  Before delete: " . BlogDB::getInstance()->count('comments', ['article_id' => $article1->id]) . " comments\n";
$c1->delete(); // Should cascade delete c3 and c5
echo "  After deleting comment {$c1->id}: " . BlogDB::getInstance()->count('comments', ['article_id' => $article1->id]) . " comments\n";

// === 删除文章 ===
echo "\n--- Delete Article ---\n";
$article3->delete();
echo "  Article 3 deleted. Remaining articles: " . BlogDB::getInstance()->count('articles') . "\n";
echo "  Comments for article 3: " . BlogDB::getInstance()->count('comments', ['article_id' => $article3->id]) . "\n";

// === 用户管理 ===
echo "\n--- User Management ---\n";
$reader->status = 'banned';
$reader->save();
$refreshedReader = BlogUser::find($reader->id);
echo "  Reader status: {$refreshedReader->status}\n";

$allUsers = BlogUser::all();
echo "  Total users: " . count($allUsers) . "\n";
foreach ($allUsers as $u) echo "    [{$u->id}] {$u->name} ({$u->role}) - {$u->status}\n";

// === 数据库统计 ===
echo "\n=== Database Statistics ===\n";
echo "  Users: " . BlogDB::getInstance()->count('users') . "\n";
echo "  Articles: " . BlogDB::getInstance()->count('articles') . "\n";
echo "  Comments: " . BlogDB::getInstance()->count('comments') . "\n";
echo "  Tags: " . BlogDB::getInstance()->count('tags') . "\n";
echo "  Article-Tag links: " . BlogDB::getInstance()->count('article_tags') . "\n";

echo "\n============================================\n";
echo "Blog System Test Complete\n";
echo "============================================\n";
