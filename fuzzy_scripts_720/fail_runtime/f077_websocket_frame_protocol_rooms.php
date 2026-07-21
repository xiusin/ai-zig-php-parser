<?php
// 极度混搭: WebSocket帧解析 + 协议处理 + 消息广播 + 房间管理
echo "=== f077: WebSocket Frame + Protocol + Broadcast + Rooms ===\n";

class WebSocketFrame {
    public bool $fin;
    public int $opcode;
    public bool $masked;
    public string $payload;
    public int $payloadLen;

    public function __construct(bool $fin, int $opcode, string $payload, bool $masked = false) {
        $this->fin = $fin;
        $this->opcode = $opcode;
        $this->payload = $payload;
        $this->masked = $masked;
        $this->payloadLen = strlen($payload);
    }

    public function encode(): string {
        $bytes = '';
        // First byte: FIN + RSV + Opcode
        $firstByte = ($this->fin ? 0x80 : 0) | ($this->opcode & 0x0F);
        $bytes .= chr($firstByte);

        // Second byte: MASK + Payload length
        $maskBit = $this->masked ? 0x80 : 0;
        if ($this->payloadLen < 126) {
            $bytes .= chr($maskBit | $this->payloadLen);
        } elseif ($this->payloadLen < 65536) {
            $bytes .= chr($maskBit | 126);
            $bytes .= pack('n', $this->payloadLen);
        } else {
            $bytes .= chr($maskBit | 127);
            $bytes .= pack('J', $this->payloadLen);
        }

        // Masking key + masked payload
        if ($this->masked) {
            $maskKey = random_bytes(4);
            $bytes .= $maskKey;
            $masked = '';
            for ($i = 0; $i < $this->payloadLen; $i++) {
                $masked .= chr(ord($this->payload[$i]) ^ ord($maskKey[$i % 4]));
            }
            $bytes .= $masked;
        } else {
            $bytes .= $this->payload;
        }
        return $bytes;
    }

    public static function decode(string $data): self {
        $pos = 0;
        $firstByte = ord($data[$pos++]);
        $fin = ($firstByte & 0x80) !== 0;
        $opcode = $firstByte & 0x0F;

        $secondByte = ord($data[$pos++]);
        $masked = ($secondByte & 0x80) !== 0;
        $payloadLen = $secondByte & 0x7F;

        if ($payloadLen === 126) {
            $payloadLen = unpack('n', substr($data, $pos, 2))[1];
            $pos += 2;
        } elseif ($payloadLen === 127) {
            $payloadLen = unpack('J', substr($data, $pos, 8))[1];
            $pos += 8;
        }

        $maskKey = '';
        if ($masked) {
            $maskKey = substr($data, $pos, 4);
            $pos += 4;
        }

        $payload = substr($data, $pos, $payloadLen);
        if ($masked) {
            $unmasked = '';
            for ($i = 0; $i < $payloadLen; $i++) {
                $unmasked .= chr(ord($payload[$i]) ^ ord($maskKey[$i % 4]));
            }
            $payload = $unmasked;
        }

        return new self($fin, $opcode, $payload, $masked);
    }

    public function isText(): bool { return $this->opcode === 0x01; }
    public function isBinary(): bool { return $this->opcode === 0x02; }
    public function isClose(): bool { return $this->opcode === 0x08; }
    public function isPing(): bool { return $this->opcode === 0x09; }
    public function isPong(): bool { return $this->opcode === 0x0A; }
}

class WSServer {
    private array $clients = []; // id → info
    private array $rooms = []; // room → [clientIds]
    private array $messages = [];

    public function connect(int $clientId, string $name): void {
        $this->clients[$clientId] = ['name' => $name, 'rooms' => []];
        $this->broadcast("System: $name joined", exclude: $clientId);
        $this->messages[] = ['type' => 'connect', 'client' => $clientId, 'name' => $name];
    }

    public function disconnect(int $clientId): void {
        $name = $this->clients[$clientId]['name'] ?? 'unknown';
        foreach ($this->clients[$clientId]['rooms'] ?? [] as $room) {
            $this->leaveRoom($clientId, $room);
        }
        unset($this->clients[$clientId]);
        $this->broadcast("System: $name left");
        $this->messages[] = ['type' => 'disconnect', 'client' => $clientId, 'name' => $name];
    }

    public function joinRoom(int $clientId, string $room): void {
        if (!isset($this->rooms[$room])) $this->rooms[$room] = [];
        $this->rooms[$room][] = $clientId;
        $this->clients[$clientId]['rooms'][] = $room;
        $this->broadcastToRoom($room, "System: {$this->clients[$clientId]['name']} joined room $room", exclude: $clientId);
    }

    public function leaveRoom(int $clientId, string $room): void {
        if (isset($this->rooms[$room])) {
            $this->rooms[$room] = array_diff($this->rooms[$room], [$clientId]);
            if (empty($this->rooms[$room])) unset($this->rooms[$room]);
        }
        if (isset($this->clients[$clientId]['rooms'])) {
            $this->clients[$clientId]['rooms'] = array_diff($this->clients[$clientId]['rooms'], [$room]);
        }
    }

    public function sendMessage(int $clientId, string $message): void {
        $name = $this->clients[$clientId]['name'] ?? 'unknown';
        $this->broadcast("$name: $message", exclude: $clientId);
        $this->messages[] = ['type' => 'message', 'client' => $clientId, 'name' => $name, 'text' => $message];
    }

    public function sendToRoom(int $clientId, string $room, string $message): void {
        $name = $this->clients[$clientId]['name'] ?? 'unknown';
        $this->broadcastToRoom($room, "[$room] $name: $message", exclude: $clientId);
    }

    private function broadcast(string $message, ?int $exclude = null): void {
        foreach ($this->clients as $id => $client) {
            if ($id !== $exclude) {
                // 模拟发送
            }
        }
        $this->messages[] = ['type' => 'broadcast', 'text' => $message];
    }

    private function broadcastToRoom(string $room, string $message, ?int $exclude = null): void {
        foreach ($this->rooms[$room] ?? [] as $id) {
            if ($id !== $exclude) {
                // 模拟发送
            }
        }
        $this->messages[] = ['type' => 'room_broadcast', 'room' => $room, 'text' => $message];
    }

    public function getRooms(): array { return array_keys($this->rooms); }
    public function getRoomClients(string $room): array { return $this->rooms[$room] ?? []; }
    public function getClientCount(): int { return count($this->clients); }
    public function getMessages(): array { return $this->messages; }
}

// 测试
echo "--- WebSocket Frame Encode/Decode ---\n";
$tests = [
    ['fin' => true, 'opcode' => 0x01, 'payload' => 'Hello'],
    ['fin' => true, 'opcode' => 0x01, 'payload' => str_repeat('A', 200)],
    ['fin' => true, 'opcode' => 0x02, 'payload' => 'binary data'],
    ['fin' => true, 'opcode' => 0x09, 'payload' => 'ping'],
    ['fin' => true, 'opcode' => 0x08, 'payload' => ''],
];
foreach ($tests as $t) {
    $frame = new WebSocketFrame($t['fin'], $t['opcode'], $t['payload'], true);
    $encoded = $frame->encode();
    $decoded = WebSocketFrame::decode($encoded);
    $match = $decoded->payload === $t['payload'] && $decoded->opcode === $t['opcode'] && $decoded->fin === $t['fin'];
    $type = match($t['opcode']) {0x01 => 'text', 0x02 => 'binary', 0x08 => 'close', 0x09 => 'ping', default => 'unknown'};
    echo "  $type (len=" . strlen($t['payload']) . ") → encoded " . strlen($encoded) . " bytes, match=" . var_export($match, true) . "\n";
}

echo "\n--- WebSocket Server ---\n";
$server = new WSServer();
$server->connect(1, 'Alice');
$server->connect(2, 'Bob');
$server->connect(3, 'Charlie');
echo "Clients: " . $server->getClientCount() . "\n";

$server->sendMessage(1, 'Hi everyone!');
$server->sendMessage(2, 'Hey Alice!');

echo "\n--- Rooms ---\n";
$server->joinRoom(1, 'gaming');
$server->joinRoom(2, 'gaming');
$server->joinRoom(3, 'coding');
echo "Rooms: " . json_encode($server->getRooms()) . "\n";
echo "Gaming room: " . json_encode($server->getRoomClients('gaming')) . "\n";
echo "Coding room: " . json_encode($server->getRoomClients('coding')) . "\n";

$server->sendToRoom(1, 'gaming', 'Anyone want to play?');
$server->sendToRoom(3, 'coding', 'Need help with PHP?');

echo "\n--- Disconnect ---\n";
$server->disconnect(2);
echo "Clients: " . $server->getClientCount() . "\n";
echo "Gaming room after Bob left: " . json_encode($server->getRoomClients('gaming')) . "\n";

echo "\n--- Message Log ---\n";
foreach ($server->getMessages() as $msg) {
    echo "  " . json_encode($msg) . "\n";
}

echo "=== f077 Done ===\n";
