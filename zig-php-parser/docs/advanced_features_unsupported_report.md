# 高级特性不支持清单

**生成时间**: 2026-03-12T16:21:04.187895

## 概述

本报告列出了PHP解释器/AOT编译器当前**不支持的高级特性**。


## CHANNEL 类特性 (5个不支持)


### PHP_FATAL

- **channel_buffered_033.php**: Channel测试
  - 代码: `$ch = new chan(3); $ch->push(1); $ch->push(2); $ch->push(3); echo $ch->pop() + $ch->pop() + $ch->pop...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "chan" not found in /Users/tuoke/Desktop`
- **channel_coroutine_032.php**: 协程测试
  - 代码: `$ch = new chan(1); co::run(function() use ($ch) {     $ch->push("from coro"); }); echo $ch->pop();...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "chan" not found in /Users/tuoke/Desktop`
- **channel_create_030.php**: Channel测试
  - 代码: `$ch = new chan(1); var_dump($ch);`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "chan" not found in /Users/tuoke/Desktop`
- **channel_push_pop_031.php**: Channel测试
  - 代码: `$ch = new chan(1); $ch->push("hello"); $val = $ch->pop(); echo $val;`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "chan" not found in /Users/tuoke/Desktop`
- **channel_select_034.php**: Channel测试
  - 代码: `$ch1 = new chan(1); $ch2 = new chan(1); $ch1->push("ch1"); $ret = chan::select([$ch1, $ch2], 1.0); e...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "chan" not found in /Users/tuoke/Desktop`

## COROUTINE 类特性 (10个不支持)


### PHP_FATAL

- **coroutine_dns_029.php**: 协程测试
  - 代码: `co::run(function() {     $ip = co::gethostbyname("localhost");     echo $ip ? "resolved" : "failed";...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`
- **coroutine_fgets_028.php**: 协程测试
  - 代码: `co::run(function() {     $fp = fopen("/tmp/test.txt", "w+");     fwrite($fp, "test");     fseek($fp,...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`
- **coroutine_getCid_025.php**: 协程测试
  - 代码: `co::run(function() {     $cid = co::getCid();     echo $cid > 0 ? "yes" : "no"; });`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`
- **coroutine_getuid_026.php**: 协程测试
  - 代码: `co::run(function() {     echo co::getuid(); });`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`
- **coroutine_resume_024.php**: 协程测试
  - 代码: `$cid = null; co::run(function() use (&$cid) {     $cid = co::getCid();     co::yield();     echo "re...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`
- **coroutine_sleep_022.php**: 协程测试
  - 代码: `co::run(function() {     co::sleep(0.001);     echo "woke"; });`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`
- **coroutine_stats_027.php**: 协程测试
  - 代码: `co::run(function() {     $stats = co::stats();     echo is_array($stats) ? "yes" : "no"; });`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`
- **coroutine_swoole_021.php**: 协程测试
  - 代码: `co::run(function() {     echo "swoole coro"; });`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`
- **coroutine_yield_023.php**: 协程测试
  - 代码: `co::run(function() {     co::yield();     echo "resumed"; });`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "co" not found in /Users/tuoke/Desktop/a`

### PHP_PARSE

- **coroutine_go_020.php**: 协程测试
  - 代码: `// go function test go function() {     echo "coroutine"; }();`
  - PHP错误: `PHP Parse error:  syntax error, unexpected token "function" in /Users/tuoke/Desk`

## FIBER 类特性 (8个不支持)


### AOT_FIBER_UNSUPPORTED

- **fiber_basic_012.php**: Fiber测试
  - 代码: `$fiber = new Fiber(function () {     echo "in fiber";     Fiber::suspend();     echo "resumed"; }); ...`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`
- **fiber_getCurrent_014.php**: Fiber测试
  - 代码: `$fiber = new Fiber(function () {     $f = Fiber::getCurrent();     echo $f ? "yes" : "no"; }); $fibe...`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`
- **fiber_loop_019.php**: Fiber测试
  - 代码: `$fiber = new Fiber(function () {     for ($i = 0; $i < 3; $i++) {         Fiber::suspend($i);     } ...`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`
- **fiber_nested_018.php**: Fiber测试
  - 代码: `$f1 = new Fiber(function () {     $f2 = new Fiber(function () {         echo "inner";     });     $f...`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`
- **fiber_return_016.php**: Fiber测试
  - 代码: `$fiber = new Fiber(function () {     Fiber::suspend();     return "done"; }); $fiber->start(); $fibe...`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`
- **fiber_states_015.php**: Fiber测试
  - 代码: `$fiber = new Fiber(function () {     Fiber::suspend(); }); echo $fiber->isStarted() ? "1" : "0"; $fi...`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`
- **fiber_throw_017.php**: Fiber测试
  - 代码: `$fiber = new Fiber(function () {     try {         Fiber::suspend();     } catch (Exception $e) {   ...`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`
- **fiber_value_013.php**: Fiber测试
  - 代码: `$fiber = new Fiber(function () {     $x = Fiber::suspend(1);     echo $x; }); $val = $fiber->start()...`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`

## GENERATOR 类特性 (11个不支持)


### AOT_GENERATOR_UNSUPPORTED

- **generator_getReturn_005.php**: Generator测试
  - 代码: `function gen() {     yield 1;     return "done"; } $g = gen(); foreach ($g as $val) {} echo $g->getR...`
  - AOT错误: `error: UnknownMethod /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigp`
- **generator_recursive_007.php**: Generator测试
  - 代码: `function gen($n) {     if ($n > 0) {         yield $n;         yield from gen($n - 1);     } } forea...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`
- **generator_rewind_010.php**: Generator测试
  - 代码: `function gen() {     yield 1;     yield 2; } $g = gen(); echo $g->current(); $g->next(); echo $g->cu...`
  - AOT错误: `error: NotAnObject /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp`
- **generator_send_003.php**: Generator测试
  - 代码: `function gen() {     $x = yield 1;     yield $x + 10; } $g = gen(); echo $g->current(); $g->send(5);...`
  - AOT错误: `error: NotAnObject /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp`
- **generator_throw_006.php**: Generator测试
  - 代码: `function gen() {     try {         yield 1;     } catch (Exception $e) {         yield "caught";    ...`
  - AOT错误: `error: NotAnObject /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp`
- **generator_valid_009.php**: Generator测试
  - 代码: `function gen() {     yield 1;     yield 2; } $g = gen(); while ($g->valid()) {     echo $g->current(...`
  - AOT错误: `error: NotAnObject /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp`
- **generator_yield_from_002.php**: Generator测试
  - 代码: `function gen1() {     yield 1;     yield 2; } function gen2() {     yield from gen1();     yield 3; ...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`

### OTHER

- **generator_basic_000.php**: Generator测试
  - 代码: `function gen() {     yield 1;     yield 2;     yield 3; } $g = gen(); foreach ($g as $val) {     ech...`
- **generator_class_008.php**: Generator测试
  - 代码: `class MyGen {     public function gen() {         yield 1;     } } $obj = new MyGen(); $g = $obj->ge...`
- **generator_key_001.php**: Generator测试
  - 代码: `function gen() {     yield 'a' => 1;     yield 'b' => 2; } foreach (gen() as $k => $v) {     echo $k...`
- **generator_return_004.php**: Generator测试
  - 代码: `function gen() {     yield 1;     yield 2;     return 3; } $g = gen(); foreach ($g as $val) {     ec...`

## MSG 类特性 (1个不支持)


### OTHER

- **msg_queue_047.php**: IPC测试
  - 代码: `$msg_key = ftok(__FILE__, 'm'); $queue = msg_get_queue($msg_key); if ($queue) {     echo "queue";   ...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`

## MUTEX 类特性 (3个不支持)


### PHP_FATAL

- **mutex_basic_035.php**: 锁测试
  - 代码: `$mutex = new mutex(); $mutex->lock(); echo "locked"; $mutex->unlock(); echo "unlocked";`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "mutex" not found in /Users/tuoke/Deskto`
- **mutex_coroutine_040.php**: 协程测试
  - 代码: `$mutex = new mutex(); $counter = 0; co::run(function() use ($mutex, &$counter) {     $mutex->lock();...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "mutex" not found in /Users/tuoke/Deskto`
- **mutex_trylock_036.php**: 锁测试
  - 代码: `$mutex = new mutex(); $ret = $mutex->trylock(); echo $ret ? "acquired" : "failed"; $mutex->unlock();...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "mutex" not found in /Users/tuoke/Deskto`

## PARALLEL 类特性 (3个不支持)


### PHP_PARSE

- **parallel_channel_056.php**: Channel测试
  - 代码: `$channel = new \parallel\Channel(1); \parallel un(function() use ($channel) {     $channel->send("he...`
  - PHP错误: `PHP Parse error:  syntax error, unexpected identifier "un" in /Users/tuoke/Deskt`
- **parallel_events_057.php**: 线程测试
  - 代码: `$events = new \parallel\Events(); $channel = new \parallel\Channel(1); $events->addChannel($channel)...`
  - PHP错误: `PHP Parse error:  syntax error, unexpected identifier "un" in /Users/tuoke/Deskt`
- **parallel_run_055.php**: 线程测试
  - 代码: `$future = \parallel un(function() {     return "parallel"; }); echo $future->value();`
  - PHP错误: `PHP Parse error:  syntax error, unexpected identifier "un" in /Users/tuoke/Deskt`

## PCNTL 类特性 (4个不支持)


### AOT_PCNTL_UNSUPPORTED

- **pcntl_alarm_044.php**: 进程控制测试
  - 代码: `pcntl_signal(SIGALRM, function() {     echo "alarm"; }); pcntl_alarm(1); sleep(2); pcntl_signal_disp...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`
- **pcntl_fork_041.php**: 进程控制测试
  - 代码: `$pid = pcntl_fork(); if ($pid == -1) {     echo "fail"; } elseif ($pid == 0) {     echo "child";    ...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`
- **pcntl_signal_043.php**: 进程控制测试
  - 代码: `pcntl_signal(SIGUSR1, function($signo) {     echo "signal"; }); posix_kill(posix_getpid(), SIGUSR1);...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`
- **pcntl_wait_042.php**: 进程控制测试
  - 代码: `$pid = pcntl_fork(); if ($pid == 0) {     exit(42); } else {     pcntl_wait($status);     echo pcntl...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`

## POSIX 类特性 (1个不支持)


### OTHER

- **posix_fifo_050.php**: 高级特性测试
  - 代码: `$fifo = "/tmp/test_fifo"; if (posix_mkfifo($fifo, 0666)) {     echo "fifo";     unlink($fifo); }...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`

## PTHREADS 类特性 (4个不支持)


### PHP_FATAL

- **pthreads_thread_051.php**: 线程测试
  - 代码: `class MyThread extends Thread {     public function run() {         echo "thread";     } } $t = new ...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "Thread" not found in /Users/tuoke/Deskt`
- **pthreads_threaded_053.php**: 线程测试
  - 代码: `class Shared extends Threaded {     public $value = 0; } $shared = new Shared(); $shared->value = 1;...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "Threaded" not found in /Users/tuoke/Des`
- **pthreads_volatile_054.php**: 线程测试
  - 代码: `$volatile = new Volatile(); $volatile["key"] = "value"; echo $volatile["key"];`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "Volatile" not found in /Users/tuoke/Des`
- **pthreads_worker_052.php**: 线程测试
  - 代码: `$worker = new Worker(); $worker->start(); $worker->stack(new class extends Threaded {     public fun...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "Worker" not found in /Users/tuoke/Deskt`

## REFL 类特性 (2个不支持)


### AOT_GENERATOR_UNSUPPORTED

- **refl_generator_087.php**: Generator测试
  - 代码: `function gen() { yield 1; } $r = new ReflectionGenerator(gen()); echo $r->getExecutingLine();`
  - AOT错误: `error: MethodNotFound /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zig`

### PHP_FATAL

- **refl_fiber_088.php**: Fiber测试
  - 代码: `$f = new Fiber(function() { Fiber::suspend(); }); $f->start(); $rf = new ReflectionFiber($f); echo $...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Call to undefined method ReflectionFiber::getS`

## RWLOCK 类特性 (2个不支持)


### PHP_FATAL

- **rwlock_read_037.php**: 高级特性测试
  - 代码: `$lock = new rwlock(); $lock->rdlock(); echo "read locked"; $lock->unlock();`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "rwlock" not found in /Users/tuoke/Deskt`
- **rwlock_write_038.php**: 高级特性测试
  - 代码: `$lock = new rwlock(); $lock->wrlock(); echo "write locked"; $lock->unlock();`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "rwlock" not found in /Users/tuoke/Deskt`

## SEM 类特性 (1个不支持)


### OTHER

- **sem_sysv_048.php**: IPC测试
  - 代码: `$sem_key = ftok(__FILE__, 's'); $sem = sem_get($sem_key, 1); if ($sem) {     echo "semaphore";     s...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`

## SEMAPHORE 类特性 (1个不支持)


### PHP_FATAL

- **semaphore_039.php**: IPC测试
  - 代码: `$sem = new semaphore(2); $sem->acquire(); echo "acquired"; $sem->release();`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Class "semaphore" not found in /Users/tuoke/De`

## SHMOP 类特性 (1个不支持)


### OTHER

- **shmop_046.php**: IPC测试
  - 代码: `$shm_key = ftok(__FILE__, 't'); $shm_id = shmop_open($shm_key, "c", 0644, 100); if ($shm_id) {     e...`
  - PHP错误: `PHP Deprecated:  Function shmop_close() is deprecated since 8.0, as Shmop object`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`

## SIGNAL 类特性 (4个不支持)


### AOT_PCNTL_UNSUPPORTED

- **signal_dispatch_058.php**: 信号测试
  - 代码: `pcntl_signal(SIGTERM, function() { echo "term"; }); posix_kill(posix_getpid(), SIGTERM); pcntl_signa...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`
- **signal_mask_059.php**: 信号测试
  - 代码: `pcntl_sigprocmask(SIG_BLOCK, [SIGTERM]); echo "blocked"; pcntl_sigprocmask(SIG_UNBLOCK, [SIGTERM]); ...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`

### PHP_FATAL

- **signal_timedwait_060.php**: 信号测试
  - 代码: `pcntl_sigprocmask(SIG_BLOCK, [SIGUSR1]); posix_kill(posix_getpid(), SIGUSR1); $info = []; $signo = p...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Call to undefined function pcntl_sigtimedwait(`
- **signal_waitinfo_061.php**: 信号测试
  - 代码: `pcntl_sigprocmask(SIG_BLOCK, [SIGUSR1]); posix_kill(posix_getpid(), SIGUSR1); $info = []; $signo = p...`
  - PHP错误: `PHP Fatal error:  Uncaught Error: Call to undefined function pcntl_sigwaitinfo()`

## SOCKET 类特性 (1个不支持)


### OTHER

- **socket_pair_049.php**: 高级特性测试
  - 代码: `$sockets = []; if (socket_create_pair(AF_UNIX, SOCK_STREAM, 0, $sockets)) {     echo "pair";     soc...`
  - AOT错误: `warning: unable to open library directory '/usr/local/lib': FileNotFound main.zi`

## THROW 类特性 (1个不支持)


### PHP_FATAL

- **throw_expr_081.php**: 高级特性测试
  - 代码: `$val = null; $result = $val ?? throw new Exception("null");`
  - PHP错误: `PHP Fatal error:  Uncaught Exception: null in /Users/tuoke/Desktop/ai-zig-php-pa`

## TRAIT 类特性 (2个不支持)


### PHP_FATAL

- **trait_conflict_086.php**: 高级特性测试
  - 代码: `trait TConflictA { public function foo() { return "A"; } } trait TConflictB { public function foo() ...`
  - PHP错误: `PHP Fatal error:  Trait method TConflictB::foo has not been applied as TraitConf`
- **trait_constants_conflict_090.php**: 高级特性测试
  - 代码: `trait ConflictConstOne { const VALUE = "A"; } trait ConflictConstTwo { const VALUE = "B"; } class Co...`
  - PHP错误: `PHP Fatal error:  ConflictConstOne and ConflictConstTwo define the same constant`

## UNPACK 类特性 (1个不支持)


### OTHER

- **unpack_string_keys_074.php**: 高级特性测试
  - 代码: `$a = ['x' => 1]; $b = ['y' => 2]; $c = [...$a, ...$b]; print_r($c);`
  - AOT错误: `Array (     [x] => 1     [y] => 2 ) `

## 后续开发建议

根据测试结果，建议按以下优先级实现高级特性：

### P0 - 核心协程支持
- [ ] Generator/yield 完整支持（包括send/throw）
- [ ] Fiber 完整支持
- [ ] go关键字协程调度

### P1 - 并发原语
- [ ] Channel（chan）支持
- [ ] Mutex/RWMutex 支持
- [ ] Semaphore 支持
- [ ] WaitGroup 支持

### P2 - 进程控制
- [ ] pcntl_fork/wait
- [ ] 信号处理（pcntl_signal）
- [ ] 进程间通信（共享内存、消息队列）

### P3 - PHP 8.x新特性
- [ ] 枚举（Enum）
- [ ] 只读类/属性
- [ ] 属性（Attribute）
- [ ] match表达式
- [ ] nullsafe运算符
- [ ] 联合类型/intersection类型
- [ ] First-class callable

### P4 - 其他高级特性
- [ ] 线程支持（pthreads/parallel）
- [ ] 弱引用/WeakMap
- [ ] 属性钩子（PHP 8.4）

