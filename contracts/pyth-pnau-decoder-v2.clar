;; Title: pyth-pnau-decoder
;; Version: v2
;; Check for latest version: https://github.com/Trust-Machines/stacks-pyth-bridge#latest-version
;; Report an issue: https://github.com/Trust-Machines/stacks-pyth-bridge/issues

;;;; Traits
(impl-trait .pyth-traits-v1.decoder-trait)
(use-trait wormhole-core-trait .wormhole-traits-v1.core-trait)

;;;; Constants

(define-constant PNAU_MAGIC 0x504e4155) ;; 'PNAU': Pyth Network Accumulator Update
(define-constant AUWV_MAGIC 0x41555756) ;; 'AUWV': Accumulator Update Wormhole Verification
(define-constant PYTHNET_MAJOR_VERSION u1)
(define-constant PYTHNET_MINOR_VERSION u0)
(define-constant UPDATE_TYPE_WORMHOLE_MERKLE u0)
(define-constant MESSAGE_TYPE_PRICE_FEED u0)
(define-constant MERKLE_PROOF_HASH_SIZE u20)
(define-constant MAXIMUM_UPDATES u6)

;; Unable to price feed magic bytes
(define-constant ERR_MAGIC_BYTES (err u2001))
;; Unable to parse major version
(define-constant ERR_VERSION_MAJ (err u2002))
;; Unable to parse minor version
(define-constant ERR_VERSION_MIN (err u2003))
;; Unable to parse trailing header size
(define-constant ERR_HEADER_TRAILING_SIZE (err u2004))
;; Unable to parse proof type
(define-constant ERR_PROOF_TYPE (err u2005))
;; Unable to parse update type
(define-constant ERR_UPDATE_TYPE (err u2006))
;; Merkle root mismatch
(define-constant ERR_INVALID_AUWV (err u2007))
;; Merkle root mismatch
(define-constant ERR_MERKLE_ROOT_MISMATCH (err u2008))
;; Incorrect AUWV payload
(define-constant ERR_INCORRECT_AUWV_PAYLOAD (err u2009))
;; Price update not signed by an authorized source 
(define-constant ERR_UNAUTHORIZED_PRICE_UPDATE (err u2401))
;; VAA buffer has unused, extra leading bytes (overlay)
(define-constant ERR_OVERLAY_PRESENT (err u2402))
;; Number of updates exceeded maximum.
(define-constant ERR_MAXIMUM_UPDATES (err u2403))

;;;; Public functions
(define-public (decode-and-verify-price-feeds (pnau-bytes (buff 8192)) (wormhole-core-address <wormhole-core-trait>))
  (begin
    ;; Check execution flow
    (try! (contract-call? .pyth-governance-v2 check-execution-flow contract-caller none))
    ;; Proceed to update
    (decode-pnau-price-update pnau-bytes wormhole-core-address)))

;;;; Private functions
;; #[filter(pnau-bytes, wormhole-core-address)]
(define-private (decode-pnau-price-update (pnau-bytes (buff 8192)) (wormhole-core-address <wormhole-core-trait>))
  (let ((pnau-header (try! (parse-pnau-header pnau-bytes)))
        (offset (get pos pnau-header))
        (pnau-vaa-size (try! (read-uint-16 pnau-bytes offset)))
        (pnau-vaa (try! (read-buff-8192-max pnau-bytes (+ offset u2) (some pnau-vaa-size))))
        (vaa (try! (contract-call? wormhole-core-address parse-and-verify-vaa pnau-vaa)))
        (cursor-merkle-root-data (try! (parse-merkle-root-data-from-vaa-payload (get payload vaa))))
        (decoded-prices-updates (try! (parse-and-verify-prices-updates (slice pnau-bytes (+ offset u2 pnau-vaa-size) none) (get merkle-root-hash (get value cursor-merkle-root-data)))))
        (prices-updates (map cast-decoded-price decoded-prices-updates))
        (authorized-prices-data-sources (contract-call? .pyth-governance-v2 get-authorized-prices-data-sources)))
    ;; Ensure that update was published by an data source authorized by governance
    (unwrap! (index-of? 
        authorized-prices-data-sources 
        { emitter-chain: (get emitter-chain vaa), emitter-address: (get emitter-address vaa) }) 
      ERR_UNAUTHORIZED_PRICE_UPDATE)
    (ok prices-updates)))

(define-private (parse-merkle-root-data-from-vaa-payload (payload-vaa-bytes (buff 8192)))
  (let ((payload-type (unwrap! (read-buff-4 payload-vaa-bytes u0) ERR_INVALID_AUWV))
        (wh-update-type (unwrap! (read-uint-8 payload-vaa-bytes u4) ERR_INVALID_AUWV))
        (merkle-root-slot (unwrap! (read-uint-64 payload-vaa-bytes u5) ERR_INVALID_AUWV))
        (merkle-root-ring-size (unwrap! (read-uint-32 payload-vaa-bytes u13) ERR_INVALID_AUWV))
        (merkle-root-hash (unwrap! (read-buff-20 payload-vaa-bytes u17) ERR_INVALID_AUWV)))
    ;; Check payload type
    (asserts! (is-eq payload-type AUWV_MAGIC) ERR_MAGIC_BYTES)
    ;; Check update type
    (asserts! (is-eq wh-update-type UPDATE_TYPE_WORMHOLE_MERKLE) ERR_PROOF_TYPE)
    (ok {
      value: {
        merkle-root-slot: merkle-root-slot,
        merkle-root-ring-size: merkle-root-ring-size,
        merkle-root-hash: merkle-root-hash,
        payload-type: payload-type
      },
      next: merkle-root-hash
    })))

(define-private (parse-pnau-header (pf-bytes (buff 8192)))
  (let ((magic (unwrap! (read-buff-4 pf-bytes u0) ERR_MAGIC_BYTES))
        (version-major (unwrap! (read-uint-8 pf-bytes u4) ERR_VERSION_MAJ))
        (version-minor (unwrap! (read-uint-8 pf-bytes u5) ERR_VERSION_MIN))
        (header-trailing-size (unwrap! (read-uint-8 pf-bytes u6) ERR_HEADER_TRAILING_SIZE))
        (proof-type (unwrap! (read-uint-8 pf-bytes (+ u7 header-trailing-size)) ERR_PROOF_TYPE)))
    ;; Check magic bytes
    (asserts! (is-eq magic PNAU_MAGIC) ERR_MAGIC_BYTES)
    ;; Check major version
    (asserts! (is-eq version-major PYTHNET_MAJOR_VERSION) ERR_VERSION_MAJ)
    ;; Check minor version
    (asserts! (>= version-minor PYTHNET_MINOR_VERSION) ERR_VERSION_MIN)
    ;; Check proof type
    (asserts! (is-eq proof-type UPDATE_TYPE_WORMHOLE_MERKLE) ERR_PROOF_TYPE)
    (ok {
      value: {
        magic: magic,
        version-major: version-major,
        version-minor: version-minor,
        header-trailing-size: header-trailing-size,
        proof-type: proof-type
      },
      pos: (+ header-trailing-size u8)
    })))

(define-private (parse-and-verify-prices-updates (bytes (buff 8192)) (merkle-root-hash (buff 20)))
  (let ((num-updates (try! (read-uint-8 bytes u0)))
        (max-updates-check (asserts! (<= num-updates MAXIMUM_UPDATES) ERR_MAXIMUM_UPDATES))
        (updates (try! (parse-price-info-and-proof bytes)))
        (merkle-proof-checks-success (get result (fold check-merkle-proof updates {
          result: true,
          merkle-root-hash: merkle-root-hash
        }))))
    (asserts! merkle-proof-checks-success ERR_MERKLE_ROOT_MISMATCH)
    ;; Overlay check; 1 is added because 1 byte is used to store "cursor-num-updates"
    (asserts! (is-eq (+ (fold sum-message-length updates u0) u1) (len bytes)) ERR_OVERLAY_PRESENT)
    ;; pyth bundles 6 when the price feeds requested are > 3 and <= 6
    ;; for < 3, it bundles requested number of updates.
    ;; so check overlay during these cases
    (if (or (<= num-updates u3) (is-eq num-updates u6))
      (begin 
        (asserts! (is-eq num-updates (len updates)) ERR_INCORRECT_AUWV_PAYLOAD)
      
        (ok updates)
      )

      (ok updates)
    )))

(define-read-only (message-length (update {
    price-identifier: (buff 32),
    price: int,
    conf: uint,
    expo: int,
    publish-time: uint,
    prev-publish-time: uint,
    ema-price: int,
    ema-conf: uint,
    proof: (list 128 (buff 20)),
    leaf-bytes: (buff 255)
  }))
  (+ u3 (len (get leaf-bytes update)) (* (len (get proof update)) MERKLE_PROOF_HASH_SIZE))
)

(define-read-only (sum-message-length (update {
    price-identifier: (buff 32),
    price: int,
    conf: uint,
    expo: int,
    publish-time: uint,
    prev-publish-time: uint,
    ema-price: int,
    ema-conf: uint,
    proof: (list 128 (buff 20)),
    leaf-bytes: (buff 255)
  }) (a uint))
  (+ (message-length update) a)
)

(define-private (parse-price-info-and-proof (bytes (buff 8192)))
  (let (
    (offset u1)
    (update1 (try! (read-and-verify-update bytes offset)))
    (update2 (unwrap! (read-and-verify-update bytes (+ (message-length update1) offset)) (ok (list update1))))
    (update3 (unwrap! (read-and-verify-update bytes (+ (message-length update1) (message-length update2) offset)) (ok (list update1 update2))))
    (update4 (unwrap! (read-and-verify-update bytes (+ (message-length update1) (message-length update2) (message-length update3) offset)) (ok (list update1 update2 update3))))
    (update5 (unwrap! (read-and-verify-update bytes (+ (message-length update1) (message-length update2) (message-length update3) (message-length update4) offset)) (ok (list update1 update2 update3 update4))))
    (update6 (unwrap! (read-and-verify-update bytes (+ (message-length update1) (message-length update2) (message-length update3) (message-length update4) (message-length update5) offset)) (ok (list update1 update2 update3 update4 update5))))
  )
    (ok (list update1 update2 update3 update4 update5 update6))
  )
)

(define-private (check-merkle-proof
      (entry 
        {
          price-identifier: (buff 32),
          price: int,
          conf: uint,
          expo: int,
          publish-time: uint,
          prev-publish-time: uint,
          ema-price: int,
          ema-conf: uint,
          proof: (list 128 (buff 20)),
          leaf-bytes: (buff 255)
        })
      (acc 
        { 
          merkle-root-hash: (buff 20),
          result: bool, 
        }))
    { 
      merkle-root-hash: (get merkle-root-hash acc),
      result: (and (get result acc)
        (check-proof 
          (get merkle-root-hash acc) 
          (get leaf-bytes entry) 
          (get proof entry)))
    })

(define-private (read-and-verify-update (bytes (buff 8192)) (offset uint))
  (let (
    (message-size (try! (read-uint-16 bytes offset)))
    (message-type (try! (read-uint-8 bytes (+ offset u2))))
    (price-identifier (try! (read-buff-32 bytes (+ offset u3))))
    (price (try! (read-int-64 bytes (+ offset u35))))
    (conf (try! (read-uint-64 bytes (+ offset u43))))
    (expo (try! (read-int-32 bytes (+ offset u51))))
    (publish-time (try! (read-uint-64 bytes (+ offset u55))))
    (prev-publish-time (try! (read-uint-64 bytes (+ offset u63))))
    (ema-price (try! (read-int-64 bytes (+ offset u71))))
    (ema-conf (try! (read-uint-64 bytes (+ offset u79))))
    (proof-size (try! (read-uint-8 bytes (+ offset u2 message-size))))
    (proof-bytes (default-to 0x (slice? bytes
      (+ offset u3 message-size)
      (+ offset u3 message-size (* MERKLE_PROOF_HASH_SIZE proof-size))
    )))
    (leaf-bytes (default-to 0x (slice? bytes (+ offset u2) (+ offset u2 message-size))))
    (proof (get result (fold parse-proof proof-bytes { 
          result: (list),
          cursor: {
            index: u0,
            next-update-index: u0
          },
          bytes: proof-bytes,
          limit: proof-size
        })))
  )
  (asserts! (is-eq message-type MESSAGE_TYPE_PRICE_FEED) ERR_UPDATE_TYPE)
  (ok {
    price-identifier: price-identifier,
    price: price,
    conf: conf,
    expo: expo,
    publish-time: publish-time,
    prev-publish-time: prev-publish-time,
    ema-price: ema-price,
    ema-conf: ema-conf,
    proof: proof,
    leaf-bytes: (unwrap-panic (as-max-len? leaf-bytes u255))
  })
))

(define-private (parse-proof
      (entry (buff 1)) 
      (acc { 
        cursor: { 
          index: uint,
          next-update-index: uint
        },
        bytes: (buff 8192),
        result: (list 128 (buff 20)), 
        limit: uint
      }))
  (if (is-eq (len (get result acc)) (get limit acc))
    acc
    (if (is-eq (get index (get cursor acc)) (get next-update-index (get cursor acc)))
      ;; Parse update
      (let ((hash (unwrap-panic (read-buff-20 (get bytes acc) (get index (get cursor acc))))))
        {
          cursor: { 
            index: (+ (get index (get cursor acc)) u1),
            next-update-index: (+ (get index (get cursor acc)) MERKLE_PROOF_HASH_SIZE),
          },
          bytes: (get bytes acc),
          result: (unwrap-panic (as-max-len? (append (get result acc) hash) u128)),
          limit: (get limit acc),
        })
      ;; Increment position
      {
          cursor: { 
            index: (+ (get index (get cursor acc)) u1),
            next-update-index: (get next-update-index (get cursor acc)),
          },
          bytes: (get bytes acc),
          result: (get result acc),
          limit: (get limit acc)
      })))

(define-private (cast-decoded-price (entry 
        {
          price-identifier: (buff 32),
          price: int,
          conf: uint,
          expo: int,
          publish-time: uint,
          prev-publish-time: uint,
          ema-price: int,
          ema-conf: uint,
          proof: (list 128 (buff 20)),
          leaf-bytes: (buff 255)
        }))
  {
    price-identifier: (get price-identifier entry),
    price: (get price entry),
    conf: (get conf entry),
    expo: (get expo entry),
    publish-time: (get publish-time entry),
    prev-publish-time: (get prev-publish-time entry),
    ema-price: (get ema-price entry),
    ema-conf: (get ema-conf entry)
  })

(define-private (read-buff (bytes (buff 8192)) (pos uint) (length uint))
  (ok (unwrap! (slice? bytes pos (+ pos length)) (err u1))))

(define-private (read-buff-4 (bytes (buff 8192)) (pos uint))
  (ok (unwrap! (as-max-len? (unwrap! (slice? bytes pos (+ pos u4)) (err u1)) u4) (err u1))))

(define-private (read-buff-20 (bytes (buff 8192)) (pos uint))
  (ok (unwrap! (as-max-len? (unwrap! (slice? bytes pos (+ pos u20)) (err u1)) u20) (err u1))))

(define-private (read-buff-32 (bytes (buff 8192)) (pos uint))
  (ok (unwrap! (as-max-len? (unwrap! (slice? bytes pos (+ pos u32)) (err u1)) u32) (err u1))))

(define-private (read-buff-8192-max (bytes (buff 8192)) (pos uint) (size (optional uint)))
  (let ((min pos)
        (max (match size value (+ value pos) (len bytes))))
    (ok (unwrap! (as-max-len? (unwrap! (slice? bytes min max) (err u1)) u8192) (err u1)))))

(define-private (read-uint-8 (bytes (buff 8192)) (pos uint))
    (let ((cursor-bytes (try! (read-buff bytes pos u1))))
        (ok (buff-to-uint-be (unwrap-panic (as-max-len? cursor-bytes u1))))))

(define-private (read-uint-16 (bytes (buff 8192)) (pos uint))
    (let ((cursor-bytes (try! (read-buff bytes pos u2))))
        (ok (buff-to-uint-be (unwrap-panic (as-max-len? cursor-bytes u2))))))

(define-private (read-uint-32 (bytes (buff 8192)) (pos uint))
    (let ((cursor-bytes (try! (read-buff bytes pos u4))))
        (ok (buff-to-uint-be (unwrap-panic (as-max-len? cursor-bytes u4))))))

(define-private (read-uint-64 (bytes (buff 8192)) (pos uint))
    (let ((cursor-bytes (try! (read-buff bytes pos u8))))
        (ok (buff-to-uint-be (unwrap-panic (as-max-len? cursor-bytes u8))))))

(define-private (slice (bytes (buff 8192)) (pos uint) (size (optional uint)))
    (match (slice? bytes pos (match size value (+ pos value) (len bytes))) b b 0x))

(define-private (read-int-32 (bytes (buff 8192)) (pos uint))
    (let ((cursor-bytes (try! (read-buff bytes pos u4))))
        (ok (bit-shift-right (bit-shift-left (buff-to-int-be (unwrap-panic (as-max-len? cursor-bytes u4))) u96) u96))))

(define-private (read-int-64 (bytes (buff 8192)) (pos uint))
    (let ((cursor-bytes (try! (read-buff bytes pos u8))))
        (ok (bit-shift-right (bit-shift-left (buff-to-int-be (unwrap-panic (as-max-len? cursor-bytes u8))) u64) u64))))

(define-private (check-proof (root-hash (buff 20)) (leaf (buff 255)) (path (list 255 (buff 20))))
    (let ((hashed-leaf (hash-leaf leaf))
          (computed-root-hash (fold hash-path path hashed-leaf)))
        (is-eq root-hash computed-root-hash)))

(define-private (hash-leaf (bytes (buff 255)))
    (keccak160 (concat 0x00 bytes)))

(define-private (keccak160 (bytes (buff 1024)))
    (unwrap-panic (as-max-len? (unwrap-panic (slice? (keccak256 bytes) u0 u20)) u20)))

(define-private (hash-path (entry (buff 20)) (acc (buff 20)))
    (hash-nodes entry acc))

(define-private (hash-nodes (node-1 (buff 20)) (node-2 (buff 20)))
    (let ((uint-1 (buff-20-to-uint node-1))
          (uint-2 (buff-20-to-uint node-2))
          (sequence (if (< uint-2 uint-1) 
            (concat (concat 0x01 node-2) node-1)
            (concat (concat 0x01 node-1) node-2))))
    (keccak160 sequence)))

(define-private (buff-20-to-uint (bytes (buff 20)))
    (buff-to-uint-be (unwrap-panic (as-max-len? (unwrap-panic (slice? bytes u0 u15)) u16))))