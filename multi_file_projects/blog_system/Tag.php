<?php
// 博客系统 - 标签系统
class Tag {
    public ?int $id = null;
    public string $name;
    public string $slug;
    public string $description;
    public int $count = 0;

    public function __construct(array $data = []) {
        foreach ($data as $key => $value) {
            if (property_exists($this, $key)) $this->$key = $value;
        }
        if (!isset($this->description)) $this->description = '';
    }

    public static function create(string $name, string $description = ''): self {
        $slug = self::slugify($name);
        $tag = new self(['name' => $name, 'slug' => $slug, 'description' => $description]);
        $id = BlogDB::getInstance()->insert('tags', [
            'name' => $tag->name,
            'slug' => $tag->slug,
            'description' => $tag->description,
            'count' => 0,
        ]);
        $tag->id = $id;
        return $tag;
    }

    public static function find(int $id): ?self {
        $row = BlogDB::getInstance()->selectOne('tags', ['id' => $id]);
        return $row ? new self($row) : null;
    }

    public static function findBySlug(string $slug): ?self {
        $row = BlogDB::getInstance()->selectOne('tags', ['slug' => $slug]);
        return $row ? new self($row) : null;
    }

    public static function all(): array {
        $rows = BlogDB::getInstance()->select('tags', [], null, 0, 'name', 'ASC');
        return array_map(fn($r) => new self($r), $rows);
    }

    public function articles(): array {
        $articleTags = BlogDB::getInstance()->select('article_tags', ['tag_id' => $this->id]);
        $articleIds = array_column($articleTags, 'article_id');
        if (empty($articleIds)) return [];
        $articles = BlogDB::getInstance()->select('articles', ['id' => $articleIds]);
        return array_map(fn($r) => new Article($r), $articles);
    }

    public function recalculateCount(): void {
        $this->count = count($this->articles());
        BlogDB::getInstance()->update('tags', ['id' => $this->id], ['count' => $this->count]);
    }

    public function delete(): void {
        BlogDB::getInstance()->delete('article_tags', ['tag_id' => $this->id]);
        BlogDB::getInstance()->delete('tags', ['id' => $this->id]);
    }

    public static function slugify(string $name): string {
        $slug = strtolower($name);
        $slug = preg_replace('/[^a-z0-9]+/', '-', $slug);
        $slug = trim($slug, '-');
        return $slug;
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'slug' => $this->slug,
            'description' => $this->description,
            'count' => $this->count,
        ];
    }
}
