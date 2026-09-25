// 中继服务器自测：开一个房间，两个人加入，互相发包
'use strict';

process.env.PORT = process.env.PORT || '18931';
const assert = require('assert');
const WebSocket = require('ws');
const { server } = require('./server');

const base = `ws://127.0.0.1:${process.env.PORT}/`;

function open(query) {
  const ws = new WebSocket(base + '?' + query);
  ws.inbox = [];
  ws.waiters = [];
  ws.on('message', (data, isBinary) => {
    const msg = isBinary ? { bin: data } : JSON.parse(data.toString());
    const w = ws.waiters.shift();
    if (w) w(msg); else ws.inbox.push(msg);
  });
  return ws;
}
function next(ws) {
  if (ws.inbox.length) return Promise.resolve(ws.inbox.shift());
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), 3000);
    ws.waiters.push((m) => { clearTimeout(t); resolve(m); });
  });
}
function packet(target, text) {
  const body = Buffer.from(text);
  const b = Buffer.alloc(4 + body.length);
  b.writeInt32LE(target, 0);
  body.copy(b, 4);
  return b;
}

(async () => {
  await new Promise((r) => server.listening ? r() : server.once('listening', r));

  const host = open('mode=host&v=7&name=%E5%94%90%E4%B8%89&room=TEST');
  const w1 = await next(host);
  assert.strictEqual(w1.t, 'welcome');
  assert.strictEqual(w1.id, 1);
  assert.strictEqual(w1.room, 'TEST');

  const bad = open('mode=join&v=6&name=x&room=TEST');
  const e = await next(bad);
  assert.strictEqual(e.t, 'error');

  const a = open('mode=join&v=7&name=%E5%B0%8F%E8%88%9E&room=TEST');
  const w2 = await next(a);
  assert.strictEqual(w2.id, 2);
  assert.deepStrictEqual(w2.peers, [{ id: 1, name: '唐三' }]);
  const j = await next(host);
  assert.deepStrictEqual(j, { t: 'join', id: 2, name: '小舞' });

  const b = open('mode=join&v=7&name=b&room=test');
  const w3 = await next(b);
  assert.strictEqual(w3.id, 3);
  await next(host); await next(a); // join 通知

  // 广播
  a.send(packet(0, 'hello'));
  const p1 = await next(host);
  const p2 = await next(b);
  assert.strictEqual(p1.bin.readInt32LE(0), 2);
  assert.strictEqual(p1.bin.slice(4).toString(), 'hello');
  assert.strictEqual(p2.bin.readInt32LE(0), 2);

  // 点对点
  host.send(packet(3, 'only-b'));
  const p3 = await next(b);
  assert.strictEqual(p3.bin.readInt32LE(0), 1);
  assert.strictEqual(p3.bin.slice(4).toString(), 'only-b');
  assert.strictEqual(a.inbox.length, 0);

  // 有人离开
  b.close();
  const l = await next(host);
  assert.deepStrictEqual(l, { t: 'leave', id: 3 });
  assert.deepStrictEqual(await next(a), { t: 'leave', id: 3 });

  // 房主离开，房间解散
  host.close();
  const c = await next(a);
  assert.strictEqual(c.t, 'closed');

  console.log('relay test: all passed');
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
