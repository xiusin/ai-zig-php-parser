<?php
interface ValueObject {
    public function getValue(): mixed;
    public function equals(self $other): bool;
}

final class Money implements ValueObject {
    public function __construct(
        private int $amount,
        private string $currency
    ) {}

    public function getValue(): array { return ['amount' => $this->amount, 'currency' => $this->currency]; }

    public function equals(self $other): bool {
        return $this->amount === $other->amount && $this->currency === $other->currency;
    }

    public static function of(int $amount, string $currency): self {
        return new self($amount, $currency);
    }

    public function add(self $other): self {
        if ($this->currency !== $other->currency) {
            throw new InvalidArgumentException("Currency mismatch");
        }
        return new self($this->amount + $other->amount, $this->currency);
    }

    public function multiply(float $factor): self {
        return new self((int)($this->amount * $factor), $this->currency);
    }
}

$yen = Money::of(1000, 'JPY');
$yen2 = Money::of(500, 'JPY');
$sum = $yen->add($yen2);
echo $sum->getValue()['amount'] . "\n";
echo $yen->equals($yen2) ? 'true' : 'false' . "\n";
echo $yen->multiply(1.5)->getValue()['amount'] . "\n";
echo "OK\n";
