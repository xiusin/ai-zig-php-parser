<?php
// 内存池与对象池：减少 GC 压力、复用对象
echo "=== f172: Memory Pool + Object Pool + Buffer ===\n";

class ObjectPool {
    private array $pool = [];
    private int $created = 0;
    private int $reused = 0;
    private int $maxSize;
    private string $factory;

    public function __construct(string $factory, int $maxSize = 100) {
        $this->factory = $factory;
        $this->maxSize = $maxSize;
    }

    public function acquire(): object {
        if (!empty($this->pool)) {
            $this->reused++;
            return array_pop($this->pool);
        }
        $this->created++;
        $class = $this->factory;
        return new $class();
    }

    public function release(object $obj): void {
        if (count($this->pool) < $this->maxSize) {
            if (method_exists($obj, 'reset')) $obj->reset();
            $this->pool[] = $obj;
        }
    }

    public function getStats(): array {
        return [
            'created' => $this->created,
            'reused' => $this->reused,
            'in_pool' => count($this->pool),
            'max_size' => $this->maxSize,
        ];
    }
}

class PooledBuffer {
    public string $data = '';
    public int $size = 0;

    public function write(string $content): void {
        $this->data .= $content;
        $this->size = strlen($this->data);
    }

    public function clear(): void {
        $this->data = '';
        $this->size = 0;
    }

    public function reset(): void {
        $this->clear();
    }

    public function read(): string {
        return $this->data;
    }

    public function capacity(): int {
        return $this->size;
    }
}

class PooledRequest {
    public string $method = 'GET';
    public string $url = '';
    public array $headers = [];
    public ?string $body = null;
    public int $timeout = 30;

    public function reset(): void {
        $this->method = 'GET';
        $this->url = '';
        $this->headers = [];
        $this->body = null;
        $this->timeout = 30;
    }

    public function setMethod(string $m): self { $this->method = $m; return $this; }
    public function setUrl(string $u): self { $this->url = $u; return $this; }
    public function setBody(?string $b): self { $this->body = $b; return $this; }
    public function setHeader(string $k, string $v): self { $this->headers[$k] = $v; return $this; }
    public function setTimeout(int $t): self { $this->timeout = $t; return $this; }

    public function execute(): array {
        return [
            'method' => $this->method,
            'url' => $this->url,
            'headers' => $this->headers,
            'has_body' => $this->body !== null,
            'timeout' => $this->timeout,
            'status' => 200,
            'response' => "OK",
        ];
    }
}

// 字节缓冲区
class ByteBuffer {
    private string $buffer = '';
    private int $position = 0;
    private bool $bigEndian = true;

    public function writeByte(int $byte): void {
        $this->buffer .= chr($byte & 0xFF);
    }

    public function writeBytes(string $data): void {
        $this->buffer .= $data;
    }

    public function writeInt(int $value, int $bytes = 4): void {
        for ($i = $bytes - 1; $i >= 0; $i--) {
            if ($this->bigEndian) {
                $this->buffer .= chr(($value >> ($i * 8)) & 0xFF);
            } else {
                $this->buffer .= chr(($value >> (($bytes - 1 - $i) * 8)) & 0xFF);
            }
        }
    }

    public function writeString(string $str): void {
        $len = strlen($str);
        $this->writeInt($len, 4);
        $this->buffer .= $str;
    }

    public function writeFloat(float $value): void {
        $this->buffer .= pack('G', $value); // IEEE 754 big-endian
    }

    public function readByte(): int {
        if ($this->position >= strlen($this->buffer)) return 0;
        return ord($this->buffer[$this->position++]);
    }

    public function readInt(int $bytes = 4): int {
        $value = 0;
        for ($i = 0; $i < $bytes; $i++) {
            $value = ($value << 8) | $this->readByte();
        }
        return $value;
    }

    public function readString(): string {
        $len = $this->readInt(4);
        $str = substr($this->buffer, $this->position, $len);
        $this->position += $len;
        return $str;
    }

    public function remaining(): int {
        return strlen($this->buffer) - $this->position;
    }

    public function rewind(): void { $this->position = 0; }
    public function clear(): void { $this->buffer = ''; $this->position = 0; }
    public function toString(): string { return $this->buffer; }
    public function length(): int { return strlen($this->buffer); }
}

// 测试
echo "--- Object Pool (Buffer) ---\n";
$pool = new ObjectPool(PooledBuffer::class, 10);

$buffers = [];
for ($i = 0; $i < 5; $i++) {
    $buf = $pool->acquire();
    $buf->write("Buffer $i content with data " . str_repeat('x', 20));
    $buffers[] = $buf;
}

echo "  After acquiring 5 buffers:\n";
$stats = $pool->getStats();
echo "    Created: {$stats['created']}, Reused: {$stats['reused']}, In pool: {$stats['in_pool']}\n";

foreach ($buffers as $buf) {
    $pool->release($buf);
}

echo "  After releasing 5 buffers:\n";
$stats = $pool->getStats();
echo "    Created: {$stats['created']}, Reused: {$stats['reused']}, In pool: {$stats['in_pool']}\n";

$buf1 = $pool->acquire();
$buf2 = $pool->acquire();
echo "  After acquiring 2 more (should be reused):\n";
$stats = $pool->getStats();
echo "    Created: {$stats['created']}, Reused: {$stats['reused']}, In pool: {$stats['in_pool']}\n";
echo "  Buffer 1 is empty: " . ($buf1->read() === '' ? 'Y' : 'N') . " (reset on release)\n";

$pool->release($buf1);
$pool->release($buf2);

echo "\n--- Object Pool (Request) ---\n";
$reqPool = new ObjectPool(PooledRequest::class, 20);

$requests = [];
for ($i = 0; $i < 10; $i++) {
    $req = $reqPool->acquire();
    $req->setMethod('POST')
        ->setUrl("/api/items/$i")
        ->setBody('{"name":"item' . $i . '"}')
        ->setHeader('Content-Type', 'application/json');
    $requests[] = $req;
}

echo "  10 requests created:\n";
$stats = $reqPool->getStats();
echo "    Created: {$stats['created']}, Reused: {$stats['reused']}\n";

foreach ($requests as $req) {
    $response = $req->execute();
    echo "    {$response['method']} {$response['url']} → {$response['status']}\n";
    $reqPool->release($req);
}

// 复用
$req2 = $reqPool->acquire();
echo "  Reuse check - method should be GET: {$req2->method}\n";
$stats = $reqPool->getStats();
echo "    Created: {$stats['created']}, Reused: {$stats['reused']}\n";
$reqPool->release($req2);

echo "\n--- Byte Buffer ---\n";
$bb = new ByteBuffer();
$bb->writeByte(0x41); // 'A'
$bb->writeByte(0x42); // 'B'
$bb->writeInt(123456, 4);
$bb->writeString('Hello World');
$bb->writeFloat(3.14159);

echo "  Buffer length: " . $bb->length() . " bytes\n";
echo "  Hex: " . bin2hex($bb->toString()) . "\n";

$bb->rewind();
echo "  Read byte: " . chr($bb->readByte()) . "\n";
echo "  Read byte: " . chr($bb->readByte()) . "\n";
echo "  Read int: " . $bb->readInt(4) . "\n";
echo "  Read string: " . $bb->readString() . "\n";
echo "  Remaining: " . $bb->remaining() . " bytes\n";

echo "\n--- Pool Statistics ---\n";
echo "  Buffer pool: " . json_encode($pool->getStats()) . "\n";
echo "  Request pool: " . json_encode($reqPool->getStats()) . "\n";

echo "=== f172 Done ===\n";
