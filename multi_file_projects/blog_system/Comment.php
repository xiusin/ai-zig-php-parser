<?php
// 博客系统 - 评论（支持嵌套回复）
class Comment {
    public ?int $id = null;
    public int $articleId;
    public int $userId;
    public string $content;
    public ?int $parentId = null; // 嵌套评论
    public string $status; // approved, pending, spam
    public string $createdAt;

    public function __construct(array $data = []) {
        foreach ($data as $key => $value) {
            $camelKey = str_replace('_', '', lcfirst(ucwords($key, '_')));
            if (property_exists($this, $camelKey)) {
                $this->$camelKey = $value;
            } elseif (property_exists($this, $key)) {
                $this->$key = $value;
            }
        }
        if (!isset($this->createdAt)) $this->createdAt = date('Y-m-d H:i:s');
        if (!isset($this->status)) $this->status = 'approved';
    }

    public static function create(int $articleId, int $userId, string $content, ?int $parentId = null): self {
        $comment = new self([
            'article_id' => $articleId,
            'user_id' => $userId,
            'content' => $content,
            'parent_id' => $parentId,
            'status' => 'approved',
        ]);
        $id = BlogDB::getInstance()->insert('comments', [
            'article_id' => $comment->articleId,
            'user_id' => $comment->userId,
            'content' => $comment->content,
            'parent_id' => $comment->parentId,
            'status' => $comment->status,
            'created_at' => $comment->createdAt,
        ]);
        $comment->id = $id;
        return $comment;
    }

    public static function find(int $id): ?self {
        $row = BlogDB::getInstance()->selectOne('comments', ['id' => $id]);
        return $row ? new self($row) : null;
    }

    public function author(): ?BlogUser {
        return BlogUser::find($this->userId);
    }

    public function article(): ?Article {
        return Article::find($this->articleId);
    }

    public function replies(): array {
        $rows = BlogDB::getInstance()->select('comments', ['parent_id' => $this->id], null, 0, 'id', 'ASC');
        return array_map(fn($r) => new self($r), $rows);
    }

    public function isReply(): bool {
        return $this->parentId !== null;
    }

    public function approve(): void {
        $this->status = 'approved';
        BlogDB::getInstance()->update('comments', ['id' => $this->id], ['status' => 'approved']);
    }

    public function markSpam(): void {
        $this->status = 'spam';
        BlogDB::getInstance()->update('comments', ['id' => $this->id], ['status' => 'spam']);
    }

    public function delete(): void {
        // 递归删除子评论
        $replies = $this->replies();
        foreach ($replies as $reply) $reply->delete();
        BlogDB::getInstance()->delete('comments', ['id' => $this->id]);
    }

    // 获取文章的评论树
    public static function getTree(int $articleId): array {
        $allComments = BlogDB::getInstance()->select('comments', ['article_id' => $articleId, 'status' => 'approved'], null, 0, 'id', 'ASC');
        $comments = array_map(fn($r) => new self($r), $allComments);
        return self::buildTree($comments, null);
    }

    private static function buildTree(array $comments, ?int $parentId): array {
        $tree = [];
        foreach ($comments as $comment) {
            if ($comment->parentId === $parentId) {
                $children = self::buildTree($comments, $comment->id);
                $tree[] = [
                    'comment' => $comment,
                    'children' => $children,
                ];
            }
        }
        return $tree;
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'article_id' => $this->articleId,
            'user_id' => $this->userId,
            'content' => $this->content,
            'parent_id' => $this->parentId,
            'status' => $this->status,
            'created_at' => $this->createdAt,
        ];
    }
}
