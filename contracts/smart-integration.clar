;; Smart Integration Contract
;; Coordinates video doorbell installation and configuration

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-REQUEST (err u401))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u402))
(define-constant ERR-INTEGRATION-NOT-FOUND (err u403))
(define-constant ERR-DEVICE-INCOMPATIBLE (err u404))

;; Data Variables
(define-data-var next-integration-id uint u1)
(define-data-var integration-fee uint u2000000) ;; 2 STX in microSTX

;; Data Maps
(define-map integration-requests
  { integration-id: uint }
  {
    customer: principal,
    installer: (optional principal),
    device-model: (string-ascii 100),
    home-system: (string-ascii 50),
    integration-type: (string-ascii 50),
    status: (string-ascii 20),
    payment-amount: uint,
    scheduled-date: uint,
    completed-at: (optional uint),
    configuration-hash: (optional (buff 32))
  }
)

(define-map smart-installers
  { installer: principal }
  {
    name: (string-ascii 100),
    certified-brands: (list 10 (string-ascii 50)),
    smart-home-platforms: (list 10 (string-ascii 50)),
    rating: uint,
    completed-integrations: uint,
    stake-amount: uint
  }
)

(define-map device-compatibility
  { device-model: (string-ascii 100) }
  {
    manufacturer: (string-ascii 50),
    supported-platforms: (list 10 (string-ascii 50)),
    required-voltage: uint,
    wireless-protocols: (list 5 (string-ascii 20)),
    features: (list 15 (string-ascii 50)),
    installation-complexity: uint
  }
)

(define-map integration-configurations
  { integration-id: uint }
  {
    network-settings: (string-ascii 200),
    app-configuration: (string-ascii 300),
    automation-rules: (list 10 (string-ascii 100)),
    security-settings: (string-ascii 200),
    testing-results: (string-ascii 300)
  }
)

(define-map smart-home-systems
  { system-id: (string-ascii 50) }
  {
    platform-name: (string-ascii 50),
    version: (string-ascii 20),
    supported-devices: (list 20 (string-ascii 100)),
    api-endpoints: (list 5 (string-ascii 100)),
    authentication-method: (string-ascii 50)
  }
)

;; Public Functions

;; Create a new smart integration request
(define-public (create-integration-request (device-model (string-ascii 100))
                                          (home-system (string-ascii 50))
                                          (integration-type (string-ascii 50))
                                          (scheduled-date uint))
  (let
    (
      (integration-id (var-get next-integration-id))
      (fee (var-get integration-fee))
      (device-info (map-get? device-compatibility { device-model: device-model }))
    )
    (asserts! (is-some device-info) ERR-DEVICE-INCOMPATIBLE)
    (asserts! (>= (stx-get-balance tx-sender) fee) ERR-INSUFFICIENT-PAYMENT)
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    (map-set integration-requests
      { integration-id: integration-id }
      {
        customer: tx-sender,
        installer: none,
        device-model: device-model,
        home-system: home-system,
        integration-type: integration-type,
        status: "pending",
        payment-amount: fee,
        scheduled-date: scheduled-date,
        completed-at: none,
        configuration-hash: none
      }
    )
    (var-set next-integration-id (+ integration-id u1))
    (ok integration-id)
  )
)

;; Register as a smart integration installer
(define-public (register-smart-installer (name (string-ascii 100))
                                        (certified-brands (list 10 (string-ascii 50)))
                                        (smart-home-platforms (list 10 (string-ascii 50)))
                                        (stake-amount uint))
  (begin
    (asserts! (>= (stx-get-balance tx-sender) stake-amount) ERR-INSUFFICIENT-PAYMENT)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (map-set smart-installers
      { installer: tx-sender }
      {
        name: name,
        certified-brands: certified-brands,
        smart-home-platforms: smart-home-platforms,
        rating: u5,
        completed-integrations: u0,
        stake-amount: stake-amount
      }
    )
    (ok true)
  )
)

;; Add device compatibility information
(define-public (add-device-compatibility (device-model (string-ascii 100))
                                        (manufacturer (string-ascii 50))
                                        (supported-platforms (list 10 (string-ascii 50)))
                                        (required-voltage uint)
                                        (wireless-protocols (list 5 (string-ascii 20)))
                                        (features (list 15 (string-ascii 50)))
                                        (installation-complexity uint))
  (begin
    (map-set device-compatibility
      { device-model: device-model }
      {
        manufacturer: manufacturer,
        supported-platforms: supported-platforms,
        required-voltage: required-voltage,
        wireless-protocols: wireless-protocols,
        features: features,
        installation-complexity: installation-complexity
      }
    )
    (ok true)
  )
)

;; Assign installer to integration request
(define-public (assign-smart-installer (integration-id uint) (installer principal))
  (let
    (
      (request (unwrap! (map-get? integration-requests { integration-id: integration-id }) ERR-INTEGRATION-NOT-FOUND))
      (installer-profile (unwrap! (map-get? smart-installers { installer: installer }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-eq (get customer request) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "pending") ERR-INVALID-REQUEST)
    (map-set integration-requests
      { integration-id: integration-id }
      (merge request { installer: (some installer), status: "assigned" })
    )
    (ok true)
  )
)

;; Configure smart integration
(define-public (configure-smart-integration (integration-id uint)
                                           (network-settings (string-ascii 200))
                                           (app-configuration (string-ascii 300))
                                           (automation-rules (list 10 (string-ascii 100)))
                                           (security-settings (string-ascii 200))
                                           (testing-results (string-ascii 300)))
  (let
    (
      (request (unwrap! (map-get? integration-requests { integration-id: integration-id }) ERR-INTEGRATION-NOT-FOUND))
    )
    (asserts! (is-eq (some tx-sender) (get installer request)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "assigned") ERR-INVALID-REQUEST)
    (map-set integration-configurations
      { integration-id: integration-id }
      {
        network-settings: network-settings,
        app-configuration: app-configuration,
        automation-rules: automation-rules,
        security-settings: security-settings,
        testing-results: testing-results
      }
    )
    (map-set integration-requests
      { integration-id: integration-id }
      (merge request { status: "configured" })
    )
    (ok true)
  )
)

;; Complete smart integration and process payment
(define-public (complete-smart-integration (integration-id uint) (configuration-hash (buff 32)))
  (let
    (
      (request (unwrap! (map-get? integration-requests { integration-id: integration-id }) ERR-INTEGRATION-NOT-FOUND))
      (installer (unwrap! (get installer request) ERR-NOT-AUTHORIZED))
      (installer-profile (unwrap! (map-get? smart-installers { installer: installer }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-eq tx-sender installer) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "configured") ERR-INVALID-REQUEST)
    (try! (as-contract (stx-transfer? (get payment-amount request) tx-sender installer)))
    (map-set integration-requests
      { integration-id: integration-id }
      (merge request {
        status: "completed",
        completed-at: (some block-height),
        configuration-hash: (some configuration-hash)
      })
    )
    (map-set smart-installers
      { installer: installer }
      (merge installer-profile { completed-integrations: (+ (get completed-integrations installer-profile) u1) })
    )
    (ok true)
  )
)

;; Register smart home system
(define-public (register-smart-home-system (system-id (string-ascii 50))
                                          (platform-name (string-ascii 50))
                                          (version (string-ascii 20))
                                          (supported-devices (list 20 (string-ascii 100)))
                                          (api-endpoints (list 5 (string-ascii 100)))
                                          (authentication-method (string-ascii 50)))
  (begin
    (map-set smart-home-systems
      { system-id: system-id }
      {
        platform-name: platform-name,
        version: version,
        supported-devices: supported-devices,
        api-endpoints: api-endpoints,
        authentication-method: authentication-method
      }
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-integration-request (integration-id uint))
  (map-get? integration-requests { integration-id: integration-id })
)

(define-read-only (get-smart-installer-profile (installer principal))
  (map-get? smart-installers { installer: installer })
)

(define-read-only (get-device-compatibility (device-model (string-ascii 100)))
  (map-get? device-compatibility { device-model: device-model })
)

(define-read-only (get-integration-configuration (integration-id uint))
  (map-get? integration-configurations { integration-id: integration-id })
)

(define-read-only (get-smart-home-system (system-id (string-ascii 50)))
  (map-get? smart-home-systems { system-id: system-id })
)

(define-read-only (get-integration-fee)
  (var-get integration-fee)
)

(define-read-only (get-next-integration-id)
  (var-get next-integration-id)
)
