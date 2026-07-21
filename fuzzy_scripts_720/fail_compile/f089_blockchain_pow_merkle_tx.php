<?php
// 极度混搭: 区块链 + 工作量证明 + 默克尔树 + 交易验证
echo "=== f089: Blockchain + PoW + Merkle + Tx ===\n";

class Transaction {
    public string $hash;
    public function __construct(
        public string $from,
        public string $to,
        public float $amount,
        public int $timestamp = 0,
        public string $signature = ''
    ) {
        $this->timestamp = $this->timestamp ?: time();
        $this->hash = $this->computeHash();
    }
    public function computeHash(): string {
        return hash('sha256', $this->from . $this->to . $this->amount . $this->timestamp);
    }
    public function __toString(): string { return "{$this->from}→{$this->to}:{$this->amount}"; }
}

class MerkleTree {
    public static function build(array $txs): string {
        if (empty($txs)) return hash('sha256', '');
        $hashes = array_map(fn($tx) => $tx->hash, $txs);
        while (count($hashes) > 1) {
            $newHashes = [];
            for ($i = 0; $i < count($hashes); $i += 2) {
                $left = $hashes[$i];
                $right = $hashes[$i + 1] ?? $hashes[$i];
                $newHashes[] = hash('sha256', $left . $right);
            }
            $hashes = $newHashes;
        }
        return $hashes[0];
    }
}

class Block {
    public string $hash;
    public int $nonce = 0;
    public string $merkleRoot;

    public function __construct(
        public int $index,
        public array $transactions,
        public int $timestamp,
        public string $previousHash,
        public int $difficulty = 2
    ) {
        $this->merkleRoot = MerkleTree::build($transactions);
        $this->hash = $this->computeHash();
    }

    public function computeHash(): string {
        return hash('sha256', $this->index . $this->merkleRoot . $this->timestamp . $this->previousHash . $this->nonce);
    }

    public function mine(): void {
        $target = str_repeat('0', $this->difficulty);
        while (!str_starts_with($this->hash, $target)) {
            $this->nonce++;
            $this->hash = $this->computeHash();
        }
    }
}

class Blockchain {
    public array $chain = [];
    public array $pendingTx = [];
    public array $balances = [];
    private int $difficulty = 2;
    private float $miningReward = 10;

    public function __construct() {
        $this->chain[] = $this->createGenesisBlock();
    }

    private function createGenesisBlock(): Block {
        return new Block(0, [], time(), '0', $this->difficulty);
    }

    public function addTransaction(Transaction $tx): bool {
        if ($tx->from !== 'system' && ($this->balances[$tx->from] ?? 0) < $tx->amount) return false;
        $this->pendingTx[] = $tx;
        return true;
    }

    public function minePendingTransactions(string $minerAddress): Block {
        $this->pendingTx[] = new Transaction('system', $minerAddress, $this->miningReward);
        $block = new Block(count($this->chain), $this->pendingTx, time(), end($this->chain)->hash, $this->difficulty);
        $block->mine();

        foreach ($this->pendingTx as $tx) {
            if ($tx->from !== 'system') $this->balances[$tx->from] = ($this->balances[$tx->from] ?? 0) - $tx->amount;
            $this->balances[$tx->to] = ($this->balances[$tx->to] ?? 0) + $tx->amount;
        }

        $this->chain[] = $block;
        $this->pendingTx = [];
        return $block;
    }

    public function isValid(): bool {
        for ($i = 1; $i < count($this->chain); $i++) {
            $current = $this->chain[$i];
            $previous = $this->chain[$i - 1];
            if ($current->previousHash !== $previous->hash) return false;
            if ($current->hash !== $current->computeHash()) return false;
        }
        return true;
    }

    public function getBalance(string $address): float { return $this->balances[$address] ?? 0; }
    public function getChainLength(): int { return count($this->chain); }
}

// 测试
echo "--- Blockchain Setup ---\n";
$bc = new Blockchain();
echo "Genesis block created, chain length: " . $bc->getChainLength() . "\n";
echo "Difficulty: 2 (hash starts with '00')\n";

echo "\n--- Initial Balances ---\n";
$bc->balances['alice'] = 100;
$bc->balances['bob'] = 50;
echo "Alice: " . $bc->getBalance('alice') . "\n";
echo "Bob: " . $bc->getBalance('bob') . "\n";

echo "\n--- Transactions ---\n";
$tx1 = new Transaction('alice', 'bob', 30);
echo "Tx1: $tx1 hash=" . substr($tx1->hash, 0, 16) . "...\n";
echo "Add tx1: " . var_export($bc->addTransaction($tx1), true) . "\n";

$tx2 = new Transaction('bob', 'alice', 10);
echo "Tx2: $tx2 hash=" . substr($tx2->hash, 0, 16) . "...\n";
echo "Add tx2: " . var_export($bc->addTransaction($tx2), true) . "\n";

$tx3 = new Transaction('alice', 'charlie', 200);
echo "Tx3 (insufficient): $tx3\n";
echo "Add tx3: " . var_export($bc->addTransaction($tx3), true) . "\n";

echo "\n--- Mining ---\n";
echo "Mining block 1...\n";
$block1 = $bc->minePendingTransactions('miner1');
echo "Block mined! hash=" . substr($block1->hash, 0, 16) . "... nonce={$block1->nonce}\n";
echo "Transactions in block: " . count($block1->transactions) . "\n";

echo "\n--- Balances After Mining ---\n";
echo "Alice: " . $bc->getBalance('alice') . "\n";
echo "Bob: " . $bc->getBalance('bob') . "\n";
echo "Charlie: " . $bc->getBalance('charlie') . "\n";
echo "Miner1: " . $bc->getBalance('miner1') . "\n";

echo "\n--- Second Block ---\n";
$tx4 = new Transaction('bob', 'charlie', 20);
$bc->addTransaction($tx4);
$block2 = $bc->minePendingTransactions('miner1');
echo "Block 2 mined! hash=" . substr($block2->hash, 0, 16) . "...\n";

echo "\n--- Chain Validation ---\n";
echo "Chain length: " . $bc->getChainLength() . "\n";
echo "Chain valid: " . var_export($bc->isValid(), true) . "\n";

echo "\n--- Chain Info ---\n";
foreach ($bc->chain as $block) {
    echo "  Block #{$block->index}: txs=" . count($block->transactions) . " nonce={$block->nonce} hash=" . substr($block->hash, 0, 16) . "... prev=" . substr($block->previousHash, 0, 16) . "...\n";
}

echo "\n--- Merkle Root ---\n";
foreach ($bc->chain as $block) {
    if (!empty($block->transactions)) {
        echo "  Block #{$block->index} merkle: " . substr($block->merkleRoot, 0, 16) . "...\n";
    }
}

echo "=== f089 Done ===\n";
