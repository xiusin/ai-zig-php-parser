<?php
// HTTP 响应对象
class Response {
    public int $status = 200;
    public string $body = '';
    public array $headers = [];
    private static array $statusTexts = [
        200 => 'OK', 201 => 'Created', 204 => 'No Content',
        301 => 'Moved Permanently', 302 => 'Found', 304 => 'Not Modified',
        400 => 'Bad Request', 401 => 'Unauthorized', 403 => 'Forbidden',
        404 => 'Not Found', 405 => 'Method Not Allowed', 409 => 'Conflict',
        422 => 'Unprocessable Entity', 500 => 'Internal Server Error',
    ];

    public function __construct(int $status = 200, string $body = '', array $headers = []) {
        $this->status = $status;
        $this->body = $body;
        $this->headers = $headers;
    }

    public static function make(int $status = 200, string $body = ''): self {
        return new self($status, $body);
    }

    public static function json(mixed $data, int $status = 200): self {
        $res = new self($status);
        $res->body = json_encode($data);
        $res->headers['Content-Type'] = 'application/json';
        return $res;
    }

    public static function html(string $body, int $status = 200): self {
        $res = new self($status, $body);
        $res->headers['Content-Type'] = 'text/html; charset=utf-8';
        return $res;
    }

    public static function text(string $body, int $status = 200): self {
        return new self($status, $body);
    }

    public static function redirect(string $url, int $status = 302): self {
        $res = new self($status);
        $res->headers['Location'] = $url;
        return $res;
    }

    public function withHeader(string $name, string $value): self {
        $this->headers[$name] = $value;
        return $this;
    }

    public function withHeaders(array $headers): self {
        $this->headers = array_merge($this->headers, $headers);
        return $this;
    }

    public function getStatusText(): string {
        return self::$statusTexts[$this->status] ?? 'Unknown';
    }

    public function send(): void {
        echo "HTTP/{$this->status} {$this->getStatusText()}\n";
        foreach ($this->headers as $name => $value) {
            echo "$name: $value\n";
        }
        echo "\n";
        echo $this->body;
    }
}
