<?php

class Bank {
    private string $name;
    private array $customers = [];
    private array $accounts = [];
    private TransactionLog $txLog;
    private int $accountCounter = 0;
    private array $auditLog = [];
    private float $totalAssets = 0;

    public function __construct(string $name) {
        $this->name = $name;
        $this->txLog = new TransactionLog();
    }

    public function registerCustomer(string $name, string $email, string $phone = ''): Customer {
        $customerId = 'CUST' . str_pad((string)(count($this->customers) + 1), 6, '0', STR_PAD_LEFT);
        $customer = new Customer($customerId, $name, $email, $phone);
        $this->customers[$customerId] = $customer;
        $this->audit("Registered customer: $customerId ($name)");
        return $customer;
    }

    public function createAccount(string $customerId, string $type = 'checking', int $initialDeposit = 0): ?Account {
        if (!isset($this->customers[$customerId])) return null;

        $accountId = 'ACC' . str_pad((string)(++$this->accountCounter), 8, '0', STR_PAD_LEFT);

        $account = match ($type) {
            'savings' => new SavingsAccount($accountId, $customerId, $initialDeposit),
            'credit' => new CreditAccount($accountId, $customerId),
            default => new Account($accountId, $customerId, 'checking', $initialDeposit),
        };

        $this->accounts[$accountId] = $account;
        $this->customers[$customerId]->addAccount($account);
        $this->totalAssets += $initialDeposit;
        $this->audit("Created $type account: $accountId for customer: $customerId");
        return $account;
    }

    public function deposit(string $accountId, int $amount, string $description = ''): bool {
        $account = $this->getAccount($accountId);
        if ($account === null) return false;

        $tx = new Transaction('deposit', $amount, $accountId, null, $description);
        if ($account->deposit($amount, $description)) {
            $tx->complete();
            $this->txLog->log($tx);
            $this->totalAssets += $amount;
            $this->audit("Deposit $amount cents to $accountId");
            return true;
        }
        $tx->fail();
        $this->txLog->log($tx);
        return false;
    }

    public function withdraw(string $accountId, int $amount, string $description = ''): bool {
        $account = $this->getAccount($accountId);
        if ($account === null) return false;

        $tx = new Transaction('withdrawal', $amount, $accountId, null, $description);
        if ($account->withdraw($amount, $description)) {
            $tx->complete();
            $this->txLog->log($tx);
            $this->totalAssets -= $amount;
            $this->audit("Withdraw $amount cents from $accountId");
            return true;
        }
        $tx->fail();
        $this->txLog->log($tx);
        return false;
    }

    public function transfer(string $fromId, string $toId, int $amount, string $description = ''): bool {
        $from = $this->getAccount($fromId);
        $to = $this->getAccount($toId);
        if ($from === null || $to === null) return false;

        $tx = new Transaction('transfer', $amount, $fromId, $toId, $description);
        if ($from->transfer($to, $amount, $description)) {
            $tx->complete();
            $this->txLog->log($tx);
            $this->audit("Transfer $amount cents from $fromId to $toId");
            return true;
        }
        $tx->fail();
        $this->txLog->log($tx);
        return false;
    }

    public function applyInterest(string $accountId): int {
        $account = $this->getAccount($accountId);
        if (!($account instanceof SavingsAccount) && !($account instanceof CreditAccount)) return 0;

        $interest = $account->applyInterest();
        if ($interest > 0) {
            $tx = new Transaction('interest', $interest, $accountId, null, 'Interest applied');
            $tx->complete();
            $this->txLog->log($tx);
            $this->audit("Interest $interest cents applied to $accountId");
        }
        return $interest;
    }

    public function freezeAccount(string $accountId, string $reason): bool {
        $account = $this->getAccount($accountId);
        if ($account === null) return false;
        $account->freeze($reason);
        $this->audit("Account $accountId frozen: $reason");
        return true;
    }

    public function unfreezeAccount(string $accountId): bool {
        $account = $this->getAccount($accountId);
        if ($account === null) return false;
        $account->unfreeze();
        $this->audit("Account $accountId unfrozen");
        return true;
    }

    public function getCustomer(string $customerId): ?Customer {
        return $this->customers[$customerId] ?? null;
    }

    public function getAccount(string $accountId): ?Account {
        return $this->accounts[$accountId] ?? null;
    }

    public function getCustomers(): array { return $this->customers; }
    public function getAccounts(): array { return $this->accounts; }
    public function getTransactionLog(): TransactionLog { return $this->txLog; }
    public function getName(): string { return $this->name; }
    public function getTotalAssets(): float { return $this->totalAssets; }

    public function getCustomerCount(): int { return count($this->customers); }
    public function getAccountCount(): int { return count($this->accounts); }

    public function getAuditLog(): array { return $this->auditLog; }

    public function getBankSummary(): array {
        $typeCounts = [];
        foreach ($this->accounts as $account) {
            $typeCounts[$account->type] = ($typeCounts[$account->type] ?? 0) + 1;
        }
        return [
            'name' => $this->name,
            'customers' => $this->getCustomerCount(),
            'accounts' => $this->getAccountCount(),
            'accountTypes' => $typeCounts,
            'totalAssets' => $this->totalAssets,
            'totalTransactions' => $this->txLog->getCount(),
        ];
    }

    private function audit(string $message): void {
        $this->auditLog[] = [
            'message' => $message,
            'timestamp' => time(),
        ];
    }
}
