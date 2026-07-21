<?php
// 博客系统 - 文章模型
class Article {
    public ?int $id = null;
    public string $title;
    public string $content;
    public string $excerpt;
    public int $authorId;
    public string $status; // draft, published, archived
    public int $views;
    public string $createdAt;
    public string $updatedAt;

    public function __construct(array $data = []) {
        foreach ($data as $key => $value) {
            $camelKey = str_replace('_', '', lcfirst(ucwords($key, '_')));
            if (property_exists($this, $camelKey)) {
                $this->$camelKey = $value;
            } elseif (property_exists($this, $key)) {
                $this->$key = $value;
            }
        }
        $now = date('Y-m-d H:i:s');
        if (!isset($this->createdAt)) $this->createdAt = $now;
        if (!isset($this->updatedAt)) $this->updatedAt = $now;
        if (!isset($this->views)) $this->views = 0;
    }

    public static function create(string $title, string $content, int $authorId, string $status = 'draft'): self {
        $article = new self([
            'title' => $title,
            'content' => $content,
            'excerpt' => self::makeExcerpt($content),
            'author_id' => $authorId,
            'status' => $status,
            'views' => 0,
        ]);
        $id = BlogDB::getInstance()->insert('articles', [
            'title' => $article->title,
            'content' => $article->content,
            'excerpt' => $article->excerpt,
            'author_id' => $article->authorId,
            'status' => $article->status,
            'views' => $article->views,
            'created_at' => $article->createdAt,
            'updated_at' => $article->updatedAt,
        ]);
        $article->id = $id;
        return $article;
    }

    public static function find(int $id): ?self {
        $row = BlogDB::getInstance()->selectOne('articles', ['id' => $id]);
        return $row ? new self($row) : null;
    }

    public static function published(int $page = 1, int $perPage = 10): array {
        $offset = ($page - 1) * $perPage;
        $rows = BlogDB::getInstance()->select('articles', ['status' => 'published'], $perPage, $offset, 'id', 'DESC');
        return array_map(fn($r) => new self($r), $rows);
    }

    public static function byAuthor(int $authorId): array {
        $rows = BlogDB::getInstance()->select('articles', ['author_id' => $authorId], null, 0, 'id', 'DESC');
        return array_map(fn($r) => new self($r), $rows);
    }

    public static function search(string $keyword): array {
        $all = BlogDB::getInstance()->select('articles', ['status' => 'published']);
        $results = [];
        foreach ($all as $row) {
            if (stripos($row['title'], $keyword) !== false || stripos($row['content'], $keyword) !== false) {
                $results[] = new self($row);
            }
        }
        return $results;
    }

    public function save(): void {
        $this->excerpt = self::makeExcerpt($this->content);
        $this->updatedAt = date('Y-m-d H:i:s');
        BlogDB::getInstance()->update('articles', ['id' => $this->id], [
            'title' => $this->title,
            'content' => $this->content,
            'excerpt' => $this->excerpt,
            'status' => $this->status,
            'updated_at' => $this->updatedAt,
        ]);
    }

    public function delete(): void {
        BlogDB::getInstance()->delete('articles', ['id' => $this->id]);
        BlogDB::getInstance()->delete('comments', ['article_id' => $this->id]);
        BlogDB::getInstance()->delete('article_tags', ['article_id' => $this->id]);
    }

    public function incrementViews(): void {
        $this->views++;
        BlogDB::getInstance()->update('articles', ['id' => $this->id], ['views' => $this->views]);
    }

    public function author(): ?BlogUser {
        return BlogUser::find($this->authorId);
    }

    public function comments(): array {
        $rows = BlogDB::getInstance()->select('comments', ['article_id' => $this->id], null, 0, 'id', 'ASC');
        return array_map(fn($r) => new Comment($r), $rows);
    }

    public function tags(): array {
        $articleTags = BlogDB::getInstance()->select('article_tags', ['article_id' => $this->id]);
        $tagIds = array_column($articleTags, 'tag_id');
        if (empty($tagIds)) return [];
        $tags = BlogDB::getInstance()->select('tags', ['id' => $tagIds]);
        return array_map(fn($r) => new Tag($r), $tags);
    }

    public function attachTag(int $tagId): void {
        $existing = BlogDB::getInstance()->selectOne('article_tags', ['article_id' => $this->id, 'tag_id' => $tagId]);
        if (!$existing) {
            BlogDB::getInstance()->insert('article_tags', ['article_id' => $this->id, 'tag_id' => $tagId]);
        }
    }

    public function detachTag(int $tagId): void {
        BlogDB::getInstance()->delete('article_tags', ['article_id' => $this->id, 'tag_id' => $tagId]);
    }

    public static function makeExcerpt(string $content, int $length = 150): string {
        $plain = strip_tags($content);
        if (strlen($plain) <= $length) return $plain;
        return substr($plain, 0, $length) . '...';
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'content' => $this->content,
            'excerpt' => $this->excerpt,
            'author_id' => $this->authorId,
            'status' => $this->status,
            'views' => $this->views,
            'created_at' => $this->createdAt,
            'updated_at' => $this->updatedAt,
        ];
    }
}
