;; Subscription Payment System Smart Contract
;; Built with Clarity for the Stacks blockchain

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_SUBSCRIPTION (err u101))
(define-constant ERR_ALREADY_SUBSCRIBED (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_SUBSCRIPTION_INACTIVE (err u104))
(define-constant ERR_INVALID_PERIOD (err u105))
(define-constant ERR_PAYMENT_FAILED (err u106))

;; Data structures
(define-map subscriptions
  { subscription-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    description: (string-ascii 200),
    price: uint,
    period: uint,  ;; in blocks (approximately 10 minutes per block on Stacks)
    active: bool
  }
)

(define-map user-subscriptions
  { user: principal, subscription-id: uint }
  {
    start-block: uint,
    next-payment-block: uint,
    active: bool,
    payment-count: uint
  }
)

;; Contract variables
(define-data-var subscription-counter uint u0)

;; Read-only functions
(define-read-only (get-subscription (subscription-id uint))
  (map-get? subscriptions { subscription-id: subscription-id })
)

(define-read-only (get-user-subscription (user principal) (subscription-id uint))
  (map-get? user-subscriptions { user: user, subscription-id: subscription-id })
)

(define-read-only (get-subscription-count)
  (var-get subscription-counter)
)

;; Creates a new subscription plan
(define-public (create-subscription (name (string-ascii 50)) (description (string-ascii 200)) (price uint) (period uint))
  (let
    (
      (subscription-id (+ (var-get subscription-counter) u1))
    )
    (asserts! (> period u0) ERR_INVALID_PERIOD)
    (var-set subscription-counter subscription-id)
    (map-set subscriptions
      { subscription-id: subscription-id }
      {
        owner: tx-sender,
        name: name,
        description: description,
        price: price,
        period: period,
        active: true
      }
    )
    (ok subscription-id)
  )
)

;; Updates an existing subscription plan
(define-public (update-subscription (subscription-id uint) (name (string-ascii 50)) (description (string-ascii 200)) (price uint) (period uint) (active bool))
  (let
    (
      (subscription (unwrap! (get-subscription subscription-id) ERR_INVALID_SUBSCRIPTION))
    )
    (asserts! (is-eq (get owner subscription) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> period u0) ERR_INVALID_PERIOD)
    
    (map-set subscriptions
      { subscription-id: subscription-id }
      {
        owner: tx-sender,
        name: name,
        description: description,
        price: price,
        period: period,
        active: active
      }
    )
    (ok true)
  )
)

;; User subscribes to a subscription plan
(define-public (subscribe (subscription-id uint))
  (let
    (
      (subscription (unwrap! (get-subscription subscription-id) ERR_INVALID_SUBSCRIPTION))
      (user-principal tx-sender)
      (current-block burn-block-height)
      (existing-subscription (get-user-subscription user-principal subscription-id))
    )
    ;; Check if subscription is active
    (asserts! (get active subscription) ERR_SUBSCRIPTION_INACTIVE)
    ;; Check if user is already subscribed
    (asserts! (is-none existing-subscription) ERR_ALREADY_SUBSCRIBED)
    
    ;; Process initial payment
    (unwrap! (stx-transfer? (get price subscription) tx-sender (get owner subscription)) ERR_PAYMENT_FAILED)
    
    ;; Create subscription record
    (map-set user-subscriptions
      { user: user-principal, subscription-id: subscription-id }
      {
        start-block: current-block,
        next-payment-block: (+ current-block (get period subscription)),
        active: true,
        payment-count: u1
      }
    )
    (ok true)
  )
)

;; Process next payment for a subscription
(define-public (process-payment (user principal) (subscription-id uint))
  (let
    (
      (subscription (unwrap! (get-subscription subscription-id) ERR_INVALID_SUBSCRIPTION))
      (user-sub (unwrap! (get-user-subscription user subscription-id) ERR_INVALID_SUBSCRIPTION))
      (current-block burn-block-height)
    )
    ;; Verify subscription is active
    (asserts! (get active subscription) ERR_SUBSCRIPTION_INACTIVE)
    (asserts! (get active user-sub) ERR_SUBSCRIPTION_INACTIVE)
    
    ;; Check if payment is due
    (asserts! (>= current-block (get next-payment-block user-sub)) ERR_PAYMENT_FAILED)
    
    ;; Process payment
    (unwrap! (stx-transfer? (get price subscription) user (get owner subscription)) ERR_PAYMENT_FAILED)
    
    ;; Update subscription record
    (map-set user-subscriptions
      { user: user, subscription-id: subscription-id }
      {
        start-block: (get start-block user-sub),
        next-payment-block: (+ (get next-payment-block user-sub) (get period subscription)),
        active: true,
        payment-count: (+ (get payment-count user-sub) u1)
      }
    )
    (ok true)
  )
)

;; Cancel a subscription
(define-public (cancel-subscription (subscription-id uint))
  (let
    (
      (user-sub (unwrap! (get-user-subscription tx-sender subscription-id) ERR_INVALID_SUBSCRIPTION))
    )
    (map-set user-subscriptions
      { user: tx-sender, subscription-id: subscription-id }
      {
        start-block: (get start-block user-sub),
        next-payment-block: (get next-payment-block user-sub),
        active: false,
        payment-count: (get payment-count user-sub)
      }
    )
    (ok true)
  )
)

;; Check if a subscription is due for payment
(define-read-only (is-payment-due (user principal) (subscription-id uint))
  (let
    (
      (user-sub (map-get? user-subscriptions { user: user, subscription-id: subscription-id }))
      (current-block burn-block-height)
    )
    (if (is-some user-sub)
      (let
        (
          (unwrapped-sub (unwrap-panic user-sub))
        )
        (and
          (get active unwrapped-sub)
          (>= current-block (get next-payment-block unwrapped-sub))
        )
      )
      false
    )
  )
)

;; Get all subscriptions for a user
(define-read-only (get-user-subscriptions (user principal))
  (let
    (
      (subscription-count (var-get subscription-counter))
    )
    ;; This is a simplified approach since Clarity doesn't support dynamic lists
    ;; In a real implementation, you would need a more sophisticated approach
    subscription-count
  )
)