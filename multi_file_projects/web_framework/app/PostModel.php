<?php
// 文章模型
class Post extends Model {
    protected string $table = 'posts';
    protected array $fillable = ['title', 'content', 'user_id', 'status', 'views'];
    protected array $casts = [
        'id' => 'integer',
        'user_id' => 'integer',
        'views' => 'integer',
    ];

    public function author(): ?User {
        return User::find($this->user_id);
    }

    public function comments(): array {
        return Comment::where('post_id', $this->id)->get();
    }

    public function incrementViews(): void {
        $this->views = ($this->views ?? 0) + 1;
        $this->save();
    }

    public function isPublished(): bool {
        return $this->status === 'published';
    }

    public function excerpt(int $length = 100): string {
        $content = $this->content ?? '';
        if (strlen($content) <= $length) return $content;
        return substr($content, 0, $length) . '...';
    }
}

// 评论模型
class Comment extends Model {
    protected string $table = 'comments';
    protected array $fillable = ['post_id', 'user_id', 'content', 'status'];
    protected array $casts = [
        'id' => 'integer',
        'post_id' => 'integer',
        'user_id' => 'integer',
    ];

    public function post(): ?Post {
        return Post::find($this->post_id);
    }

    public function author(): ?User {
        return User::find($this->user_id);
    }
}
