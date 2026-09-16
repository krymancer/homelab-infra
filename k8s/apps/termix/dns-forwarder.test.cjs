'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const dns = require('node:dns').promises;
const {questionName, frame, exchange, start} = require('./dns-forwarder.cjs');
function query(name) {
  return Buffer.concat([Buffer.from('123401000001000000000000', 'hex'), ...name.split('.').map(x => Buffer.concat([Buffer.from([x.length]), Buffer.from(x)])), Buffer.from([0, 0, 1, 0, 1])]);
}
function reply(q) {
  const r = Buffer.from(q); r[2] = 0x81; r[3] = 0x80; r.writeUInt16BE(1, 6);
  return Buffer.concat([r, Buffer.from('c00c000100010000003c00046478d828', 'hex')]);
}
async function listen(server) { await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); return server.address().port; }
test('reject malformed queries', () => { assert.throws(() => questionName(Buffer.alloc(12))); assert.equal(questionName(query('Panam.tailcd7688.ts.net')), 'panam.tailcd7688.ts.net'); });
test('tailnet DNS uses LocalAPI; other DNS bypasses it; UDP and TCP listeners', async () => {
  let tunnels = 0, ordinary = 0;
  const socketPath = process.cwd() + '/k8s/apps/termix/.dns-test-' + process.pid + '.sock';
  const socks = require('node:http').createServer((request, response) => {
    assert.equal(request.headers.host, 'local-tailscaled.sock');
    const url = new URL(request.url, 'http://localhost');
    assert.equal(url.pathname, '/localapi/v0/dns-query');
    assert.equal(url.searchParams.get('type'), 'A');
    const q = query(url.searchParams.get('name').replace(/\.$/, ''));
    const r = reply(q); r.writeUInt16BE(9876, 0);
    tunnels++;
    response.end(JSON.stringify({Bytes:r.toString('base64')}));
  });
  await new Promise(r => socks.listen(socketPath, r));
  const cluster = net.createServer(socket => socket.on('data', data => { ordinary++; socket.end(frame(reply(data.subarray(2)))); }));
  const options = {socketPath, clusterHost: '127.0.0.1', clusterPort: await listen(cluster)};
  const q = query('panam.tailcd7688.ts.net');
  assert.deepEqual(await exchange(q, options), reply(q));
  const publicQ = query('example.org');
  assert.deepEqual(await exchange(publicQ, options), reply(publicQ));
  // Reserve a loopback port, then run both DNS transports on it.
  const reservation = net.createServer(); const port = await listen(reservation); await new Promise(r => reservation.close(r));
  const servers = start(port, options);
  await new Promise(r => servers.tcp.on('listening', r));
  const resolver = new dns.Resolver(); resolver.setServers(['127.0.0.1:' + port]);
  assert.deepEqual(await resolver.resolve4('other-host.tailcd7688.ts.net'), ['100.120.216.40']);
  const tcpReply = await new Promise((resolve, reject) => {
    const socket = net.createConnection({host:'127.0.0.1',port}, () => socket.write(frame(q)));
    socket.on('error', reject); socket.on('data', data => {socket.destroy(); resolve(data);});
  });
  assert.deepEqual(tcpReply, frame(reply(q)));
  assert.equal(tunnels, 3); assert.equal(ordinary, 1);
  servers.udp.close(); await new Promise(r => servers.tcp.close(r));
  await new Promise(r => socks.close(r)); await new Promise(r => cluster.close(r));
});
test('unavailable LocalAPI fails closed, without public DNS fallback', async () => {
  await assert.rejects(exchange(query('panam.tailcd7688.ts.net'), {socketPath: '/nonexistent/tailscaled.sock'}));
});
