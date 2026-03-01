# Hybrid Post‑Quantum TLS 1.3

## Protocol Overview, Handshake Mechanics, and Real‑World Support (Early 2026)

This document consolidates all prior discussion into a single reference covering:

- What hybrid post‑quantum TLS is and why it exists
- How a hybrid TLS 1.3 handshake works step‑by‑step
- Which released clients and servers can negotiate *true* hybrid TLS
- Operational realities and deployment caveats

## 1. What "Hybrid Post‑Quantum TLS" Means

**Hybrid TLS** combines:

- **Classical cryptography**
  - ECDHE (e.g., X25519)
  - Classical signatures (ECDSA / RSA)
- **Post‑quantum cryptography**
  - Key Encapsulation Mechanism (KEM): **ML‑KEM‑768** (formerly Kyber)

### Goal: Cryptographic Hedging

A connection remains secure unless **both** the classical algorithm **and** the post‑quantum algorithm are broken.

This protects against:
- Harvest‑now, decrypt‑later attacks
- Unknown weaknesses in new PQ algorithms

Hybrid TLS is the **transition strategy** between classical TLS and future PQ‑only TLS.

## 2. Baseline: Normal TLS 1.3 Handshake (Refresher)

```
Client                     Server
------                     ------
ClientHello  -----------→
  + key_share (ECDHE)

                        ServerHello
                        + key_share (ECDHE)
           ←-----------

[Handshake keys derived]

EncryptedExtensions
Certificate
CertificateVerify
Finished        ←-----------

Finished        -----------→
```

- Forward secrecy via ECDHE
- Authentication is separate from key exchange
- Handshake keys derived immediately after ServerHello

## 3. Where Hybrid PQ Fits into TLS 1.3

Hybrid TLS does **not** change TLS 1.3 structure.

- A new key‑exchange group is negotiated
- The TLS key schedule is fed multiple shared secrets

Authentication typically remains classical; key exchange becomes hybrid.

## 4. Hybrid TLS 1.3 Handshake (Step‑by‑Step)

### Step 1: ClientHello — "I want hybrid"

```
ClientHello:
  supported_groups:
    - x25519_mlkem768
    - x25519
  key_share:
    - hybrid_keyshare (ECDHE_pub || PQ_pub)
    - classical_keyshare (ECDHE_pub)
```

The classical key share exists as a fallback for compatibility.

### Step 2: ServerHello — Hybrid selection

```
ServerHello:
  selected_group: x25519_mlkem768
  key_share:
    - ECDHE_public
    - PQ_KEM_ciphertext
```

### Step 3: Hybrid secret derivation

```
handshake_secret =
  HKDF-Extract(S_classical, S_pq)
```

The TLS key schedule itself is unchanged.

### Step 4: Encrypted handshake continues

- Certificate (classical)
- CertificateVerify (classical signature)
- Finished

## 5. Authentication vs Key Exchange

| Function | Algorithm |
|----------|-----------|
| Key exchange | Hybrid (ECDHE + ML‑KEM) |
| Authentication | Classical (ECDSA / RSA) |
| Record protection | Symmetric (AES‑GCM / ChaCha20) |

## 6. Security Properties

| Scenario | Result |
|----------|--------|
| Classical broken, PQ secure | Secure |
| PQ broken, classical secure | Secure |
| Both broken | Broken |

## 7. Clients Supporting Hybrid TLS (Early 2026)

| Client | Status |
|--------|--------|
| Chrome 124+ | ✅ |
| Edge 124+ | ✅ |
| Firefox (late 2025+) | ✅ |
| Safari (recent) | ✅ |

## 8. Servers Supporting True Hybrid TLS

| Server | Status | Notes |
|--------|--------|-------|
| Cloudflare (edge) | ✅ | Hybrid ML‑KEM globally enabled |
| NGINX / Apache / HAProxy | ✅ | Requires OpenSSL ≥ 3.5 or oqs‑provider |

## 9. Operational Reality

- Some middleboxes break on large ClientHello messages
- Some servers advertise TLS 1.3 but cannot parse hybrid groups

Browsers mitigate this by always including a classical fallback key share.

## 10. What Hybrid TLS Is Not

- Not two TLS handshakes
- Not a new TLS version
- Not a change to the record layer

Hybrid TLS **is** a new key‑exchange group fully compatible with TLS 1.3.

> Hybrid TLS is mainstream on the client side.  
> Server crypto library lag remains the primary blocker.

---

Document version: Early 2026
