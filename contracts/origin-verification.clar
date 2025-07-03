;; Origin Verification System
;; Verifies and tracks product origins and manufacturing details

;; Data Maps
(define-map product-origins
    { product-id: uint }
    {
        manufacturer: (string-ascii 100),
        manufacturing-location: (string-ascii 100),
        raw-materials: (string-ascii 200),
        manufacturing-date: uint,
        certifications: (string-ascii 200),
        verified: bool,
        verifier-id: uint
    }
)

(define-map origin-certificates
    { certificate-id: uint }
    {
        product-id: uint,
        certificate-type: (string-ascii 50),
        issuer: (string-ascii 100),
        issue-date: uint,
        expiry-date: uint,
        certificate-hash: (buff 64),
        valid: bool
    }
)

(define-map raw-material-sources
    { product-id: uint, source-id: uint }
    {
        source-name: (string-ascii 100),
        source-location: (string-ascii 100),
        material-type: (string-ascii 50),
        quantity: uint,
        verified: bool
    }
)

;; Data Variables
(define-data-var certificate-counter uint u0)

;; Constants
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-PRODUCT-NOT-FOUND (err u301))
(define-constant ERR-CERTIFICATE-NOT-FOUND (err u302))
(define-constant ERR-ALREADY-VERIFIED (err u303))
(define-constant ERR-INVALID-CERTIFICATE (err u304))

;; Public Functions

;; Register product origin
(define-public (register-origin
    (product-id uint)
    (coordinator-id uint)
    (manufacturer (string-ascii 100))
    (manufacturing-location (string-ascii 100))
    (raw-materials (string-ascii 200))
    (manufacturing-date uint)
)
    (begin
        (asserts! (can-coordinator-verify coordinator-id tx-sender) ERR-UNAUTHORIZED)
        (asserts! (product-exists product-id) ERR-PRODUCT-NOT-FOUND)

        (map-set product-origins
            { product-id: product-id }
            {
                manufacturer: manufacturer,
                manufacturing-location: manufacturing-location,
                raw-materials: raw-materials,
                manufacturing-date: manufacturing-date,
                certifications: "",
                verified: false,
                verifier-id: coordinator-id
            }
        )
        (ok true)
    )
)

;; Add origin certificate
(define-public (add-certificate
    (product-id uint)
    (coordinator-id uint)
    (certificate-type (string-ascii 50))
    (issuer (string-ascii 100))
    (issue-date uint)
    (expiry-date uint)
    (certificate-hash (buff 64))
)
    (let
        (
            (certificate-id (+ (var-get certificate-counter) u1))
        )
        (begin
            (asserts! (can-coordinator-verify coordinator-id tx-sender) ERR-UNAUTHORIZED)
            (asserts! (is-some (map-get? product-origins { product-id: product-id })) ERR-PRODUCT-NOT-FOUND)
            (asserts! (> expiry-date issue-date) ERR-INVALID-CERTIFICATE)

            (map-set origin-certificates
                { certificate-id: certificate-id }
                {
                    product-id: product-id,
                    certificate-type: certificate-type,
                    issuer: issuer,
                    issue-date: issue-date,
                    expiry-date: expiry-date,
                    certificate-hash: certificate-hash,
                    valid: true
                }
            )

            (var-set certificate-counter certificate-id)
            (ok certificate-id)
        )
    )
)

;; Verify product origin
(define-public (verify-origin (product-id uint) (coordinator-id uint))
    (begin
        (asserts! (can-coordinator-verify coordinator-id tx-sender) ERR-UNAUTHORIZED)

        (match (map-get? product-origins { product-id: product-id })
            origin-data
            (begin
                (asserts! (not (get verified origin-data)) ERR-ALREADY-VERIFIED)
                (map-set product-origins
                    { product-id: product-id }
                    (merge origin-data
                        {
                            verified: true,
                            verifier-id: coordinator-id
                        }
                    )
                )
                (ok true)
            )
            ERR-PRODUCT-NOT-FOUND
        )
    )
)

;; Add raw material source
(define-public (add-raw-material-source
    (product-id uint)
    (coordinator-id uint)
    (source-id uint)
    (source-name (string-ascii 100))
    (source-location (string-ascii 100))
    (material-type (string-ascii 50))
    (quantity uint)
)
    (begin
        (asserts! (can-coordinator-verify coordinator-id tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-some (map-get? product-origins { product-id: product-id })) ERR-PRODUCT-NOT-FOUND)

        (map-set raw-material-sources
            { product-id: product-id, source-id: source-id }
            {
                source-name: source-name,
                source-location: source-location,
                material-type: material-type,
                quantity: quantity,
                verified: false
            }
        )
        (ok true)
    )
)

;; Verify raw material source
(define-public (verify-raw-material
    (product-id uint)
    (source-id uint)
    (coordinator-id uint)
)
    (begin
        (asserts! (can-coordinator-verify coordinator-id tx-sender) ERR-UNAUTHORIZED)

        (match (map-get? raw-material-sources { product-id: product-id, source-id: source-id })
            source-data
            (begin
                (map-set raw-material-sources
                    { product-id: product-id, source-id: source-id }
                    (merge source-data { verified: true })
                )
                (ok true)
            )
            ERR-PRODUCT-NOT-FOUND
        )
    )
)

;; Read-only Functions

;; Get product origin
(define-read-only (get-product-origin (product-id uint))
    (map-get? product-origins { product-id: product-id })
)

;; Get certificate info
(define-read-only (get-certificate (certificate-id uint))
    (map-get? origin-certificates { certificate-id: certificate-id })
)

;; Get raw material source
(define-read-only (get-raw-material-source (product-id uint) (source-id uint))
    (map-get? raw-material-sources { product-id: product-id, source-id: source-id })
)

;; Check if origin is verified
(define-read-only (is-origin-verified (product-id uint))
    (match (map-get? product-origins { product-id: product-id })
        origin-data
        (get verified origin-data)
        false
    )
)

;; Check certificate validity
(define-read-only (is-certificate-valid (certificate-id uint))
    (match (map-get? origin-certificates { certificate-id: certificate-id })
        cert-data
        (and
            (get valid cert-data)
            (> (get expiry-date cert-data) block-height)
        )
        false
    )
)

;; Private Functions

;; Check if coordinator can verify origins (simplified internal check)
(define-private (can-coordinator-verify (coordinator-id uint) (address principal))
    (and
        (> coordinator-id u0)
        (is-eq tx-sender address)
    )
)

;; Simple product existence check (replace contract call)
(define-private (product-exists (product-id uint))
    (> product-id u0)
)
