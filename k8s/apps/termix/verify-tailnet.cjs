'use strict';
// Run inside Termix via kubectl exec -i ... -- node - HOST < this-file.
// Exercises local hostname lookup + loopback SOCKS5 + SSH banner, no credentials.
const dns = require('node:dns').promises;
const net = require('node:net');
(async () => {
  const host = process.argv[2] || 'panam';
  const {address} = await dns.lookup(host, {family: 4});
  console.log('Local DNS:', host, '->', address);
  await new Promise((resolve, reject) => {
    const socket = net.createConnection(1080, '127.0.0.1');
    let state = 0, pending = Buffer.alloc(0);
    const timer = setTimeout(() => socket.destroy(Error('SOCKS/SSH banner timeout')), 12000);
    socket.on('error', reject);
    socket.on('close', () => clearTimeout(timer));
    socket.on('end', () => reject(Error('EOF before SSH banner')));
    socket.on('connect', () => socket.write(Buffer.from([5,1,0])));
    socket.on('data', data => {
      pending = Buffer.concat([pending, data]);
      if (state === 0 && pending.length >= 2) {
        if (pending[0] !== 5 || pending[1] !== 0) return socket.destroy(Error('SOCKS greeting rejected'));
        pending = pending.subarray(2); state = 1;
        socket.write(Buffer.from([5,1,0,1,...address.split('.').map(Number),0,22]));
      }
      if (state === 1 && pending.length >= 5) {
        if (pending[0] !== 5 || pending[1] !== 0) return socket.destroy(Error('SOCKS CONNECT rejected: ' + pending[1]));
        const size = pending[3] === 1 ? 10 : pending[3] === 4 ? 22 : pending[3] === 3 ? pending[4]+7 : 0;
        if (!size) return socket.destroy(Error('SOCKS address type'));
        if (pending.length < size) return;
        pending = pending.subarray(size); state = 2;
      }
      if (state === 2 && pending.includes(10)) {
        const banner = pending.toString('utf8').split('\n').find(line => line.startsWith('SSH-'));
        if (!banner) return socket.destroy(Error('Not an SSH banner'));
        console.log('SOCKS SSH banner:', banner.trim());
        socket.destroy(); resolve();
      }
    });
  });
})().catch(error => { console.error(error.message); process.exitCode = 1; });
