// 斗罗大陆·猎魂 —— 联机中继服务器
//
// 服务器只做一件事：把同一个房间里各个玩家的数据包转发给彼此。
// 游戏逻辑（魂兽、伤害、金魂币）都在房主的电脑上算，这里不参与。
//
// 连接：   wss://<host>/?mode=host&v=<协议版本>&name=<名字>[&room=<指定房间码>]
//          wss://<host>/?mode=join&v=<协议版本>&name=<名字>&room=<房间码>
// 文本帧： 服务器发出的控制消息（JSON）：welcome / join / leave / closed / error
// 二进制帧：客户端 → 服务器：[int32 目标][数据]，目标 0 = 房间里其他所有人
//          服务器 → 客户端：[int32 来源][数据]

'use strict';

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT) || 8080;
const MAX_PEERS = 8;
const MAX_ROOMS = 500;
const MAX_MSG = 256 * 1024;
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 去掉了容易看错的 I O 0 1

const rooms = new Map(); // code -> { v, hostName, peers: Map<id, ws>, nextId, created }

function makeCode() {
  for (let tries = 0; tries < 100; tries++) {
    let c = '';
    for (let i = 0; i < 4; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    if (!rooms.has(c)) return c;
  }
  return null;
}

function sendJson(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function cleanName(s) {
  s = String(s || '').replace(/[\u0000-\u001f<>]/g, '').trim();
  return s.slice(0, 12) || '魂师';
}

const server = http.createServer((req, res) => {
  if (req.url === '/health' || req.url === '/health/') {
    res.writeHead(200, { 'content-type': 'text/plain', 'access-control-allow-origin': '*' });
    res.end('ok');
    return;
  }
  res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
  let peers = 0;
  for (const r of rooms.values()) peers += r.peers.size;
  res.end(`斗罗大陆·猎魂 联机服务器\n房间 ${rooms.size} 个，在线 ${peers} 人\n`);
});

const wss = new WebSocketServer({ server, maxPayload: MAX_MSG });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, 'http://x');
  const mode = url.searchParams.get('mode');
  const v = url.searchParams.get('v') || '0';
  const name = cleanName(url.searchParams.get('name'));
  let code = (url.searchParams.get('room') || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8);

  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  let room;
  let id;
  if (mode === 'host') {
    if (rooms.size >= MAX_ROOMS) { sendJson(ws, { t: 'error', msg: '服务器房间已满，请稍后再试' }); ws.close(); return; }
    if (!code || rooms.has(code)) code = makeCode();
    if (!code) { sendJson(ws, { t: 'error', msg: '无法创建房间' }); ws.close(); return; }
    room = { v, peers: new Map(), names: new Map(), nextId: 2, created: Date.now() };
    rooms.set(code, room);
    id = 1;
  } else if (mode === 'join') {
    room = rooms.get(code);
    if (!room) { sendJson(ws, { t: 'error', msg: `找不到房间 ${code || ''}` }); ws.close(); return; }
    if (room.v !== v) { sendJson(ws, { t: 'error', msg: '游戏版本和房主不一致，请下载最新版' }); ws.close(); return; }
    if (room.peers.size >= MAX_PEERS) { sendJson(ws, { t: 'error', msg: '房间已满（最多 8 人）' }); ws.close(); return; }
    id = room.nextId++;
  } else {
    sendJson(ws, { t: 'error', msg: '参数错误' });
    ws.close();
    return;
  }

  const peers = [];
  for (const [pid, n] of room.names) peers.push({ id: pid, name: n });
  room.peers.set(id, ws);
  room.names.set(id, name);
  sendJson(ws, { t: 'welcome', id, room: code, peers });
  for (const [pid, other] of room.peers) if (pid !== id) sendJson(other, { t: 'join', id, name });

  ws.on('message', (data, isBinary) => {
    ws.isAlive = true;
    if (!isBinary) {
      // 文本帧只用来保活
      return;
    }
    const buf = Buffer.isBuffer(data) ? data : Buffer.concat(data);
    if (buf.length < 4) return;
    const target = buf.readInt32LE(0);
    buf.writeInt32LE(id, 0); // 把目标换成来源，原地复用这块内存
    if (target === 0) {
      for (const [pid, other] of room.peers) {
        if (pid !== id && other.readyState === other.OPEN) other.send(buf, { binary: true });
      }
    } else {
      const other = room.peers.get(target);
      if (other && other.readyState === other.OPEN) other.send(buf, { binary: true });
    }
  });

  ws.on('close', () => {
    if (!room.peers.has(id)) return;
    room.peers.delete(id);
    room.names.delete(id);
    if (id === 1) {
      // 房主离开，房间解散
      for (const other of room.peers.values()) {
        sendJson(other, { t: 'closed', msg: '房主已离开，房间解散' });
        other.close();
      }
      rooms.delete(code);
    } else {
      for (const other of room.peers.values()) sendJson(other, { t: 'leave', id });
    }
  });
});

// 每 20 秒检查一次，掉线的连接清掉
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 20000);
wss.on('close', () => clearInterval(heartbeat));

server.listen(PORT, () => {
  console.log(`relay listening on :${PORT}`);
});

module.exports = { server, wss, rooms };
