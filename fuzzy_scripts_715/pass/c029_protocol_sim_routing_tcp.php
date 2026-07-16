<?php
// 极度混搭: 网络协议模拟 + 数据包 + 路由表 + TCP握手 + 滑动窗口
echo "=== c029: Protocol Sim + Packet + Routing + TCP + SlidingWindow ===\n\n";

class Packet {
    public int $seq;
    public int $ack;
    public string $source;
    public string $dest;
    public string $payload;
    public int $flags;
    public int $ttl = 64;

    public const SYN = 1;
    public const ACK = 2;
    public const FIN = 4;
    public const RST = 8;
    public const PSH = 16;

    public function __construct(int $seq, int $ack, string $src, string $dst, string $payload = '', int $flags = 0) {
        $this->seq = $seq;
        $this->ack = $ack;
        $this->source = $src;
        $this->dest = $dst;
        $this->payload = $payload;
        $this->flags = $flags;
    }

    public function hasFlag(int $flag): bool {
        return ($this->flags & $flag) !== 0;
    }

    public function __toString(): string {
        $flagStr = [];
        if ($this->hasFlag(self::SYN)) $flagStr[] = 'SYN';
        if ($this->hasFlag(self::ACK)) $flagStr[] = 'ACK';
        if ($this->hasFlag(self::FIN)) $flagStr[] = 'FIN';
        if ($this->hasFlag(self::RST)) $flagStr[] = 'RST';
        if ($this->hasFlag(self::PSH)) $flagStr[] = 'PSH';
        return sprintf("Pkt[%s->%s] seq=%d ack=%d flags=[%s] ttl=%d payload=%s",
            $this->source, $this->dest, $this->seq, $this->ack,
            implode(",", $flagStr), $this->ttl,
            strlen($this->payload) > 0 ? strlen($this->payload) . 'B' : 'empty'
        );
    }
}

class RoutingTable {
    private array $routes = [];

    public function addRoute(string $network, string $gateway, int $metric = 1): void {
        $this->routes[$network] = ['gateway' => $gateway, 'metric' => $metric];
    }

    public function lookup(string $dest): ?string {
        // Simple matching: longest prefix
        $bestMatch = null;
        $bestLen = 0;
        foreach ($this->routes as $network => $route) {
            if (str_starts_with($dest, $network)) {
                $len = strlen($network);
                if ($len > $bestLen) {
                    $bestMatch = $route['gateway'];
                    $bestLen = $len;
                }
            }
        }
        return $bestMatch;
    }

    public function getRoutes(): array {
        return $this->routes;
    }
}

class TCPConnection {
    private string $localAddr;
    private string $remoteAddr;
    private int $seqNum;
    private int $ackNum;
    private string $state = 'CLOSED';
    private array $sendBuffer = [];
    private int $windowSize = 5;
    private int $base = 0;
    private int $nextSeq = 0;
    private array $unacked = [];

    public function __construct(string $local, string $remote) {
        $this->localAddr = $local;
        $this->remoteAddr = $remote;
        $this->seqNum = 1000;
        $this->ackNum = 0;
    }

    public function connect(): array {
        $packets = [];
        // SYN
        $syn = new Packet($this->seqNum, 0, $this->localAddr, $this->remoteAddr, '', Packet::SYN);
        $this->state = 'SYN_SENT';
        $this->seqNum++;
        $packets[] = $syn;

        // SYN-ACK (simulated)
        $synAck = new Packet(2000, $this->seqNum, $this->remoteAddr, $this->localAddr, '', Packet::SYN | Packet::ACK);
        $this->ackNum = 2001;
        $packets[] = $synAck;

        // ACK
        $ack = new Packet($this->seqNum, $this->ackNum, $this->localAddr, $this->remoteAddr, '', Packet::ACK);
        $this->state = 'ESTABLISHED';
        $packets[] = $ack;

        return $packets;
    }

    public function sendData(string $data): array {
        $packets = [];
        $chunkSize = 10;
        $chunks = str_split($data, $chunkSize);

        foreach ($chunks as $chunk) {
            if (count($this->unacked) >= $this->windowSize) {
                break; // Flow control
            }
            $pkt = new Packet(
                $this->seqNum,
                $this->ackNum,
                $this->localAddr,
                $this->remoteAddr,
                $chunk,
                Packet::PSH | Packet::ACK
            );
            $this->unacked[$this->seqNum] = $pkt;
            $this->seqNum += strlen($chunk);
            $packets[] = $pkt;
        }

        return $packets;
    }

    public function receiveAck(int $ackNum): void {
        foreach ($this->unacked as $seq => $pkt) {
            if ($seq < $ackNum) {
                unset($this->unacked[$seq]);
            }
        }
        $this->base = $ackNum;
    }

    public function close(): array {
        $packets = [];
        $fin = new Packet($this->seqNum, $this->ackNum, $this->localAddr, $this->remoteAddr, '', Packet::FIN | Packet::ACK);
        $this->state = 'FIN_WAIT';
        $packets[] = $fin;

        $finAck = new Packet($this->ackNum, $this->seqNum + 1, $this->remoteAddr, $this->localAddr, '', Packet::ACK);
        $this->state = 'CLOSED';
        $packets[] = $finAck;

        return $packets;
    }

    public function getState(): string { return $this->state; }
    public function getUnackedCount(): int { return count($this->unacked); }
    public function getWindowSize(): int { return $this->windowSize; }
}

// === 测试 ===

echo "--- TCP 3-Way Handshake ---\n";
$conn = new TCPConnection('10.0.0.1:8080', '10.0.0.2:443');
echo "State: " . $conn->getState() . "\n";
$handshake = $conn->connect();
foreach ($handshake as $pkt) {
    echo "  $pkt\n";
}
echo "State: " . $conn->getState() . "\n";

echo "\n--- Data Transfer (Sliding Window) ---\n";
$message = "Hello World! This is a test message for TCP sliding window protocol simulation.";
$dataPackets = $conn->sendData($message);
echo "Sent " . count($dataPackets) . " packets:\n";
foreach ($dataPackets as $pkt) {
    echo "  $pkt\n";
}
echo "Unacked: " . $conn->getUnackedCount() . "/" . $conn->getWindowSize() . "\n";

echo "\n--- Acknowledgment ---\n";
$conn->receiveAck(1011); // ACK first chunk
echo "After ACK 1011: Unacked=" . $conn->getUnackedCount() . "\n";
$conn->receiveAck(1021);
echo "After ACK 1021: Unacked=" . $conn->getUnackedCount() . "\n";

echo "\n--- Connection Close ---\n";
$closePackets = $conn->close();
foreach ($closePackets as $pkt) {
    echo "  $pkt\n";
}
echo "State: " . $conn->getState() . "\n";

echo "\n--- Routing Table ---\n";
$rt = new RoutingTable();
$rt->addRoute('10.0.0', '10.0.0.1', 1);
$rt->addRoute('10.0.0.0', '10.0.0.1', 1);
$rt->addRoute('192.168.1', '192.168.1.1', 2);
$rt->addRoute('172.16', '172.16.0.1', 3);
$rt->addRoute('', '0.0.0.0', 99); // Default route

$destinations = ['10.0.0.5', '192.168.1.100', '172.16.5.5', '8.8.8.8'];
foreach ($destinations as $dest) {
    $gateway = $rt->lookup($dest);
    echo "  $dest -> gateway: $gateway\n";
}

echo "\n--- Packet TTL Simulation ---\n";
$pkt = new Packet(1, 0, 'A', 'D', 'data', 0);
echo "Initial: $pkt\n";
for ($hop = 0; $hop < 5; $hop++) {
    $pkt->ttl--;
    if ($pkt->ttl <= 0) {
        echo "  TTL expired at hop $hop\n";
        break;
    }
    echo "  Hop $hop: TTL=$pkt->ttl\n";
}

echo "\n=== c029 Done ===\n";
