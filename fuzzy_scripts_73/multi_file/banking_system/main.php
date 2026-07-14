<?php
require_once __DIR__ . '/Account.php';
require_once __DIR__ . '/Customer.php';
require_once __DIR__ . '/Transaction.php';
require_once __DIR__ . '/Bank.php';

echo "=== Banking System ===\n\n";

$bank = new Bank('First National Bank');

// 注册客户
echo "--- Customer Registration ---\n";
$alice = $bank->registerCustomer('Alice Johnson', 'alice@email.com', '555-0101');
$bob = $bank->registerCustomer('Bob Smith', 'bob@email.com', '555-0102');
$charlie = $bank->registerCustomer('Charlie Brown', 'charlie@email.com', '555-0103');

echo "Customers: {$bank->getCustomerCount()}\n";
echo "  {$alice->id}: {$alice->name} (credit: {$alice->getCreditScore()})\n";
echo "  {$bob->id}: {$bob->name}\n";

// 创建账户
echo "\n--- Account Creation ---\n";
$aliceChecking = $bank->createAccount($alice->id, 'checking', 50000);    // $500.00
$aliceSavings = $bank->createAccount($alice->id, 'savings', 100000);     // $1000.00
$bobChecking = $bank->createAccount($bob->id, 'checking', 25000);        // $250.00
$charlieCredit = $bank->createAccount($charlie->id, 'credit');            // Credit card

echo "Accounts: {$bank->getAccountCount()}\n";
echo "  Alice checking: {$aliceChecking->formatBalance()}\n";
echo "  Alice savings: {$aliceSavings->formatBalance()}\n";
echo "  Bob checking: {$bobChecking->formatBalance()}\n";
echo "  Charlie credit limit: " . sprintf('$%d.%02d', $charlieCredit->getCreditLimit() / 100, $charlieCredit->getCreditLimit() % 100) . "\n";

// 存款/取款
echo "\n--- Deposits & Withdrawals ---\n";
$bank->deposit($aliceChecking->id, 30000, 'Paycheck deposit');
echo "Alice checking after deposit: {$aliceChecking->formatBalance()}\n";

$bank->withdraw($bobChecking->id, 5000, 'ATM withdrawal');
echo "Bob checking after withdrawal: {$bobChecking->formatBalance()}\n";

// 失败操作
$success = $bank->withdraw($bobChecking->id, 99999999, 'Too large withdrawal');
echo "Withdraw too much: " . ($success ? 'success' : 'failed') . "\n";

// 转账
echo "\n--- Transfers ---\n";
$bank->transfer($aliceChecking->id, $bobChecking->id, 15000, 'Loan repayment');
echo "Alice checking: {$aliceChecking->formatBalance()}\n";
echo "Bob checking: {$bobChecking->formatBalance()}\n";

// 信用账户操作
echo "\n--- Credit Account ---\n";
$bank->withdraw($charlieCredit->id, 20000, 'Purchase: Electronics');
echo "Charlie debt: {$charlieCredit->formatBalance()}\n";
echo "Available credit: " . sprintf('$%d.%02d', $charlieCredit->getAvailableCredit() / 100, $charlieCredit->getAvailableCredit() % 100) . "\n";

$bank->deposit($charlieCredit->id, 10000, 'Monthly payment');
echo "Charlie debt after payment: {$charlieCredit->formatBalance()}\n";

// 储蓄利息
echo "\n--- Interest ---\n";
$interest = $bank->applyInterest($aliceSavings->id);
echo "Alice savings interest: " . sprintf('$%d.%02d', $interest / 100, $interest % 100) . "\n";
echo "Alice savings balance: {$aliceSavings->formatBalance()}\n";

// 冻结账户
echo "\n--- Freeze Account ---\n";
$bank->freezeAccount($bobChecking->id, 'Suspicious activity');
echo "Bob checking frozen: " . ($bobChecking->isFrozen() ? 'true' : 'false') . "\n";
echo "Freeze reason: {$bobChecking->getFrozenReason()}\n";

$success = $bank->withdraw($bobChecking->id, 1000, 'While frozen');
echo "Withdraw while frozen: " . ($success ? 'success' : 'failed') . "\n";

$bank->unfreezeAccount($bobChecking->id);
echo "After unfreeze: " . ($bobChecking->isFrozen() ? 'frozen' : 'active') . "\n";

// 信用评分调整
echo "\n--- Credit Score ---\n";
$alice->adjustCreditScore(15);
echo "Alice credit score: {$alice->getCreditScore()}\n";
$bob->adjustCreditScore(-25);
echo "Bob credit score: {$bob->getCreditScore()}\n";

// 交易历史
echo "\n--- Transaction Summary ---\n";
$summary = $bank->getTransactionLog()->getSummary();
foreach ($summary as $type => $data) {
    echo "  $type: {$data['count']} transactions, total=" . sprintf('$%d.%02d', $data['total'] / 100, $data['total'] % 100) . "\n";
}

// 客户总览
echo "\n--- Customer Summary ---\n";
foreach ($bank->getCustomers() as $customer) {
    $info = $customer->toArray();
    echo "  {$info['id']}: {$info['name']} - {$info['accountCount']} accounts, balance=" . sprintf('$%d.%02d', $info['totalBalance'] / 100, abs($info['totalBalance'] % 100)) . " (credit: {$info['creditScore']})\n";
}

// 账户详情
echo "\n--- Account Details ---\n";
foreach ($bank->getAccounts() as $account) {
    echo "  {$account->id} [{$account->type}]: {$account->formatBalance()} ({$account->getTransactionCount()} transactions)\n";
}

// 银行总览
echo "\n--- Bank Summary ---\n";
$bankSummary = $bank->getBankSummary();
echo "  Name: {$bankSummary['name']}\n";
echo "  Customers: {$bankSummary['customers']}\n";
echo "  Accounts: {$bankSummary['accounts']}\n";
echo "  Account types: " . json_encode($bankSummary['accountTypes']) . "\n";
echo "  Total transactions: {$bankSummary['totalTransactions']}\n";

// 审计日志
echo "\n--- Audit Log (last 5) ---\n";
$auditLog = $bank->getAuditLog();
$recent = array_slice($auditLog, -5);
foreach ($recent as $entry) {
    echo "  {$entry['message']}\n";
}
