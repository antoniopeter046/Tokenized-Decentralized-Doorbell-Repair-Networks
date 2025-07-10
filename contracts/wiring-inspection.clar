;; Wiring Inspection Contract
;; Evaluates electrical connections and safety compliance

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-REQUEST (err u201))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u202))
(define-constant ERR-INSPECTION-NOT-FOUND (err u203))
(define-constant ERR-ALREADY-COMPLETED (err u204))

;; Data Variables
(define-data-var next-inspection-id uint u1)
(define-data-var inspection-fee uint u1500000) ;; 1.5 STX in microSTX

;; Data Maps
(define-map inspection-requests
  { inspection-id: uint }
  {
    customer: principal,
    inspector: (optional principal),
    property-address: (string-ascii 200),
    inspection-type: (string-ascii 50),
    status: (string-ascii 20),
    payment-amount: uint,
    scheduled-date: uint,
    completed-at: (optional uint),
    certification-issued: bool
  }
)

(define-map inspector-profiles
  { inspector: principal }
  {
    name: (string-ascii 100),
    license-number: (string-ascii 50),
    certification-level: uint,
    rating: uint,
    completed-inspections: uint,
    stake-amount: uint
  }
)

(define-map inspection-reports
  { inspection-id: uint }
  {
    wiring-condition: (string-ascii 50),
    safety-compliance: bool,
    code-violations: (list 10 (string-ascii 100)),
    recommended-repairs: (string-ascii 500),
    certification-valid-until: (optional uint),
    risk-level: uint
  }
)

(define-map safety-violations
  { inspection-id: uint, violation-id: uint }
  {
    violation-type: (string-ascii 100),
    severity: uint,
    description: (string-ascii 300),
    required-action: (string-ascii 200),
    deadline: uint
  }
)

;; Public Functions

;; Create a new wiring inspection request
(define-public (create-inspection-request (property-address (string-ascii 200))
                                         (inspection-type (string-ascii 50))
                                         (scheduled-date uint))
  (let
    (
      (inspection-id (var-get next-inspection-id))
      (fee (var-get inspection-fee))
    )
    (asserts! (>= (stx-get-balance tx-sender) fee) ERR-INSUFFICIENT-PAYMENT)
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    (map-set inspection-requests
      { inspection-id: inspection-id }
      {
        customer: tx-sender,
        inspector: none,
        property-address: property-address,
        inspection-type: inspection-type,
        status: "pending",
        payment-amount: fee,
        scheduled-date: scheduled-date,
        completed-at: none,
        certification-issued: false
      }
    )
    (var-set next-inspection-id (+ inspection-id u1))
    (ok inspection-id)
  )
)

;; Register as an inspector
(define-public (register-inspector (name (string-ascii 100))
                                  (license-number (string-ascii 50))
                                  (certification-level uint)
                                  (stake-amount uint))
  (begin
    (asserts! (>= (stx-get-balance tx-sender) stake-amount) ERR-INSUFFICIENT-PAYMENT)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (map-set inspector-profiles
      { inspector: tx-sender }
      {
        name: name,
        license-number: license-number,
        certification-level: certification-level,
        rating: u5,
        completed-inspections: u0,
        stake-amount: stake-amount
      }
    )
    (ok true)
  )
)

;; Assign inspector to inspection request
(define-public (assign-inspector (inspection-id uint) (inspector principal))
  (let
    (
      (request (unwrap! (map-get? inspection-requests { inspection-id: inspection-id }) ERR-INSPECTION-NOT-FOUND))
      (inspector-profile (unwrap! (map-get? inspector-profiles { inspector: inspector }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-eq (get customer request) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "pending") ERR-INVALID-REQUEST)
    (map-set inspection-requests
      { inspection-id: inspection-id }
      (merge request { inspector: (some inspector), status: "assigned" })
    )
    (ok true)
  )
)

;; Submit inspection report
(define-public (submit-inspection-report (inspection-id uint)
                                        (wiring-condition (string-ascii 50))
                                        (safety-compliance bool)
                                        (code-violations (list 10 (string-ascii 100)))
                                        (recommended-repairs (string-ascii 500))
                                        (risk-level uint))
  (let
    (
      (request (unwrap! (map-get? inspection-requests { inspection-id: inspection-id }) ERR-INSPECTION-NOT-FOUND))
      (certification-valid (if safety-compliance (some (+ block-height u52560)) none)) ;; 1 year validity
    )
    (asserts! (is-eq (some tx-sender) (get inspector request)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "assigned") ERR-INVALID-REQUEST)
    (map-set inspection-reports
      { inspection-id: inspection-id }
      {
        wiring-condition: wiring-condition,
        safety-compliance: safety-compliance,
        code-violations: code-violations,
        recommended-repairs: recommended-repairs,
        certification-valid-until: certification-valid,
        risk-level: risk-level
      }
    )
    (map-set inspection-requests
      { inspection-id: inspection-id }
      (merge request {
        status: "completed",
        completed-at: (some block-height),
        certification-issued: safety-compliance
      })
    )
    (ok true)
  )
)

;; Complete inspection and process payment
(define-public (complete-inspection (inspection-id uint))
  (let
    (
      (request (unwrap! (map-get? inspection-requests { inspection-id: inspection-id }) ERR-INSPECTION-NOT-FOUND))
      (inspector (unwrap! (get inspector request) ERR-NOT-AUTHORIZED))
      (inspector-profile (unwrap! (map-get? inspector-profiles { inspector: inspector }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-eq tx-sender inspector) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "completed") ERR-INVALID-REQUEST)
    (try! (as-contract (stx-transfer? (get payment-amount request) tx-sender inspector)))
    (map-set inspector-profiles
      { inspector: inspector }
      (merge inspector-profile { completed-inspections: (+ (get completed-inspections inspector-profile) u1) })
    )
    (ok true)
  )
)

;; Record safety violation
(define-public (record-safety-violation (inspection-id uint)
                                       (violation-id uint)
                                       (violation-type (string-ascii 100))
                                       (severity uint)
                                       (description (string-ascii 300))
                                       (required-action (string-ascii 200))
                                       (deadline uint))
  (let
    (
      (request (unwrap! (map-get? inspection-requests { inspection-id: inspection-id }) ERR-INSPECTION-NOT-FOUND))
    )
    (asserts! (is-eq (some tx-sender) (get inspector request)) ERR-NOT-AUTHORIZED)
    (map-set safety-violations
      { inspection-id: inspection-id, violation-id: violation-id }
      {
        violation-type: violation-type,
        severity: severity,
        description: description,
        required-action: required-action,
        deadline: deadline
      }
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-inspection-request (inspection-id uint))
  (map-get? inspection-requests { inspection-id: inspection-id })
)

(define-read-only (get-inspector-profile (inspector principal))
  (map-get? inspector-profiles { inspector: inspector })
)

(define-read-only (get-inspection-report (inspection-id uint))
  (map-get? inspection-reports { inspection-id: inspection-id })
)

(define-read-only (get-safety-violation (inspection-id uint) (violation-id uint))
  (map-get? safety-violations { inspection-id: inspection-id, violation-id: violation-id })
)

(define-read-only (get-inspection-fee)
  (var-get inspection-fee)
)

(define-read-only (get-next-inspection-id)
  (var-get next-inspection-id)
)
