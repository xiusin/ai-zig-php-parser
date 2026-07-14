<?php

class Customer {
    public readonly string $id;
    public string $name;
    public string $email;
    public string $phone;
    public string $status;
    private array $accounts = [];
    private float $creditScore;

    public function __construct(
        string $id,
        string $name,
        string $email,
        string $phone = '',
        float $creditScore = 700.0
    ) {
        $this->id = $id;
        $this->name = $name;
        $this->email = $email;
        $this->phone = $phone;
        $this->creditScore = $creditScore;
        $this->status = 'active';
    }

    public function addAccount(Account $account): void {
        $this->accounts[$account->id] = $account;
    }

    public function removeAccount(string $accountId): bool {
        if (!isset($this->accounts[$accountId])) return false;
        unset($this->accounts[$accountId]);
        return true;
    }

    public function getAccount(string $accountId): ?Account {
        return $this->accounts[$accountId] ?? null;
    }

    public function getAccounts(): array { return $this->accounts; }

    public function getTotalBalance(): int {
        $total = 0;
        foreach ($this->accounts as $account) {
            $total += $account->getBalance();
        }
        return $total;
    }

    public function getAccountCount(): int { return count($this->accounts); }

    public function getCreditScore(): float { return $this->creditScore; }

    public function setCreditScore(float $score): void {
        $this->creditScore = max(300, min(850, $score));
    }

    public function adjustCreditScore(float $delta): void {
        $this->setCreditScore($this->creditScore + $delta);
    }

    public function suspend(): void { $this->status = 'suspended'; }
    public function activate(): void { $this->status = 'active'; }
    public function close(): void { $this->status = 'closed'; }

    public function isActive(): bool { return $this->status === 'active'; }

    public function getAccountIds(): array { return array_keys($this->accounts); }

    public function getTransactionHistory(): array {
        $history = [];
        foreach ($this->accounts as $accountId => $account) {
            foreach ($account->getTransactions() as $tx) {
                $history[] = array_merge(['accountId' => $accountId], $tx);
            }
        }
        return $history;
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
            'phone' => $this->phone,
            'status' => $this->status,
            'creditScore' => $this->creditScore,
            'accountCount' => $this->getAccountCount(),
            'totalBalance' => $this->getTotalBalance(),
        ];
    }
}
