<?php
// 验收组19：M2-2 IO 非阻塞让出（NetPoller / poll(2)）
// a) stream_socket_pair 资源形状与 meta（对齐 PHP 8.5.8）
// b) 基本读写 / 部分读 / EOF 口径（socket 短读不置 EOF）
// c) 双协程经 socket 对流 echo 往返 3 行（读写互相唤醒）
// d) timer + IO 混排：等待方 fgets 挂起时，睡眠定时器仍按点唤醒
// e) 关闭边界：对端 fclose 后先行数据可读，随后 fgets=false 且 feof=true
// f) 多协程并发写同一 socket，读侧逐行完整
// h) 跨协程分片写：fgets 跨让出点拼出一条完整行
// g) 协程活跃期普通文件 IO 保持原语义（tmpfile 回归）
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}

// ---- a) 资源形状与 meta ----
$p = stream_socket_pair(1, 1, 0);
t("a.array", is_array($p) && count($p) === 2);
t("a.type", get_resource_type($p[0]) === "stream" && get_resource_type($p[1]) === "stream");
$m = stream_get_meta_data($p[0]);
t("a.meta_shape", count($m) === 7 && !isset($m["wrapper_type"]) && !isset($m["uri"]));
t("a.meta_socket", $m["stream_type"] === "generic_socket" && $m["mode"] === "r+");
t("a.meta_flags", $m["blocked"] === true && $m["eof"] === false && $m["timed_out"] === false);
t("a.meta_misc", $m["seekable"] === false && $m["unread_bytes"] === 0);
t("a.fseek", @fseek($p[0], 0) === -1);
t("a.ftell", ftell($p[0]) === 0);

// ---- b) 基本读写 / 部分读 / EOF 口径 ----
t("b.write", fwrite($p[0], "hello\n") === 6);
t("b.read", fread($p[1], 6) === "hello\n");
t("b.eof_after_full", feof($p[1]) === false);
fwrite($p[0], "0123456789");
t("b.partial", fread($p[1], 4) === "0123");
t("b.partial_no_eof", feof($p[1]) === false);
t("b.rest", fread($p[1], 100) === "456789");
t("b.rest_no_eof", feof($p[1]) === false);
fclose($p[0]);
fclose($p[1]);

// ---- c) 双协程 echo ----
function echo_server($sock, $ready, $n) {
    $ready->send("R");
    for ($i = 0; $i < $n; $i++) {
        $line = fgets($sock);
        if ($line === false) {
            return;
        }
        fwrite($sock, "echo:" . $line);
    }
}
function echo_client($sock, $ready, $res, $n) {
    $ready->recv();
    for ($i = 0; $i < $n; $i++) {
        fwrite($sock, "L" . $i . "\n");
        $line = fgets($sock);
        $res->send($line === false ? "false" : $line);
    }
}
$p2 = stream_socket_pair(1, 1, 0);
$ready = new Channel(1);
$res = new Channel(4);
$sid = go('echo_server', $p2[1], $ready, 3);
$cid = go('echo_client', $p2[0], $ready, $res, 3);
$out = [];
for ($i = 0; $i < 3; $i++) {
    $out[] = $res->recv();
}
go_join($sid);
go_join($cid);
t("c.echo", $out[0] === "echo:L0\n" && $out[1] === "echo:L1\n" && $out[2] === "echo:L2\n");
fclose($p2[0]);
fclose($p2[1]);

// ---- d) timer + IO 混排 ----
function delayed_writer($sock, $ms) {
    usleep($ms * 1000);
    fwrite($sock, "late\n");
}
function blocking_reader($sock, $res) {
    $line = fgets($sock);
    $res->send($line === false ? "false" : $line);
}
$p3 = stream_socket_pair(1, 1, 0);
$res3 = new Channel(1);
$rid = go('blocking_reader', $p3[1], $res3);
$wid = go('delayed_writer', $p3[0], 30);
t("d.timer_io", $res3->recv() === "late\n");
go_join($wid);
go_join($rid);
fclose($p3[0]);
fclose($p3[1]);

// ---- e) 关闭边界 ----
$p4 = stream_socket_pair(1, 1, 0);
fwrite($p4[0], "last");
fclose($p4[0]);
t("e.rest", fread($p4[1], 10) === "last");
t("e.no_eof_yet", feof($p4[1]) === false);
t("e.eof_read", fread($p4[1], 10) === "");
t("e.eof_flag", feof($p4[1]) === true);
fclose($p4[1]);

// e2) 对端关闭后写入 ⇒ false（PHP 口径；SIGPIPE 已按 PHP CLI 忽略，进程不得被信号杀死）
$p7 = stream_socket_pair(1, 1, 0);
fclose($p7[0]);
t("e.write_after_close", @fwrite($p7[1], "x") === false);
t("e.read_after_close", fread($p7[1], 4) === "" && feof($p7[1]) === true);
fclose($p7[1]);

// ---- f) 多协程并发写，读侧逐行完整 ----
function writer_line($sock, $tag) {
    fwrite($sock, $tag . "\n");
}
$p5 = stream_socket_pair(1, 1, 0);
$ids = [];
for ($i = 0; $i < 3; $i++) {
    $ids[] = go('writer_line', $p5[0], "W" . $i);
}
$lines = [];
for ($i = 0; $i < 3; $i++) {
    $l = fgets($p5[1]);
    $lines[] = trim($l === false ? "false" : $l);
}
sort($lines);
t("f.multi_writer", $lines === ["W0", "W1", "W2"]);
foreach ($ids as $id) {
    go_join($id);
}
fclose($p5[0]);
fclose($p5[1]);

// ---- h) 跨协程分片写：fgets 跨让出点拼整行 ----
function slow_writer($sock) {
    fwrite($sock, "par");
    usleep(10000);
    fwrite($sock, "tial\n");
}
function reader_line($sock, $res) {
    $res->send(fgets($sock));
}
$p6 = stream_socket_pair(1, 1, 0);
$res6 = new Channel(1);
$id6 = go('reader_line', $p6[1], $res6);
$w6 = go('slow_writer', $p6[0]);
t("h.partial_line", $res6->recv() === "partial\n");
go_join($w6);
go_join($id6);
fclose($p6[0]);
fclose($p6[1]);

// ---- i) stream_get_contents / stream_get_line / fgetcsv 的 socket 路径 ----
function reader_all($sock, $res) {
    $res->send(stream_get_contents($sock));
}
$p8 = stream_socket_pair(1, 1, 0);
$res8 = new Channel(1);
$id8 = go('reader_all', $p8[1], $res8);
fwrite($p8[0], "all-in");
fclose($p8[0]);
t("i.get_contents", $res8->recv() === "all-in");
go_join($id8);
fclose($p8[1]);

function reader_line2($sock, $res) {
    $res->send(stream_get_line($sock, 0, "\n"));
}
$p9 = stream_socket_pair(1, 1, 0);
$res9 = new Channel(1);
$id9 = go('reader_line2', $p9[1], $res9);
fwrite($p9[0], "part1|part2\n");
t("i.get_line", $res9->recv() === "part1|part2");
go_join($id9);
fclose($p9[0]);
fclose($p9[1]);

$p10 = stream_socket_pair(1, 1, 0);
fwrite($p10[0], "x,y\n");
$row = fgetcsv($p10[1], null, ",", '"', "\\");
t("i.fgetcsv", is_array($row) && $row[0] === "x" && $row[1] === "y");
fclose($p10[0]);
fclose($p10[1]);

// ---- j) 非普通文件的 .blocking 读写路径（/dev/null 字符设备：poll 后就绪、read=0=EOF）----
function devnull_worker($res) {
    $r = fopen('/dev/null', 'r');
    $ok = is_resource($r) && fread($r, 8) === '' && feof($r) === true;
    if (is_resource($r)) {
        fclose($r);
    }
    $w = fopen('/dev/null', 'w');
    $ok = $ok && is_resource($w) && fwrite($w, "sink") === 4;
    if (is_resource($w)) {
        fclose($w);
    }
    $res->send($ok ? "ok" : "bad");
}
$resj = new Channel(1);
$jid = go('devnull_worker', $resj);
t("j.char_device", $resj->recv() === "ok");
go_join($jid);

// ---- g) 协程活跃期普通文件 IO（tmpfile 回归）----
function file_worker($res) {
    $f = tmpfile();
    $ok = is_resource($f)
        && fwrite($f, "abc\ndef\n") === 8
        && fseek($f, 0) === 0
        && fgets($f) === "abc\n"
        && ftell($f) === 4
        && fread($f, 4) === "def\n"
        && fread($f, 4) === ""
        && feof($f) === true;
    fclose($f);
    $res->send($ok ? "ok" : "bad");
}
$resg = new Channel(1);
$gid = go('file_worker', $resg);
t("g.file_in_coroutine", $resg->recv() === "ok");
go_join($gid);

// ---- k) stream_set_timeout 对 socket 的建模（M2-2-b）----
// k1) 非 socket 流不受理；socket 受理（秒+微秒）
$tmpk = tmpfile();
t("k.set_timeout_file", stream_set_timeout($tmpk, 1) === false);
fclose($tmpk);

$pk = stream_socket_pair(1, 1, 0);
t("k.set_timeout_sock", stream_set_timeout($pk[1], 0, 120000) === true);

// k2) fread 超时 ⇒ false；meta timed_out=true、eof=false；确实等到超时点
$tk = microtime(true);
$rk = fread($pk[1], 8);
$dtk = microtime(true) - $tk;
t("k.fread_timeout", $rk === false && $dtk >= 0.08 && $dtk < 2.0);
$mk = stream_get_meta_data($pk[1]);
t("k.fread_meta", $mk["timed_out"] === true && $mk["eof"] === false);

// k3) 数据到达后成功读 ⇒ timed_out 复位
fwrite($pk[0], "ok");
t("k.success_read", fread($pk[1], 4) === "ok");
t("k.timed_out_reset", stream_get_meta_data($pk[1])["timed_out"] === false);

// k4) fgets 半行超时 ⇒ 返回已读部分；EOF 不置位
fwrite($pk[0], "par");
t("k.fgets_partial", fgets($pk[1]) === "par");
$mk2 = stream_get_meta_data($pk[1]);
t("k.fgets_meta", $mk2["timed_out"] === true && $mk2["eof"] === false);

// k5) fgetc 超时 ⇒ false
t("k.fgetc_timeout", fgetc($pk[1]) === false);
t("k.fgetc_meta", stream_get_meta_data($pk[1])["timed_out"] === true);

// k6) stream_get_contents 超时 ⇒ 已收内容（空串）
t("k.sgc_timeout", stream_get_contents($pk[1]) === "");
t("k.sgc_meta", stream_get_meta_data($pk[1])["timed_out"] === true);

// k7) stream_get_line 超时 ⇒ false
t("k.get_line_timeout", stream_get_line($pk[1], 0, "\n") === false);
t("k.get_line_meta", stream_get_meta_data($pk[1])["timed_out"] === true);

// k8) fgetcsv 超时 ⇒ false
t("k.fgetcsv_timeout", fgetcsv($pk[1], null, ",", '"', "\\") === false);
t("k.fgetcsv_meta", stream_get_meta_data($pk[1])["timed_out"] === true);

// k9) fscanf 超时 ⇒ false
t("k.fscanf_timeout", fscanf($pk[1], "%d") === false);
t("k.fscanf_meta", stream_get_meta_data($pk[1])["timed_out"] === true);

// k10) fpassthru 超时 ⇒ -1（PHP 8.5.8 实测）
t("k.fpassthru_timeout", fpassthru($pk[1]) === -1);
t("k.fpassthru_meta", stream_get_meta_data($pk[1])["timed_out"] === true);

// k11) 超时后对端关闭：read "" + feof true，timed_out 复位
fclose($pk[0]);
t("k.eof_after_timeout", fread($pk[1], 4) === "" && feof($pk[1]) === true);
t("k.eof_meta", stream_get_meta_data($pk[1])["timed_out"] === false);
fclose($pk[1]);

// k12) (0,0) ⇒ 非阻塞读：空串、timed_out 不置位；有数据照常读
$pz = stream_socket_pair(1, 1, 0);
t("k.zero_set", stream_set_timeout($pz[1], 0, 0) === true);
$tz = microtime(true);
t("k.zero_read", fread($pz[1], 8) === "" && (microtime(true) - $tz) < 0.05);
t("k.zero_meta", stream_get_meta_data($pz[1])["timed_out"] === false);
fwrite($pz[0], "z");
t("k.zero_data", fread($pz[1], 4) === "z");
fclose($pz[0]);
fclose($pz[1]);

// k13) 负值 ⇒ 无限等（协程 30ms 后写数据，读侧不得提前超时）
function timeout_writer($sock) {
    usleep(30000);
    fwrite($sock, "neg");
}
$pn = stream_socket_pair(1, 1, 0);
t("k.neg_set", stream_set_timeout($pn[1], -1, 0) === true);
$nid = go('timeout_writer', $pn[0]);
$tn = microtime(true);
t("k.neg_infinite", fread($pn[1], 8) === "neg" && (microtime(true) - $tn) >= 0.02);
go_join($nid);
fclose($pn[0]);
fclose($pn[1]);

// ---- l) stream_set_blocking 复用非阻塞口径（M2-2-c）----
// l1) socket 受理并记账；memory/temp/input 忽略标志（既有口径不变）
$pl = stream_socket_pair(1, 1, 0);
t("l.set_false", stream_set_blocking($pl[1], false) === true);
t("l.meta_unblocked", stream_get_meta_data($pl[1])["blocked"] === false);

// l2) 非阻塞读无数据：fread ⇒ ""；feof/timed_out 均不置位；不耗时
$tl = microtime(true);
$rl = fread($pl[1], 8);
$dtl = microtime(true) - $tl;
$ml = stream_get_meta_data($pl[1]);
t("l.fread_empty", $rl === "" && $dtl < 0.05);
t("l.fread_meta", $ml["timed_out"] === false && $ml["eof"] === false);

// l3) 非阻塞 fgets/fgetc/fscanf/fgetcsv/stream_get_line 无数据 ⇒ false；stream_get_contents ⇒ ""
t("l.fgets_none", fgets($pl[1]) === false);
t("l.fgetc_none", fgetc($pl[1]) === false);
t("l.fscanf_none", fscanf($pl[1], "%d") === false);
t("l.fgetcsv_none", fgetcsv($pl[1], null, ",", '"', "\\") === false);
t("l.get_line_none", stream_get_line($pl[1], 0, "\n") === false);
t("l.sgc_none", stream_get_contents($pl[1]) === "");
$ml2 = stream_get_meta_data($pl[1]);
t("l.still_not_eof", $ml2["eof"] === false && $ml2["timed_out"] === false);

// l4) 非阻塞 fpassthru 无数据 ⇒ 0（不是 -1）；有数据 ⇒ 转发并返回字节数
t("l.fpassthru_none", fpassthru($pl[1]) === 0);
fwrite($pl[0], "AB");
echo "\n"; // fpassthru 原文转发到 stdout，独立成行以免污染断言行
$pass_n = fpassthru($pl[1]);
echo "\n";
t("l.fpassthru_data", $pass_n === 2 && stream_get_meta_data($pl[1])["eof"] === false);

// l5) 非阻塞有部分数据：fgets 返回已有部分（无换行也返回）
fwrite($pl[0], "half");
t("l.fgets_partial", fgets($pl[1]) === "half");

// l6) 非阻塞写：首写全量，塞满后 ⇒ 0（PHP 实测）
stream_set_blocking($pl[0], false);
$blob = str_repeat("y", 8192);
t("l.write_first", fwrite($pl[0], $blob) === 8192);
$last = 8192;
for ($i = 0; $i < 300; $i++) {
    $n = fwrite($pl[0], $blob);
    if ($n === false || $n < 8192) {
        $last = $n;
        break;
    }
}
t("l.write_short_or_zero", $last === 0 || (is_int($last) && $last > 0 && $last < 8192));

// l7) 恢复阻塞语义（meta blocked 随置位；读侧恢复挂起等待）
stream_set_blocking($pl[1], true);
t("l.meta_blocked", stream_get_meta_data($pl[1])["blocked"] === true);

// l8) 非阻塞下对端关闭：read "" + feof true（紧闭边界仍可识别）
$pc = stream_socket_pair(1, 1, 0);
stream_set_blocking($pc[1], false);
t("l.closed_empty", fread($pc[1], 4) === "" && feof($pc[1]) === false);
fclose($pc[0]);
t("l.closed_eof", fread($pc[1], 4) === "" && feof($pc[1]) === true);
fclose($pc[1]);

// l9) (0,0) 超时与 set_blocking(false) 同口径：fread ""、timed_out 不置位
$pz2 = stream_socket_pair(1, 1, 0);
stream_set_blocking($pz2[1], false);
stream_set_timeout($pz2[1], 0, 0);
t("l.zero_consistent", fread($pz2[1], 4) === "" && stream_get_meta_data($pz2[1])["timed_out"] === false);
stream_set_blocking($pz2[1], true);
stream_set_timeout($pz2[1], 0, 100000);
t("l.timeout_after_block", fread($pz2[1], 4) === false && stream_get_meta_data($pz2[1])["timed_out"] === true);
fclose($pz2[0]);
fclose($pz2[1]);

// l10) 非阻塞普通文件：恒就绪 ⇒ 读写语义不变（fwrite 全长、fread 正常）
$fl = tmpfile();
stream_set_blocking($fl, false);
t("l.file_write", fwrite($fl, "abc") === 3);
t("l.file_seek", fseek($fl, 0) === 0);
t("l.file_read", fread($fl, 8) === "abc" && feof($fl) === true);
t("l.file_eof", fread($fl, 8) === "" && feof($fl) === true);
fclose($fl);

fclose($pl[0]);
fclose($pl[1]);

// ---- m) 用户态读缓冲（M2-2-h）----
// m1) 非阻塞 stream_get_line 未命中分隔符 ⇒ false + 回推；下次调用拼接（PHP 实测口径）
$pm = stream_socket_pair(1, 1, 0);
stream_set_blocking($pm[1], false);
fwrite($pm[0], "abc");
t("m.get_line_first", stream_get_line($pm[1], 0, "\n") === false);
t("m.unread_after_rollback", stream_get_meta_data($pm[1])["unread_bytes"] === 3);
fwrite($pm[0], "def\n");
t("m.get_line_join", stream_get_line($pm[1], 0, "\n") === "abcdef");
t("m.unread_consumed", stream_get_meta_data($pm[1])["unread_bytes"] === 0);

// m2) 部分匹配的分隔符前缀同样回推（不丢字节）
fwrite($pm[0], "xy-");
t("m.get_line_prefix", stream_get_line($pm[1], 0, "-END") === false);
fwrite($pm[0], "END");
t("m.get_line_prefix_join", stream_get_line($pm[1], 0, "-END") === "xy");

// m3) fgets/fgetc 经同一缓冲（一次填充多字节、逐次消费）
fwrite($pm[0], "hello\nworld\n");
stream_set_blocking($pm[1], true);
t("m.fgets_1", fgets($pm[1]) === "hello\n");
t("m.fgetc_1", fgetc($pm[1]) === "w");
t("m.fgets_2", fgets($pm[1]) === "orld\n");
fclose($pm[0]);
fclose($pm[1]);

// m4) EOF 口径：缓冲耗尽后底层 read=0 才置 feof
$pe = stream_socket_pair(1, 1, 0);
fwrite($pe[0], "q");
fclose($pe[0]);
t("m.eof_buffered", fread($pe[1], 4) === "q" && feof($pe[1]) === false);
t("m.eof_after_drain", fread($pe[1], 4) === "" && feof($pe[1]) === true);
fclose($pe[1]);

// m5) fscanf 回推：socket 上多读的未消耗后缀不丢（AOT 优于 PHP seek 失败丢数据）
$ps = stream_socket_pair(1, 1, 0);
stream_set_blocking($ps[1], false);
fwrite($ps[0], "42 rest");
$rs = fscanf($ps[1], "%d");
t("m.fscanf_val", is_array($rs) && $rs[0] === 42);
t("m.fscanf_tail", fread($ps[1], 32) === " rest");
fclose($ps[0]);
fclose($ps[1]);

// m6) 普通文件不做用户态缓冲（ftell 语义不受预读影响）
$fm = tmpfile();
fwrite($fm, "0123456789");
fseek($fm, 0);
t("m.file_ftell0", ftell($fm) === 0);
t("m.file_fread3", fread($fm, 3) === "012" && ftell($fm) === 3);
t("m.file_fgets", fgets($fm) === "3456789" && feof($fm) === true);
fclose($fm);

echo "G19 DONE\n";
