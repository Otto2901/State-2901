// VAPID key generator — raw format for Web Push
// Run: node gen-vapid.js

async function generateVAPID() {
  const keyPair = await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    ['deriveKey']
  );

  // Public key: raw 65-byte uncompressed EC point
  const pubRaw = await crypto.subtle.exportKey('raw', keyPair.publicKey);
  // Private key: JWK — take the 'd' field (raw 32-byte scalar, base64url)
  const privJwk = await crypto.subtle.exportKey('jwk', keyPair.privateKey);

  const toB64 = buf =>
    Buffer.from(buf).toString('base64')
      .replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');

  const pub  = toB64(pubRaw);    // ~87 chars
  const priv = privJwk.d;        // ~43 chars — this is the correct VAPID format

  console.log('');
  console.log('=== VAPID Keys (copy both) ===');
  console.log('PUBLIC_KEY :', pub);
  console.log('PRIVATE_KEY:', priv);
  console.log('');
  console.log('PUBLIC_KEY length:', pub.length, '(should be 87)');
  console.log('PRIVATE_KEY length:', priv.length, '(should be 43)');
}

generateVAPID();
