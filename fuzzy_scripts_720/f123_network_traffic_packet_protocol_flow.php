<?php
// 极度混搭: 网络流量分析 + 数据包 + 协议解析 + 流重组
echo "=== f123: Network Traffic + Packet + Protocol + FlowReassembly ===\n";

class NetworkPacket {
    public function __construct(
        public int $seq,
        public string $srcIP,
        public string $dstIP,
        public int $srcPort,
        public int $dstPort,
        public string $protocol,
        public string $payload,
        public float $timestamp = 0,
        public int $flags = 0
    ) {
        if ($this->timestamp === 0) $this->timestamp = microtime(true);
    }
    public function isSyn(): bool { return ($this->flags & 1) !== 0; }
    public function isAck(): bool { return ($this->flags & 2) !== 0; }
    public function isFin(): bool { return ($this->flags & 4) !== 0; }
    public function getPayloadSize(): int { return strlen($this->payload); }
    public function getFlowKey(): string { return "{$this->srcIP}:{$this->srcPort}->{$this->dstIP}:{$this->dstPort}:{$this->protocol}"; }
}

class NetworkFlow {
    public array $packets = [];
    public int $totalBytes = 0;
    public float $startTime = 0;
    public float $endTime = 0;
    public string $state = 'new';
    public array $reassembled = [];

    public function addPacket(NetworkPacket $pkt): void {
        $this->packets[] = $pkt;
        $this->totalBytes += $pkt->getPayloadSize();
        if ($this->startTime === 0) $this->startTime = $pkt->timestamp;
        $this->endTime = $pkt->timestamp;
        $this->updateState($pkt);
        $this->reassembled[] = $pkt->payload;
    }

    private function updateState(NetworkPacket $pkt): void {
        if ($pkt->isSyn() && !$pkt->isAck()) $this->state = 'syn_sent';
        elseif ($pkt->isSyn() && $pkt->isAck()) $this->state = 'syn_ack';
        elseif ($pkt->isAck() && $this->state === 'syn_ack') $this->state = 'established';
        elseif ($pkt->isFin()) $this->state = 'closing';
        elseif ($this->state === 'closing' && $pkt->isAck()) $this->state = 'closed';
    }

    public function getDuration(): float { return $this->endTime - $this->startTime; }
    public function getReassembledData(): string { return implode('', $this->reassembled); }
    public function getPacketCount(): int { return count($this->packets); }
}

class FlowTable {
    private array $flows = [];
    private array $stats = ['total_packets' => 0, 'total_bytes' => 0, 'flows_created' => 0, 'flows_closed' => 0];

    public function processPacket(NetworkPacket $pkt): void {
        $key = $pkt->getFlowKey();
        $reverseKey = "{$pkt->dstIP}:{$pkt->dstPort}->{$pkt->srcIP}:{$pkt->srcPort}:{$pkt->protocol}";
        if (isset($this->flows[$key])) {
            $this->flows[$key]->addPacket($pkt);
        } elseif (isset($this->flows[$reverseKey])) {
            $this->flows[$reverseKey]->addPacket($pkt);
        } else {
            $flow = new NetworkFlow();
            $flow->addPacket($pkt);
            $this->flows[$key] = $flow;
            $this->stats['flows_created']++;
        }
        $this->stats['total_packets']++;
        $this->stats['total_bytes'] += $pkt->getPayloadSize();
        if ($this->flows[$key] ?? $this->flows[$reverseKey] ?? null) {
            $flow = $this->flows[$key] ?? $this->flows[$reverseKey];
            if ($flow->state === 'closed') $this->stats['flows_closed']++;
        }
    }

    public function getFlows(): array { return $this->flows; }
    public function getStats(): array { return $this->stats; }
    public function getFlowCount(): int { return count($this->flows); }
}

class ProtocolParser {
    public static function parseHTTP(string $data): array {
        $lines = explode("\r\n", $data);
        $firstLine = $lines[0] ?? '';
        $headers = [];
        $body = '';
        $bodyStarted = false;
        for ($i = 1; $i < count($lines); $i++) {
            if ($bodyStarted) { $body .= $lines[$i] . "\r\n"; continue; }
            if ($lines[$i] === '') { $bodyStarted = true; continue; }
            $colon = strpos($lines[$i], ':');
            if ($colon !== false) {
                $key = substr($lines[$i], 0, $colon);
                $value = trim(substr($lines[$i], $colon + 1));
                $headers[$key] = $value;
            }
        }
        $isRequest = str_starts_with($firstLine, 'GET') || str_starts_with($firstLine, 'POST') || str_starts_with($firstLine, 'PUT') || str_starts_with($firstLine, 'DELETE');
        $isResponse = str_starts_with($firstLine, 'HTTP/');
        $method = null; $path = null; $statusCode = null; $statusText = null;
        if ($isRequest) {
            $parts = explode(' ', $firstLine);
            $method = $parts[0] ?? ''; $path = $parts[1] ?? '';
        } elseif ($isResponse) {
            $parts = explode(' ', $firstLine, 3);
            $statusCode = (int)($parts[1] ?? 0);
            $statusText = $parts[2] ?? '';
        }
        return [
            'type' => $isRequest ? 'request' : ($isResponse ? 'response' : 'unknown'),
            'method' => $method, 'path' => $path,
            'statusCode' => $statusCode, 'statusText' => $statusText,
            'headers' => $headers, 'body' => trim($body),
        ];
    }

    public static function parseDNS(string $data): array {
        if (strlen($data) < 12) return ['error' => 'too short'];
        $id = (ord($data[0]) << 8) | ord($data[1]);
        $flags = (ord($data[2]) << 8) | ord($data[3]);
        $isResponse = ($flags & 0x8000) !== 0;
        $qdcount = (ord($data[4]) << 8) | ord($data[5]);
        $domain = '';
        $i = 12;
        while ($i < strlen($data) && ord($data[$i]) !== 0) {
            $len = ord($data[$i]);
            if ($len > 0) {
                if ($domain !== '') $domain .= '.';
                $domain .= substr($data, $i + 1, $len);
            }
            $i += $len + 1;
        }
        return ['id' => $id, 'isResponse' => $isResponse, 'questions' => $qdcount, 'domain' => $domain];
    }
}

class TrafficAnalyzer {
    private FlowTable $flowTable;
    private array $protocolStats = [];
    private array $topTalkers = [];

    public function __construct() { $this->flowTable = new FlowTable(); }

    public function analyze(array $packets): array {
        foreach ($packets as $pkt) {
            $this->flowTable->processPacket($pkt);
            $this->protocolStats[$pkt->protocol] = ($this->protocolStats[$pkt->protocol] ?? 0) + $pkt->getPayloadSize();
            $this->topTalkers[$pkt->srcIP] = ($this->topTalkers[$pkt->srcIP] ?? 0) + $pkt->getPayloadSize();
        }
        arsort($this->topTalkers);
        return $this->getReport();
    }

    public function getReport(): array {
        return [
            'flow_stats' => $this->flowTable->getStats(),
            'flow_count' => $this->flowTable->getFlowCount(),
            'protocol_distribution' => $this->protocolStats,
            'top_talkers' => array_slice($this->topTalkers, 0, 5, true),
        ];
    }
}

// 测试
echo "--- Generate Network Traffic ---\n";
$baseTime = 1000.0;
$packets = [
    // TCP Handshake
    new NetworkPacket(1, '192.168.1.10', '10.0.0.1', 54321, 80, 'TCP', '', $baseTime, 1),
    new NetworkPacket(2, '10.0.0.1', '192.168.1.10', 80, 54321, 'TCP', '', $baseTime + 0.01, 1 | 2),
    new NetworkPacket(3, '192.168.1.10', '10.0.0.1', 54321, 80, 'TCP', '', $baseTime + 0.02, 2),
    // HTTP Request (split across packets)
    new NetworkPacket(4, '192.168.1.10', '10.0.0.1', 54321, 80, 'TCP', 'GET /api/users HTT', $baseTime + 0.03, 2),
    new NetworkPacket(5, '192.168.1.10', '10.0.0.1', 54321, 80, 'TCP', "P/1.1\r\nHost: api.\r\n\r\n", $baseTime + 0.04, 2),
    // HTTP Response
    new NetworkPacket(6, '10.0.0.1', '192.168.1.10', 80, 54321, 'TCP', "HTTP/1.1 200 OK\r\n", $baseTime + 0.1, 2),
    new NetworkPacket(7, '10.0.0.1', '192.168.1.10', 80, 54321, 'TCP', "Content-Length: 13\r\n\r\nHello, World!", $baseTime + 0.11, 2),
    // FIN
    new NetworkPacket(8, '192.168.1.10', '10.0.0.1', 54321, 80, 'TCP', '', $baseTime + 0.2, 4),
    // UDP DNS
    new NetworkPacket(9, '192.168.1.10', '8.8.8.8', 12345, 53, 'UDP', "\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00", $baseTime + 0.3),
    // Another connection
    new NetworkPacket(10, '192.168.1.20', '10.0.0.2', 33333, 443, 'TCP', '', $baseTime + 0.5, 1),
    new NetworkPacket(11, '10.0.0.2', '192.168.1.20', 443, 33333, 'TCP', '', $baseTime + 0.51, 1 | 2),
];

echo "Packets: " . count($packets) . "\n";

echo "\n--- Traffic Analysis ---\n";
$analyzer = new TrafficAnalyzer();
$report = $analyzer->analyze($packets);
echo "Flow stats: " . json_encode($report['flow_stats']) . "\n";
echo "Flow count: {$report['flow_count']}\n";
echo "Protocol distribution: " . json_encode($report['protocol_distribution']) . "\n";
echo "Top talkers:\n";
foreach ($report['top_talkers'] as $ip => $bytes) echo "  $ip: $bytes bytes\n";

echo "\n--- Flow Details ---\n";
$flowTable = $analyzer->getFlows();
foreach ($flowTable as $key => $flow) {
    echo "Flow: $key\n";
    echo "  State: {$flow->state}\n";
    echo "  Packets: {$flow->getPacketCount()}\n";
    echo "  Bytes: {$flow->totalBytes}\n";
    echo "  Duration: " . number_format($flow->getDuration() * 1000, 1) . "ms\n";
    $data = $flow->getReassembledData();
    if (strlen($data) > 0) {
        echo "  Reassembled (" . strlen($data) . " bytes): " . substr($data, 0, 60) . (strlen($data) > 60 ? '...' : '') . "\n";
    }
}

echo "\n--- HTTP Protocol Parsing ---\n";
$httpRequest = "GET /api/users HTTP/1.1\r\nHost: api.example.com\r\nAccept: application/json\r\nUser-Agent: TestClient/1.0\r\n\r\n";
$parsed = ProtocolParser::parseHTTP($httpRequest);
echo "Request: " . json_encode($parsed, JSON_PRETTY_PRINT) . "\n";

$httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 25\r\n\r\n{\"users\": [\"alice\"]}";
$parsedResp = ProtocolParser::parseHTTP($httpResponse);
echo "Response: " . json_encode($parsedResp, JSON_PRETTY_PRINT) . "\n";

echo "\n--- Reassemble HTTP from fragments ---\n";
$flowTable = $analyzer->getFlows();
foreach ($flowTable as $key => $flow) {
    $data = $flow->getReassembledData();
    if (str_starts_with($data, 'GET') || str_starts_with($data, 'HTTP')) {
        echo "Flow $key contains HTTP:\n";
        $parsed = ProtocolParser::parseHTTP($data);
        echo "  " . json_encode(['type' => $parsed['type'], 'method' => $parsed['method'], 'path' => $parsed['path'], 'statusCode' => $parsed['statusCode']]) . "\n";
        echo "  Headers: " . count($parsed['headers']) . "\n";
        if ($parsed['body']) echo "  Body: {$parsed['body']}\n";
    }
}

echo "\n--- DNS Parsing ---\n";
// 构建DNS查询包
$dnsQuery = "\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01";
$parsedDNS = ProtocolParser::parseDNS($dnsQuery);
echo "DNS: " . json_encode($parsedDNS) . "\n";

echo "=== f123 Done ===\n";
