'use strict';
// Pod-local split DNS: Tailscale LocalAPI for MagicDNS, Cluster DNS otherwise.
const http = require('node:http');
const net = require('node:net');
const dgram = require('node:dgram');
const fs = require('node:fs');
const ZONE = 'tailcd7688.ts.net';
const clusterDNS = () => fs.readFileSync('/etc/resolv.conf', 'utf8').match(/^nameserver\s+(\S+)/m)[1];

function questionName(packet) {
  if (packet.length < 17 || packet.readUInt16BE(4) !== 1 || (packet[2] & 0x80)) throw Error('invalid query');
  const labels = [];
  let i = 12;
  while (packet[i]) {
    const n = packet[i++];
    if (n > 63 || i + n >= packet.length) throw Error('invalid name');
    labels.push(packet.subarray(i, i + n).toString('ascii').toLowerCase());
    i += n;
  }
  if (i + 5 > packet.length) throw Error('missing question');
  return labels.join('.');
}
function failure(packet) {
  const reply = Buffer.from(packet);
  if (reply.length >= 12) {
    reply[2] = (reply[2] & 1) | 0x80;
    reply[3] = 0x82; // recursion available, SERVFAIL (never leak tailnet queries).
    reply.fill(0, 6, 12);
  }
  return reply;
}
function frame(packet) {
  const size = Buffer.alloc(2);
  size.writeUInt16BE(packet.length);
  return Buffer.concat([size, packet]);
}
function exchange(packet, options = {}) {
  const name = questionName(packet);
  const tailnet = name === ZONE || name.endsWith('.' + ZONE);
  if (tailnet) {
    let end = 12;
    while (packet[end]) end += packet[end] + 1;
    const types = {1:'A', 2:'NS', 5:'CNAME', 6:'SOA', 12:'PTR', 13:'HINFO', 15:'MX', 16:'TXT', 28:'AAAA', 33:'SRV', 255:'ALL'};
    const type = types[packet.readUInt16BE(end + 1)];
    if (!type || packet.readUInt16BE(end + 3) !== 1) return Promise.reject(Error('unsupported DNS question'));
    return new Promise((resolve, reject) => {
      const request = http.get({
        socketPath: options.socketPath || '/var/run/tailscale/tailscaled.sock',
        host: 'local-tailscaled.sock',
        path: '/localapi/v0/dns-query?' + new URLSearchParams({name: name + '.', type}),
      }, response => {
        let body = '';
        response.on('data', data => { body += data; if (body.length > 200000) request.destroy(Error('oversized DNS response')); });
        response.on('error', reject);
        response.on('end', () => {
          try {
            if (response.statusCode !== 200) throw Error('Tailscale DNS unavailable');
            const bytes = Buffer.from(JSON.parse(body).Bytes, 'base64');
            if (bytes.length < 12) throw Error('invalid DNS response');
            packet.copy(bytes, 0, 0, 2); // LocalAPI generates its own transaction ID.
            resolve(bytes);
          } catch (error) { reject(error); }
        });
      });
      const timer = setTimeout(() => request.destroy(Error('DNS upstream timeout')), 4000);
      request.on('close', () => clearTimeout(timer));
      request.on('error', reject);
    });
  }
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({host: options.clusterHost || clusterDNS(), port: options.clusterPort || 53});
    let buffer = Buffer.alloc(0), done = false;
    const finish = (error, response) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      socket.destroy();
      error ? reject(error) : resolve(response);
    };
    const timer = setTimeout(() => finish(Error('DNS upstream timeout')), 4000);
    socket.on('error', error => finish(error));
    socket.on('end', () => finish(Error('DNS upstream EOF')));
    socket.on('connect', () => socket.write(frame(packet)));
    socket.on('data', chunk => {
      buffer = Buffer.concat([buffer, chunk]);
      if (buffer.length >= 2) {
        const size = buffer.readUInt16BE(0);
        if (size < 12) return finish(Error('invalid DNS response'));
        if (buffer.length >= size + 2) {
          const response = buffer.subarray(2, size + 2);
          if (!response.subarray(0, 2).equals(packet.subarray(0, 2))) return finish(Error('DNS transaction mismatch'));
          finish(null, response);
        }
      }
    });
  });
}
function start(port = 53, options = {}) {
  let active = 0;
  async function answer(packet) {
    if (active >= 128) return failure(packet);
    active++;
    try { return await exchange(packet, options); }
    catch { return failure(packet); }
    finally { active--; }
  }
  const udp = dgram.createSocket('udp4');
  udp.on('message', async (packet, peer) => {
    if (packet.length < 12) return;
    const response = await answer(packet);
    udp.send(response, peer.port, peer.address, () => {});
  });
  const tcp = net.createServer(socket => {
    socket.setTimeout(10000, () => socket.destroy());
    socket.on('error', () => {});
    let pending = Buffer.alloc(0), chain = Promise.resolve();
    socket.on('data', data => {
      pending = Buffer.concat([pending, data]);
      if (pending.length > 131072) return socket.destroy();
      while (pending.length >= 2 && pending.length >= pending.readUInt16BE(0) + 2) {
        const size = pending.readUInt16BE(0);
        const packet = Buffer.from(pending.subarray(2, size + 2));
        pending = pending.subarray(size + 2);
        if (size < 12) return socket.destroy();
        chain = chain.then(async () => {
          const response = await answer(packet);
          if (!socket.destroyed) socket.write(frame(response));
        });
      }
    });
  });
  tcp.maxConnections = 128;
  udp.bind(port, '127.0.0.1');
  tcp.listen(port, '127.0.0.1');
  return {udp, tcp};
}
if (require.main === module) start();
module.exports = {questionName, failure, frame, exchange, start};
