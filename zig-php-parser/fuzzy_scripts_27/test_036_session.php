<?php
// Test 036: Session handling simulation, $_SESSION-like operations
class SessionLab {
    private array $sessionData = [];
    private bool $started = false;

    public function start(): void {
        $this->started = true;
        $this->sessionData = ['_started' => true, '_id' => uniqid('sess_')];
    }

    public function set(string $key, mixed $value): void {
        if (!$this->started) $this->start();
        $this->sessionData[$key] = $value;
    }

    public function get(string $key): mixed {
        if (!$this->started) return null;
        return $this->sessionData[$key] ?? null;
    }

    public function has(string $key): bool {
        return isset($this->sessionData[$key]);
    }

    public function remove(string $key): void {
        unset($this->sessionData[$key]);
    }

    public function destroy(): void {
        $this->sessionData = [];
        $this->started = false;
    }

    public function getAll(): array {
        return $this->sessionData;
    }

    public function isStarted(): bool {
        return $this->started;
    }
}

echo "=== Session simulation ===\n";
$session = new SessionLab();

echo "Is started: " . ($session->isStarted() ? 'yes' : 'no') . "\n";
$session->start();
echo "Is started after start(): " . ($session->isStarted() ? 'yes' : 'no') . "\n";

$session->set('user_id', 12345);
$session->set('username', 'testuser');
$session->set('roles', ['admin', 'editor']);
$session->set('preferences', ['theme' => 'dark', 'lang' => 'en']);

echo "user_id: " . $session->get('user_id') . "\n";
echo "username: " . $session->get('username') . "\n";
echo "roles: " . json_encode($session->get('roles')) . "\n";
echo "theme preference: " . ($session->get('preferences'))['theme'] . "\n";

echo "\n=== Session has/remove ===\n";
echo "has('username'): " . ($session->has('username') ? 'yes' : 'no') . "\n";
echo "has('nonexistent'): " . ($session->has('nonexistent') ? 'yes' : 'no') . "\n";

$session->remove('username');
echo "After remove, has('username'): " . ($session->has('username') ? 'yes' : 'no') . "\n";

echo "\n=== Session destroy ===\n";
echo "Before destroy: " . count($session->getAll()) . " keys\n";
$session->destroy();
echo "After destroy: " . count($session->getAll()) . " keys\n";

echo "\n=== Session data persistence simulation ===\n";
$session->start();
$session->set('counter', 0);

for ($i = 0; $i < 5; $i++) {
    $count = $session->get('counter') + 1;
    $session->set('counter', $count);
}
echo "Counter after 5 increments: " . $session->get('counter') . "\n";