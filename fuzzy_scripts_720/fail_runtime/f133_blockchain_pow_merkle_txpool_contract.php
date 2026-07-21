<?php
// 极度混搭: 区块链 + PoW + Merkle树 + 交易池 + 智能合约
echo "=== f133: Blockchain + PoW + Merkle + TxPool + Contract ===\n";

class Transaction {
    public string $hash;

    public function __construct(
        public string $from,
        public string $to,
        public float $amount,
        public float $fee = 0,
        public int $nonce = 0,
        public ?string $signature = null
    ) {
        $this->hash = $this->computeHash();
    }

    public function computeHash(): string {
        return hash('sha256', $this->from . $this->to . $this->amount . $this->fee . $this->nonce);
    }

    public function __toString(): string { return substr($this->hash, 0, 16); }
}

class MerkleTree {
    public function __construct(public array $leaves) {
        $this->root = $this->build($leaves);
    }
    public string $root;

    private function build(array $nodes): string {
        if (count($nodes) === 1) return $nodes[0];
        if (count($nodes) % 2 !== 0) $nodes[] = end($nodes);
        $next = [];
        for ($i = 0; $i < count($nodes); $i += 2) {
            $next[] = hash('sha256', $nodes[$i] . $nodes[$i + 1]);
        }
        return $this->build($next);
    }

    public function getProof(string $leaf): array {
        $index = array_search($leaf, $this->leaves);
        if ($index === false) return [];
        $proof = [];
        $nodes = $this->leaves;
        $idx = $index;
        while (count($nodes) > 1) {
            if (count($nodes) % 2 !== 0) $nodes[] = end($nodes);
            $siblingIdx = $idx % 2 === 0 ? $idx + 1 : $idx - 1;
            $proof[] = ['hash' => $nodes[$siblingIdx], 'position' => $idx % 2 === 0 ? 'right' : 'left'];
            $next = [];
            for ($i = 0; $i < count($nodes); $i += 2) $next[] = hash('sha256', $nodes[$i] . $nodes[$i + 1]);
            $nodes = $next;
            $idx = (int)($idx / 2);
        }
        return $proof;
    }

    public static function verifyProof(string $leaf, array $proof, string $root): bool {
        $hash = $leaf;
        foreach ($proof as $p) {
            $hash = $p['position'] === 'right' ? hash('sha256', $hash . $p['hash']) : hash('sha256', $p['hash'] . $hash);
        }
        return $hash === $root;
    }
}

class Block {
    public string $hash;
    public array $transactions = [];
    public int $nonce = 0;

    public function __construct(
        public int $index,
        public string $previousHash,
        public float $timestamp,
        public array $txs,
        public int $difficulty = 2
    ) {
        $this->transactions = $txs;
        $this->mine();
    }

    public function computeHash(int $nonce = 0): string {
        $txHashes = implode('', array_map(fn($t) => $t->hash, $this->transactions));
        return hash('sha256', $this->index . $this->previousHash . $this->timestamp . $txHashes . $nonce);
    }

    public function mine(): void {
        $target = str_repeat('0', $this->difficulty);
        while (true) {
            $hash = $this->computeHash($this->nonce);
            if (str_starts_with($hash, $target)) { $this->hash = $hash; break; }
            $this->nonce++;
            if ($this->nonce > 100000) { $this->hash = $hash; break; } // 防止无限循环
        }
    }

    public function getMerkleRoot(): string {
        $leaves = array_map(fn($t) => $t->hash, $this->transactions);
        if (empty($leaves)) return hash('sha256', '');
        $tree = new MerkleTree($leaves);
        return $tree->root;
    }
}

class Blockchain {
    public array $chain = [];
    public array $pendingTx = [];
    public array $balances = [];
    public int $difficulty = 2;
    public float $miningReward = 10;
    public array $contracts = [];

    public function __construct() {
        $this->chain[] = $this->createGenesisBlock();
    }

    private function createGenesisBlock(): Block {
        return new Block(0, '0', microtime(true), [], $this->difficulty);
    }

    public function getLatestBlock(): Block { return end($this->chain); }

    public function addTransaction(Transaction $tx): bool {
        if ($tx->from === 'system') { $this->pendingTx[] = $tx; return true; }
        $balance = $this->balances[$tx->from] ?? 0;
        if ($balance < $tx->amount + $tx->fee) return false;
        $this->pendingTx[] = $tx;
        return true;
    }

    public function minePendingTransactions(string $minerAddress): Block {
        $rewardTx = new Transaction('system', $minerAddress, $this->miningReward);
        $this->pendingTx[] = $rewardTx;
        $block = new Block(count($this->chain), $this->getLatestBlock()->hash, microtime(true), $this->pendingTx, $this->difficulty);
        $this->chain[] = $block;
        // 处理交易
        foreach ($this->pendingTx as $tx) {
            if ($tx->from !== 'system') {
                $this->balances[$tx->from] = ($this->balances[$tx->from] ?? 0) - $tx->amount - $tx->fee;
            }
            $this->balances[$tx->to] = ($this->balances[$tx->to] ?? 0) + $tx->amount;
            if ($tx->fee > 0) $this->balances[$minerAddress] = ($this->balances[$minerAddress] ?? 0) + $tx->fee;
        }
        $this->pendingTx = [];
        return $block;
    }

    public function getBalance(string $address): float { return $this->balances[$address] ?? 0; }

    public function isValid(): bool {
        for ($i = 1; $i < count($this->chain); $i++) {
            $current = $this->chain[$i];
            $previous = $this->chain[$i - 1];
            if ($current->previousHash !== $previous->hash) return false;
            if ($current->computeHash($current->nonce) !== $current->hash) return false;
        }
        return true;
    }

    public function deployContract(string $address, string $code): string {
        $contractAddr = hash('sha256', $address . $code . microtime(true));
        $this->contracts[$contractAddr] = ['code' => $code, 'storage' => [], 'owner' => $address];
        return $contractAddr;
    }

    public function executeContract(string $contractAddr, string $method, array $args, string $caller): mixed {
        if (!isset($this->contracts[$contractAddr])) return null;
        $contract = &$this->contracts[$contractAddr];
        $storage = &$contract['storage'];
        // 简化合约执行
        if ($method === 'set') { $storage[$args[0]] = $args[1]; return true; }
        if ($method === 'get') { return $storage[$args[0]] ?? null; }
        if ($method === 'transfer') {
            $amount = $args[1];
            if (($this->balances[$caller] ?? 0) >= $amount) {
                $this->balances[$caller] -= $amount;
                $this->balances[$args[0]] = ($this->balances[$args[0]] ?? 0) + $amount;
                $storage['lastTransfer'] = ['from' => $caller, 'to' => $args[0], 'amount' => $amount];
                return true;
            }
            return false;
        }
        return null;
    }
}

// 测试
echo "--- Create Blockchain ---\n";
$bc = new Blockchain();
echo "Genesis block hash: " . substr($bc->getLatestBlock()->hash, 0, 20) . "...\n";
echo "Chain length: " . count($bc->chain) . "\n";

echo "\n--- Merkle Tree ---\n";
$txHashes = [hash('sha256', 'tx1'), hash('sha256', 'tx2'), hash('sha256', 'tx3'), hash('sha256', 'tx4')];
$tree = new MerkleTree($txHashes);
echo "Merkle root: " . substr($tree->root, 0, 20) . "...\n";
$proof = $tree->getProof($txHashes[1]);
echo "Proof for tx2: " . count($proof) . " nodes\n";
$valid = MerkleTree::verifyProof($txHashes[1], $proof, $tree->root);
echo "Verification: " . var_export($valid, true) . "\n";

echo "\n--- Transactions & Mining ---\n";
// 初始余额
$bc->balances['alice'] = 100;
$bc->balances['bob'] = 50;

$tx1 = new Transaction('alice', 'bob', 30, 0.5);
$tx2 = new Transaction('bob', 'charlie', 20, 0.3);
$bc->addTransaction($tx1);
$bc->addTransaction($tx2);
echo "Pending transactions: " . count($bc->pendingTx) . "\n";

$block = $bc->minePendingTransactions('miner1');
echo "Mined block #{$block->index}, nonce={$block->nonce}\n";
echo "Block hash: " . substr($block->hash, 0, 20) . "...\n";

echo "\n--- Balances ---\n";
echo "  alice: " . $bc->getBalance('alice') . "\n";
echo "  bob: " . $bc->getBalance('bob') . "\n";
echo "  charlie: " . $bc->getBalance('charlie') . "\n";
echo "  miner1: " . $bc->getBalance('miner1') . "\n";

echo "\n--- Chain Validation ---\n";
echo "Chain valid: " . var_export($bc->isValid(), true) . "\n";

echo "\n--- More Mining ---\n";
$tx3 = new Transaction('charlie', 'alice', 10, 0.2);
$bc->addTransaction($tx3);
$block2 = $bc->minePendingTransactions('miner1');
echo "Mined block #{$block2->index}\n";
echo "Chain length: " . count($bc->chain) . "\n";
echo "Chain valid: " . var_export($bc->isValid(), true) . "\n";

echo "\n--- Smart Contracts ---\n";
$contractAddr = $bc->deployContract('alice', 'storage_contract');
echo "Contract deployed: " . substr($contractAddr, 0, 20) . "...\n";

$result = $bc->executeContract($contractAddr, 'set', ['key1', 'value1'], 'alice');
echo "Set key1=value1: " . var_export($result, true) . "\n";
$result = $bc->executeContract($contractAddr, 'get', ['key1'], 'alice');
echo "Get key1: " . var_export($result, true) . "\n";

$result = $bc->executeContract($contractAddr, 'transfer', ['bob', 20], 'alice');
echo "Contract transfer alice→bob 20: " . var_export($result, true) . "\n";
echo "  alice balance: " . $bc->getBalance('alice') . "\n";
echo "  bob balance: " . $bc->getBalance('bob') . "\n";

echo "\n--- Block Details ---\n";
foreach ($bc->chain as $block) {
    echo "Block #{$block->index}:\n";
    echo "  Hash: " . substr($block->hash, 0, 20) . "...\n";
    echo "  Prev: " . substr($block->previousHash, 0, 20) . "...\n";
    echo "  Nonce: {$block->nonce}\n";
    echo "  Transactions: " . count($block->transactions) . "\n";
    echo "  Merkle root: " . substr($block->getMerkleRoot(), 0, 20) . "...\n";
}

echo "\n--- Tamper Detection ---\n";
$bc->chain[1]->transactions[0] = new Transaction('alice', 'bob', 999);
echo "After tampering: chain valid = " . var_export($bc->isValid(), true) . "\n";

echo "=== f133 Done ===\n";
