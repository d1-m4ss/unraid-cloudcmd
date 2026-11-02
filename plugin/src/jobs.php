<?php
// cloudcmd.main: background copy/move jobs (rsync) with persistent state. POST only (CSRF is enforced by the webGUI).
//
// Trust model: the Cloud Commander container (uid 99) can write anywhere under /mnt/user, so no root write or read
// ever touches a path under /mnt/user except the validated source/destination (done by the unprivileged runner).
// Job definitions live on the flash drive (persistent, root only); runtime state lives in a root-owned RAM dir.
header('Content-Type: application/json');
header('Cache-Control: no-store');

const DEFS = '/boot/config/plugins/cloudcmd.main/jobs';   // <id>.json, survives reboot
const RUN = '/var/local/cloudcmd.main/jobs';              // <id>/{job.json,cancel,started,w/}, w/ is writable by the runner only
const RUNNER = '/usr/local/emhttp/plugins/cloudcmd.main/job-run.sh';
const ROOTS = ['/user' => '/mnt/user', '/disks' => '/mnt/disks', '/remotes' => '/mnt/remotes'];
const MAX_NAMES = 2000;
const CFG = '/boot/config/plugins/cloudcmd.main/cloudcmd.cfg';   // {"url": "..."}: address of Cloud Commander as the browser reaches it

function out($data, $code = 200) {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

function fail($msg, $code = 400, $extra = []) {
    out(['ok' => false, 'error' => $msg] + $extra, $code);
}

// Container path (/user/..., /disks/..., /remotes/...) -> [real host path, normalized container path, root key] or null.
function host_path($c) {
    if (!is_string($c) || $c === '' || $c[0] !== '/' || strpos($c, "\0") !== false) return null;
    foreach (explode('/', $c) as $seg) if ($seg === '..') return null;
    $c = '/' . trim(preg_replace('#/+#', '/', $c), '/');
    foreach (ROOTS as $cp => $hp) {
        if ($c === $cp || strpos($c, $cp . '/') === 0) {
            $r = realpath($hp . substr($c, strlen($cp)));
            if ($r === false || !is_dir($r)) return null;
            if ($r !== $hp && strpos($r, $hp . '/') !== 0) return null;
            return [$r, $c, $cp];
        }
    }
    return null;
}

function valid_id($id) {
    return is_string($id) && preg_match('/^\d{8}-\d{6}-[0-9a-f]{6}$/', $id);
}

function read_json($f) {
    if (is_link($f)) return null;
    $d = @json_decode(@file_get_contents($f), true);
    return is_array($d) ? $d : null;
}

function ensure_dir($d, $mode = 0755) {
    if (!is_dir($d)) @mkdir($d, $mode, true);
    return is_dir($d) && !is_link($d);
}

function pid_alive($pid, $id) {
    $pid = (int)$pid;
    if ($pid <= 0) return false;
    $cl = @file_get_contents("/proc/$pid/cmdline");
    return $cl !== false && strpos($cl, 'job-run.sh') !== false && strpos($cl, $id) !== false;
}

function spawn($id, $pct) {
    $dir = RUN . '/' . $id;
    @unlink("$dir/started");
    touch("$dir/started");
    exec('nohup setsid setpriv --reuid=99 --regid=100 --clear-groups ' . escapeshellarg(RUNNER) . ' ' .
        escapeshellarg($dir) . ' ' . (int)$pct . ' >/dev/null 2>&1 &');
}

// Create the runtime dir for a job (root-owned; w/ writable by the runner).
function prepare_run($id, $def) {
    $dir = RUN . '/' . $id;
    if (!ensure_dir(RUN) || !ensure_dir($dir)) return false;
    $lock = RUN . '/.lock';
    if (!file_exists($lock)) { file_put_contents($lock, ''); chmod($lock, 0644); }
    if (!ensure_dir("$dir/w")) return false;
    chown("$dir/w", 99);
    chgrp("$dir/w", 100);
    file_put_contents("$dir/job.json", json_encode($def, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
    return true;
}

function job_view($id) {
    $def = read_json(DEFS . "/$id.json");
    if (!$def) return null;
    $dir = RUN . '/' . $id;
    $st = read_json("$dir/w/status.json");
    if (!$st) {
        $young = file_exists("$dir/started") && time() - (int)@filemtime("$dir/started") < 10;
        $st = ['state' => $young ? 'queued' : 'interrupted', 'pct' => 0, 'bytes' => 0, 'rate' => '', 'eta' => '', 'msg' => '', 'pid' => 0];
        if (!$young && !is_dir($dir)) $st['msg'] = 'interrupted by a restart';
    } elseif (in_array($st['state'], ['queued', 'running'], true) && !pid_alive($st['pid'], $id)) {
        $st['state'] = file_exists("$dir/cancel") ? 'cancelled' : 'interrupted';
        $st['rate'] = $st['eta'] = '';
    }
    return [
        'id' => $id, 'op' => $def['op'], 'src' => $def['src_c'], 'dst' => $def['dst_c'], 'names' => $def['names'],
        'created' => $def['created'], 'state' => $st['state'], 'pct' => (int)$st['pct'], 'bytes' => (int)$st['bytes'],
        'rate' => $st['rate'], 'eta' => $st['eta'], 'msg' => $st['msg'],
    ];
}

function rm_tree($p) {
    if (is_link($p) || is_file($p)) { @unlink($p); return; }
    if (!is_dir($p)) return;
    foreach (scandir($p) as $f) if ($f !== '.' && $f !== '..') rm_tree("$p/$f");
    @rmdir($p);
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') fail('POST only', 405);
if (!ensure_dir(DEFS) || !ensure_dir(RUN)) fail('job storage is not available', 500);

$action = $_POST['action'] ?? '';

if ($action === 'list') {
    $ids = [];
    foreach (scandir(DEFS, SCANDIR_SORT_DESCENDING) as $f) {
        if (substr($f, -5) === '.json' && valid_id(substr($f, 0, -5))) $ids[] = substr($f, 0, -5);
    }
    $jobs = [];
    foreach (array_slice($ids, 0, 200) as $id) if ($v = job_view($id)) $jobs[] = $v;
    out(['ok' => true, 'jobs' => $jobs]);
}

if ($action === 'start') {
    $op = $_POST['op'] ?? '';
    if (!in_array($op, ['copy', 'move'], true)) fail('bad operation');
    $rawNames = $_POST['names'] ?? '';
    if (!is_string($rawNames)) fail('bad item list');
    $names = json_decode($rawNames, true);
    if (!is_array($names) || !$names || count($names) > MAX_NAMES) fail('bad item list');
    $s = host_path($_POST['src'] ?? null);
    $d = host_path($_POST['dst'] ?? null);
    if (!$s || !$d) fail('source or destination is not available');
    if ($d[2] === '/remotes') fail('destination is read-only');
    if ($op === 'move' && $s[2] === '/remotes') fail('cannot move out of a read-only location');
    if ($s[0] === $d[0]) fail('source and destination are the same folder');
    $exists = [];
    foreach ($names as $n) {
        if (!is_string($n) || $n === '' || $n === '.' || $n === '..' || strpos($n, '/') !== false || preg_match('/[\x00-\x1f\x7f]/', $n)) {
            fail('unsupported item name (empty, "..", "/" or control characters)');
        }
        $p = $s[0] . '/' . $n;
        if (!file_exists($p) && !is_link($p)) fail('item not found: ' . $n);
        if (is_dir($p) && !is_link($p)) {
            $r = realpath($p);
            if ($d[0] === $r || strpos($d[0] . '/', $r . '/') === 0) fail('destination is inside the source: ' . $n);
        }
        if (file_exists($d[0] . '/' . $n) || is_link($d[0] . '/' . $n)) $exists[] = $n;
    }
    if ($exists && ($_POST['overwrite'] ?? '') !== '1') {
        fail('already exist in the destination', 409, ['code' => 'exists', 'exists' => array_slice($exists, 0, 20), 'existsCount' => count($exists)]);
    }
    $id = date('Ymd-His') . '-' . bin2hex(random_bytes(3));
    $def = ['id' => $id, 'op' => $op, 'src' => $s[0], 'dst' => $d[0], 'src_c' => $s[1], 'dst_c' => $d[1], 'names' => array_values($names), 'created' => time()];
    if (!prepare_run($id, $def)) fail('cannot create job', 500);
    file_put_contents(DEFS . "/$id.json", json_encode($def, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
    spawn($id, 0);
    out(['ok' => true, 'id' => $id]);
}

if ($action === 'setcfg') {
    $u = $_POST['url'] ?? '';
    if (!is_string($u) || strlen($u) > 300) fail('bad address');
    if ($u === '') {
        @unlink(CFG);
        out(['ok' => true]);
    }
    if (!preg_match('#^https?://[^\s<>"\'\\\\]+$#', $u) || !parse_url($u, PHP_URL_HOST)) fail('the address must look like http://host:port/ or https://host/path/');
    if (file_put_contents(CFG, json_encode(['url' => $u], JSON_UNESCAPED_SLASHES)) === false) fail('cannot save the address', 500);
    out(['ok' => true]);
}

$id = $_POST['id'] ?? '';
if (!valid_id($id)) fail('unknown job', 404);
$v = job_view($id);
if (!$v) fail('unknown job', 404);
$dir = RUN . '/' . $id;

if ($action === 'cancel') {
    if (!in_array($v['state'], ['queued', 'running'], true)) fail('job is not running');
    touch("$dir/cancel");
    $st = read_json("$dir/w/status.json");
    if ($st && pid_alive($st['pid'], $id)) exec('kill -TERM -- -' . (int)$st['pid']);
    out(['ok' => true]);
}

if ($action === 'resume') {
    if (!in_array($v['state'], ['interrupted', 'cancelled', 'failed'], true)) fail('job cannot be resumed');
    $def = read_json(DEFS . "/$id.json");
    if (!$def || !prepare_run($id, $def)) fail('cannot prepare job', 500);
    @unlink("$dir/cancel");
    @unlink("$dir/w/status.json");
    spawn($id, $v['pct']);
    out(['ok' => true]);
}

if ($action === 'dismiss') {
    if (in_array($v['state'], ['queued', 'running'], true)) fail('job is running');
    @unlink(DEFS . "/$id.json");
    rm_tree($dir);
    out(['ok' => true]);
}

fail('unknown action');
