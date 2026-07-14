<?php

class Transaction {
    public readonly string $id;
    public readonly string $type;
    public readonly int $amount;
    public readonly string $fromAccountId;
    public readonly ?string $toAccountId;
    public readonly string $description;
    public readonly int $timestamp;
    public string $status;

    private static int $idCounter = 0;

    public function __construct(
        string $type,
        int $amount,
        string $fromAccountId,
        ?string $toAccountId = null,
        string $description = ''
    ) {
        $this->id = 'TXN' . str_pad((string)(++self::$idCounter), 8, '0', STR_PAD_LEFT);
        $this->type = $type;
        $this->amount = $amount;
        $this->fromAccountId = $fromAccountId;
        $this->toAccountId = $toAccountId;
        $this->description = $description;
        $this->timestamp = time();
        $this->status = 'pending';
    }

    public function complete(): void { $this->status = 'completed'; }
    public function fail(): void { $this->status = 'failed'; }
    public function cancel(): void { $this->status = 'cancelled'; }

    public function isCompleted(): bool { return $this->status === 'completed'; }
    public function isFailed(): bool { return $this->status === 'failed'; }

    public function formatAmount(): string {
        $sign = in_array($this->type, ['withdrawal', 'transfer_out', 'credit_charge', 'payment']) ? '-' : '+';
        if ($this->type === 'transfer_out') $sign = '-';
        if ($this->type === 'transfer_in') $sign = '+';
        return sprintf("%s$%d.%02d", $sign, $this->amount / 100, $this->amount % 100);
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'type' => $this->type,
            'amount' => $this->amount,
            'from' => $this->fromAccountId,
            'to' => $this->toAccountId,
            'description' => $this->description,
            'status' => $this->status,
        ];
    }
}

class TransactionLog {
    private array $transactions = [];
    private array $byType = [];
    private int $totalAmount = 0;

    public function log(Transaction $tx): void {
        $this->transactions[] = $tx;
        $this->byType[$tx->type][] = $tx;
        $this->totalAmount += $tx->amount;
    }

    public function getByType(string $type): array {
        return $this->byType[$type] ?? [];
    }

    public function getByAccount(string $accountId): array {
        return array_values(array_filter(
            $this->transactions,
            fn($tx) => $tx->fromAccountId === $accountId || $tx->toAccountId === $accountId
        ));
    }

    public function getAll(): array { return $this->transactions; }
    public function getCount(): int { return count($this->transactions); }
    public function getTotalAmount(): int { return $this->totalAmount; }

    public function getSummary(): array {
        $summary = [];
        foreach ($this->byType as $type => $txs) {
            $summary[$type] = [
                'count' => count($txs),
                'total' => array_sum(array_map(fn($t) => $t->amount, $txs)),
            ];
        }
        return $summary;
    }

    public function getCompletedTransactions(): array {
        return array_values(array_filter($this->transactions, fn($tx) => $tx->isCompleted()));
    }

    public function getFailedTransactions(): array {
        return array_values(array_filter($this->transactions, fn($tx) => $tx->isFailed()));
    }
}
