<?php
// 极度混搭: 网络协议栈模拟 + TCP握手 + 滑动窗口 + 拥塞控制
echo "=== f106: Network Stack + TCP + SlidingWindow + Congestion ===\n";

class TCPPacket {
    public function __construct(
        public int $seq,
        public int $ack,
        public string $data,
        public int $flags = 0, // SYN=1, ACK=2, FIN=4, RST=8
        public int $window = 65535
    ) {}
    public function isSyn(): bool { return ($this->flags & 1) !== 0; }
    public function isAck(): bool { return ($this->flags & 2) !== 0; }
    public function isFin(): bool { return ($this->flags & 4) !== 0; }
}

class TCPConnection {
    public string $state = 'CLOSED';
    public int $seqNum = 0;
    public int $ackNum = 0;
    public int $windowSize = 1024;
    public array $sendBuffer = [];
    public array $recvBuffer = [];
    public array $sentPackets = [];
    public float $rtt = 0.1;
    public int $ssthresh = 16;
    public int $cwnd = 1;
    public int $dupAcks = 0;
    public array $log = [];

    public function __construct(public string $name) {}

    public function connect(): array {
        $packets = [];
        // SYN
        $this->seqNum = 1000;
        $syn = new TCPPacket($this->seqNum, 0, '', 1);
        $this->state = 'SYN_SENT';
        $this->log[] = "→ SYN seq={$this->seqNum}";
        $packets[] = $syn;
        return $packets;
    }

    public function receive(TCPPacket $packet): array {
        $response = [];
        $this->log[] = "← " . $this->describePacket($packet);

        if ($packet->isSyn() && $this->state === 'CLOSED') {
            // Server receives SYN
            $this->ackNum = $packet->seq + 1;
            $this->seqNum = 2000;
            $synAck = new TCPPacket($this->seqNum, $this->ackNum, '', 1 | 2);
            $this->state = 'SYN_RCVD';
            $this->log[] = "→ SYN-ACK seq={$this->seqNum} ack={$this->ackNum}";
            $response[] = $synAck;
        } elseif ($packet->isSyn() && $packet->isAck() && $this->state === 'SYN_SENT') {
            // Client receives SYN-ACK
            $this->ackNum = $packet->seq + 1;
            $this->seqNum++;
            $ack = new TCPPacket($this->seqNum, $this->ackNum, '', 2);
            $this->state = 'ESTABLISHED';
            $this->log[] = "→ ACK seq={$this->seqNum} ack={$this->ackNum}";
            $response[] = $ack;
        } elseif ($packet->isAck() && !$packet->isSyn() && $this->state === 'SYN_RCVD') {
            $this->state = 'ESTABLISHED';
            $this->log[] = "  Connection established";
        } elseif ($packet->isFin()) {
            $this->ackNum = $packet->seq + 1;
            $ack = new TCPPacket($this->seqNum, $this->ackNum, '', 2);
            $this->state = 'CLOSE_WAIT';
            $this->log[] = "→ ACK (FIN received)";
            $response[] = $ack;
            $fin = new TCPPacket($this->seqNum, $this->ackNum, '', 4);
            $this->state = 'LAST_ACK';
            $this->log[] = "→ FIN";
            $response[] = $fin;
        } elseif ($packet->isAck() && $this->state === 'LAST_ACK') {
            $this->state = 'CLOSED';
            $this->log[] = "  Connection closed";
        } elseif ($packet->data !== '') {
            $this->ackNum = $packet->seq + strlen($packet->data);
            $this->recvBuffer[] = $packet->data;
            $ack = new TCPPacket($this->seqNum, $this->ackNum, '', 2);
            $this->log[] = "→ ACK seq={$this->seqNum} ack={$this->ackNum} (data=" . strlen($packet->data) . ")";
            $response[] = $ack;
        }
        return $response;
    }

    public function sendData(string $data): array {
        $packets = [];
        $chunkSize = 100;
        $offset = 0;
        while ($offset < strlen($data)) {
            $chunk = substr($data, $offset, $chunkSize);
            $packet = new TCPPacket($this->seqNum, $this->ackNum, $chunk, 2);
            $this->sentPackets[] = ['seq' => $this->seqNum, 'data' => $chunk, 'acked' => false];
            $this->seqNum += strlen($chunk);
            $this->log[] = "→ DATA seq=" . ($this->seqNum - strlen($chunk)) . " len=" . strlen($chunk);
            $packets[] = $packet;
            $offset += $chunkSize;
        }
        return $packets;
    }

    public function close(): array {
        $fin = new TCPPacket($this->seqNum, $this->ackNum, '', 4);
        $this->state = 'FIN_WAIT_1';
        $this->log[] = "→ FIN";
        return [$fin];
    }

    private function describePacket(TCPPacket $p): string {
        $flags = [];
        if ($p->isSyn()) $flags[] = 'SYN';
        if ($p->isAck()) $flags[] = 'ACK';
        if ($p->isFin()) $flags[] = 'FIN';
        return implode('+', $flags) . " seq={$p->seq} ack={$p->ack}" . ($p->data ? " data=" . strlen($p->data) : '');
    }

    public function getLog(): array { return $this->log; }
}

class SlidingWindow {
    private int $base = 0;
    private int $nextSeq = 0;
    private array $buffer = [];
    private array $acked = [];

    public function __construct(private int $windowSize, private int $totalPackets) {}

    public function send(): array {
        $sent = [];
        while ($this->nextSeq < $this->totalPackets && $this->nextSeq < $this->base + $this->windowSize) {
            $this->buffer[$this->nextSeq] = ['seq' => $this->nextSeq, 'sent' => true, 'acked' => false];
            $sent[] = $this->nextSeq;
            $this->nextSeq++;
        }
        return $sent;
    }

    public function receiveAck(int $ack): void {
        if ($ack >= $this->base) {
            for ($i = $this->base; $i <= $ack; $i++) {
                if (isset($this->buffer[$i])) {
                    $this->buffer[$i]['acked'] = true;
                    $this->acked[] = $i;
                }
            }
            $this->base = $ack + 1;
        }
    }

    public function getWindowState(): array {
        return ['base' => $this->base, 'nextSeq' => $this->nextSeq, 'windowSize' => $this->windowSize, 'inFlight' => $this->nextSeq - $this->base];
    }
}

class CongestionControl {
    public int $cwnd = 1;
    public int $ssthresh = 16;
    public string $state = 'slow_start';
    public array $log = [];

    public function onAck(): void {
        if ($this->state === 'slow_start') {
            $this->cwnd++;
            $this->log[] = "ACK: cwnd=$this->cwnd (slow_start)";
            if ($this->cwnd >= $this->ssthresh) { $this->state = 'congestion_avoidance'; $this->log[] = "→ congestion_avoidance"; }
        } else {
            $this->cwnd += 1 / $this->cwnd;
            $this->log[] = "ACK: cwnd=" . number_format($this->cwnd, 2) . " (congestion_avoidance)";
        }
    }

    public function onLoss(): void {
        $this->ssthresh = max(1, (int)($this->cwnd / 2));
        $this->cwnd = 1;
        $this->state = 'slow_start';
        $this->log[] = "LOSS: ssthresh=$this->ssthresh cwnd=1 → slow_start";
    }

    public function onTimeout(): void {
        $this->ssthresh = max(1, (int)($this->cwnd / 2));
        $this->cwnd = 1;
        $this->state = 'slow_start';
        $this->log[] = "TIMEOUT: ssthresh=$this->ssthresh cwnd=1 → slow_start";
    }
}

// 测试
echo "--- TCP 3-Way Handshake ---\n";
$client = new TCPConnection('Client');
$server = new TCPConnection('Server');

$packets = $client->connect();
echo "Client sends SYN\n";
foreach ($packets as $p) {
    $resp = $server->receive($p);
    foreach ($resp as $r) $client->receive($r);
}
echo "Client state: {$client->state}\n";
echo "Server state: {$server->state}\n";

echo "\n--- Data Transfer ---\n";
$dataPackets = $client->sendData("Hello World! This is a test message for TCP data transfer.");
echo "Client sends " . count($dataPackets) . " data packets\n";
foreach ($dataPackets as $p) {
    $resp = $server->receive($p);
    foreach ($resp as $r) $client->receive($r);
}
echo "Server received: " . implode('', $server->recvBuffer) . "\n";

echo "\n--- Connection Close ---\n";
$closePackets = $client->close();
foreach ($closePackets as $p) {
    $resp = $server->receive($p);
    foreach ($resp as $r) $client->receive($r);
}
echo "Client state: {$client->state}\n";
echo "Server state: {$server->state}\n";

echo "\n--- Client Log ---\n";
foreach ($client->getLog() as $log) echo "  $log\n";

echo "\n--- Sliding Window ---\n";
$sw = new SlidingWindow(4, 10);
echo "Window size: 4, Total packets: 10\n";
for ($round = 1; $round <= 4; $round++) {
    $sent = $sw->send();
    echo "Round $round: sent [" . implode(',', $sent) . "] state=" . json_encode($sw->getWindowState()) . "\n";
    // ACK some
    $ackUpTo = $sw->getWindowState()['base'] + count($sent) - 1;
    $sw->receiveAck($ackUpTo);
    echo "  After ACK $ackUpTo: " . json_encode($sw->getWindowState()) . "\n";
}

echo "\n--- Congestion Control ---\n";
$cc = new CongestionControl();
echo "Initial: cwnd={$cc->cwnd} ssthresh={$cc->ssthresh} state={$cc->state}\n";
// 模拟20个ACK
for ($i = 0; $i < 20; $i++) $cc->onAck();
echo "After 20 ACKs: cwnd=" . number_format($cc->cwnd, 1) . " ssthresh={$cc->ssthresh} state={$cc->state}\n";
// 模拟丢包
$cc->onLoss();
echo "After loss: cwnd={$cc->cwnd} ssthresh={$cc->ssthresh} state={$cc->state}\n";
// 再次增长
for ($i = 0; $i < 10; $i++) $cc->onAck();
echo "After 10 more ACKs: cwnd=" . number_format($cc->cwnd, 1) . " state={$cc->state}\n";

echo "\n--- Log (last 10) ---\n";
foreach (array_slice($cc->log, -10) as $log) echo "  $log\n";

echo "=== f106 Done ===\n";
