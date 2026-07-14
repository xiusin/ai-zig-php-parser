<?php

class Account {
    public readonly string $id;
    public readonly string $customerId;
    public string $type;
    protected int $balance;
    protected array $transactions = [];
    protected bool $frozen = false;
    protected ?string $frozenReason = null;

    public function __construct(string $id, string $customerId, string $type = 'checking', int $initialBalance = 0) {
        $this->id = $id;
        $this->customerId = $customerId;
        $this->type = $type;
        $this->balance = $initialBalance;

        if ($initialBalance > 0) {
            $this->addTransaction('deposit', $initialBalance, 'Initial deposit');
        }
    }

    public function getBalance(): int { return $this->balance; }
    public function isFrozen(): bool { return $this->frozen; }
    public function getFrozenReason(): ?string { return $this->frozenReason; }
    public function getTransactions(): array { return $this->transactions; }

    public function deposit(int $amount, string $description = ''): bool {
        if ($this->frozen) return false;
        if ($amount <= 0) return false;

        $this->balance += $amount;
        $this->addTransaction('deposit', $amount, $description);
        return true;
    }

    public function withdraw(int $amount, string $description = ''): bool {
        if ($this->frozen) return false;
        if ($amount <= 0) return false;
        if ($amount > $this->balance) return false;

        $this->balance -= $amount;
        $this->addTransaction('withdrawal', $amount, $description);
        return true;
    }

    public function transfer(Account $target, int $amount, string $description = ''): bool {
        if ($this->frozen || $target->frozen) return false;
        if ($amount <= 0 || $amount > $this->balance) return false;

        $this->balance -= $amount;
        $target->balance += $amount;

        $this->addTransaction('transfer_out', $amount, "Transfer to {$target->id}: $description");
        $target->addTransaction('transfer_in', $amount, "Transfer from {$this->id}: $description");
        return true;
    }

    public function freeze(string $reason): void {
        $this->frozen = true;
        $this->frozenReason = $reason;
    }

    public function unfreeze(): void {
        $this->frozen = false;
        $this->frozenReason = null;
    }

    protected function addTransaction(string $type, int $amount, string $description): void {
        $this->transactions[] = [
            'type' => $type,
            'amount' => $amount,
            'balance_after' => $this->balance,
            'description' => $description,
            'timestamp' => time(),
        ];
    }

    public function getTransactionCount(): int { return count($this->transactions); }

    public function getTransactionSummary(): array {
        $summary = ['deposit' => 0, 'withdrawal' => 0, 'transfer_in' => 0, 'transfer_out' => 0];
        foreach ($this->transactions as $tx) {
            if (isset($summary[$tx['type']])) {
                $summary[$tx['type']]++;
            }
        }
        return $summary;
    }

    public function formatBalance(): string {
        return sprintf('$%d.%02d', $this->balance / 100, abs($this->balance % 100));
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'customerId' => $this->customerId,
            'type' => $this->type,
            'balance' => $this->balance,
            'frozen' => $this->frozen,
            'transactionCount' => count($this->transactions),
        ];
    }
}

class SavingsAccount extends Account {
    private float $interestRate;
    private int $minBalance;

    public function __construct(string $id, string $customerId, int $initialBalance = 0, float $interestRate = 0.02, int $minBalance = 10000) {
        parent::__construct($id, $customerId, 'savings', $initialBalance);
        $this->interestRate = $interestRate;
        $this->minBalance = $minBalance;
    }

    public function withdraw(int $amount, string $description = ''): bool {
        if ($this->frozen) return false;
        if ($amount <= 0) return false;
        if ($this->balance - $amount < $this->minBalance) return false;

        $this->balance -= $amount;
        $this->addTransaction('withdrawal', $amount, $description);
        return true;
    }

    public function applyInterest(): int {
        $interest = (int)($this->balance * $this->interestRate);
        if ($interest > 0) {
            $this->balance += $interest;
            $ratePct = $this->interestRate * 100;
            $this->addTransaction('interest', $interest, "Interest at {$ratePct}%");
        }
        return $interest;
    }

    public function getInterestRate(): float { return $this->interestRate; }
    public function getMinBalance(): int { return $this->minBalance; }
}

class CreditAccount extends Account {
    private int $creditLimit;
    private int $totalDebt = 0;
    private float $apr;

    public function __construct(string $id, string $customerId, int $creditLimit = 500000, float $apr = 0.1899) {
        parent::__construct($id, $customerId, 'credit', 0);
        $this->creditLimit = $creditLimit;
        $this->apr = $apr;
    }

    public function withdraw(int $amount, string $description = ''): bool {
        if ($this->frozen) return false;
        if ($amount <= 0) return false;
        if ($this->totalDebt + $amount > $this->creditLimit) return false;

        $this->totalDebt += $amount;
        $this->addTransaction('credit_charge', $amount, $description);
        return true;
    }

    public function deposit(int $amount, string $description = ''): bool {
        if ($this->frozen) return false;
        if ($amount <= 0) return false;
        if ($amount > $this->totalDebt) return false;

        $this->totalDebt -= $amount;
        $this->addTransaction('payment', $amount, $description);
        return true;
    }

    public function getAvailableCredit(): int { return $this->creditLimit - $this->totalDebt; }
    public function getTotalDebt(): int { return $this->totalDebt; }
    public function getCreditLimit(): int { return $this->creditLimit; }

    public function applyInterest(): int {
        $interest = (int)($this->totalDebt * $this->apr / 12);
        if ($interest > 0) {
            $this->totalDebt += $interest;
            $this->addTransaction('finance_charge', $interest, "Monthly finance charge");
        }
        return $interest;
    }

    public function getBalance(): int { return -$this->totalDebt; }

    public function formatBalance(): string {
        return sprintf('-$%d.%02d', $this->totalDebt / 100, $this->totalDebt % 100);
    }
}
