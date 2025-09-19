;; StacksOracle - Decentralized Prediction Protocol
;;
;; Title: StacksOracle Protocol
;;
;; Summary: Revolutionary trustless prediction platform leveraging Bitcoin's security 
;; through Stacks Layer 2, enabling transparent price forecasting markets with 
;; automated settlements and proportional reward distribution.
;;
;; Description: StacksOracle transforms traditional prediction markets by utilizing 
;; Stacks' Bitcoin-secured smart contracts to create fully decentralized forecasting 
;; ecosystems. Users stake STX on directional price movements across various assets, 
;; with oracle-verified outcomes ensuring transparent, tamper-proof settlements. 
;; Winners receive proportional shares of total pools minus sustainable protocol fees.
;; Built for Bitcoin maximalists seeking DeFi yield through predictive intelligence.

;; CONSTANTS & ERROR DEFINITIONS

;; Protocol Identity
(define-constant CONTRACT_OWNER tx-sender)
(define-constant PROTOCOL_NAME "StacksOracle")

;; Authorization Errors
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_OWNER_ONLY (err u101))

;; Market Operation Errors
(define-constant ERR_MARKET_NOT_FOUND (err u200))
(define-constant ERR_INVALID_PREDICTION (err u201))
(define-constant ERR_MARKET_CLOSED (err u202))
(define-constant ERR_MARKET_NOT_RESOLVED (err u203))
(define-constant ERR_ALREADY_CLAIMED (err u204))
(define-constant ERR_ALREADY_RESOLVED (err u205))

;; Financial Errors
(define-constant ERR_INSUFFICIENT_BALANCE (err u300))
(define-constant ERR_INSUFFICIENT_STAKE (err u301))
(define-constant ERR_TRANSFER_FAILED (err u302))

;; Validation Errors
(define-constant ERR_INVALID_PARAMETER (err u400))
(define-constant ERR_INVALID_TIMEFRAME (err u401))
(define-constant ERR_INVALID_PRICE (err u402))

;; Business Logic Constants
(define-constant PREDICTION_UP "up")
(define-constant PREDICTION_DOWN "down")
(define-constant MAX_FEE_PERCENTAGE u10)
(define-constant MINIMUM_MARKET_DURATION u144)

;; STATE VARIABLES

;; Protocol Configuration
(define-data-var oracle-address principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-data-var minimum-stake uint u1000000)
(define-data-var platform-fee-percentage uint u2)
(define-data-var market-counter uint u0)
(define-data-var protocol-paused bool false)

;; Protocol Analytics
(define-data-var total-volume uint u0)
(define-data-var total-fees-collected uint u0)

;; DATA STRUCTURES

;; Market Definition
(define-map markets
    uint
    {
        creator: principal,
        asset-name: (string-ascii 32),
        start-price: uint,
        end-price: uint,
        total-up-stake: uint,
        total-down-stake: uint,
        start-block: uint,
        end-block: uint,
        resolution-block: uint,
        resolved: bool,
        total-participants: uint
    }
)

;; User Prediction Records
(define-map user-predictions
    {market-id: uint, user: principal}
    {
        prediction: (string-ascii 4),
        stake: uint,
        claimed: bool,
        timestamp: uint
    }
)

;; User Performance Metrics
(define-map user-stats
    principal
    {
        total-predictions: uint,
        total-winnings: uint,
        total-losses: uint
    }
)

;; PUBLIC MARKET FUNCTIONS

;; Create New Prediction Market
(define-public (create-market 
    (asset-name (string-ascii 32))
    (start-price uint) 
    (start-block uint) 
    (end-block uint))
    (let
        (
            (market-id (var-get market-counter))
            (current-block stacks-block-height)
        )
        ;; Validation Suite
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (asserts! (not (var-get protocol-paused)) ERR_UNAUTHORIZED)
        (asserts! (> end-block start-block) ERR_INVALID_TIMEFRAME)
        (asserts! (>= (- end-block start-block) MINIMUM_MARKET_DURATION) ERR_INVALID_TIMEFRAME)
        (asserts! (>= start-block current-block) ERR_INVALID_TIMEFRAME)
        (asserts! (> start-price u0) ERR_INVALID_PRICE)
        (asserts! (> (len asset-name) u0) ERR_INVALID_PARAMETER)
        
        ;; Market Creation
        (map-set markets market-id
            {
                creator: tx-sender,
                asset-name: asset-name,
                start-price: start-price,
                end-price: u0,
                total-up-stake: u0,
                total-down-stake: u0,
                start-block: start-block,
                end-block: end-block,
                resolution-block: u0,
                resolved: false,
                total-participants: u0
            }
        )
        
        (var-set market-counter (+ market-id u1))
        (ok market-id)
    )
)

;; Submit Prediction with Stake
(define-public (make-prediction 
    (market-id uint) 
    (prediction (string-ascii 4)) 
    (stake uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
            (current-block stacks-block-height)
            (existing-prediction (map-get? user-predictions {market-id: market-id, user: tx-sender}))
        )
        ;; Comprehensive Validation
        (asserts! (not (var-get protocol-paused)) ERR_UNAUTHORIZED)
        (asserts! (and (>= current-block (get start-block market)) 
                      (< current-block (get end-block market))) 
                 ERR_MARKET_CLOSED)
        (asserts! (or (is-eq prediction PREDICTION_UP) (is-eq prediction PREDICTION_DOWN)) 
                 ERR_INVALID_PREDICTION)
        (asserts! (>= stake (var-get minimum-stake)) 
                 ERR_INSUFFICIENT_STAKE)
        (asserts! (>= (stx-get-balance tx-sender) stake) 
                 ERR_INSUFFICIENT_BALANCE)
        (asserts! (not (get resolved market)) ERR_MARKET_CLOSED)

        (let
            (
                (final-stake (if (is-some existing-prediction)
                               (+ stake (get stake (unwrap-panic existing-prediction)))
                               stake))
                (is-new-participant (is-none existing-prediction))
            )
            
            ;; Stake Transfer
            (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))
            
            ;; Update User Record
            (map-set user-predictions 
                {market-id: market-id, user: tx-sender}
                {
                    prediction: prediction, 
                    stake: final-stake, 
                    claimed: false,
                    timestamp: current-block
                }
            )
            
            ;; Update Market Statistics
            (map-set markets market-id
                (merge market
                    {
                        total-up-stake: (if (is-eq prediction PREDICTION_UP)
                                        (+ (get total-up-stake market) stake)
                                        (get total-up-stake market)),
                        total-down-stake: (if (is-eq prediction PREDICTION_DOWN)
                                          (+ (get total-down-stake market) stake)
                                          (get total-down-stake market)),
                        total-participants: (if is-new-participant
                                           (+ (get total-participants market) u1)
                                           (get total-participants market))
                    }
                )
            )
            
            (var-set total-volume (+ (var-get total-volume) stake))
            (ok {market-id: market-id, total-stake: final-stake})
        )
    )
)

;; Oracle Market Resolution
(define-public (resolve-market (market-id uint) (end-price uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
            (current-block stacks-block-height)
        )
        ;; Oracle Authorization Check
        (asserts! (is-eq tx-sender (var-get oracle-address)) ERR_UNAUTHORIZED)
        (asserts! (>= current-block (get end-block market)) ERR_MARKET_CLOSED)
        (asserts! (not (get resolved market)) ERR_ALREADY_RESOLVED)
        (asserts! (> end-price u0) ERR_INVALID_PRICE)

        ;; Market Resolution
        (map-set markets market-id
            (merge market
                {
                    end-price: end-price,
                    resolved: true,
                    resolution-block: current-block
                }
            )
        )
        (ok {market-id: market-id, end-price: end-price})
    )
)

;; Claim Winnings Distribution
(define-public (claim-winnings (market-id uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) ERR_MARKET_NOT_FOUND))
            (prediction (unwrap! (map-get? user-predictions {market-id: market-id, user: tx-sender}) ERR_MARKET_NOT_FOUND))
        )
        ;; Claim Validation
        (asserts! (get resolved market) ERR_MARKET_NOT_RESOLVED)
        (asserts! (not (get claimed prediction)) ERR_ALREADY_CLAIMED)

        (let
            (
                (winning-prediction (if (> (get end-price market) (get start-price market)) 
                                   PREDICTION_UP 
                                   PREDICTION_DOWN))
                (total-pool (+ (get total-up-stake market) (get total-down-stake market)))
                (winning-pool (if (is-eq winning-prediction PREDICTION_UP) 
                               (get total-up-stake market) 
                               (get total-down-stake market)))
                (user-stake (get stake prediction))
            )
            ;; Winner Verification
            (asserts! (is-eq (get prediction prediction) winning-prediction) ERR_INVALID_PREDICTION)
            (asserts! (> winning-pool u0) ERR_INVALID_PARAMETER)
            
            (let
                (
                    (gross-winnings (/ (* user-stake total-pool) winning-pool))
                    (platform-fee (/ (* gross-winnings (var-get platform-fee-percentage)) u100))
                    (net-payout (- gross-winnings platform-fee))
                )
                ;; Payout Execution
                (try! (as-contract (stx-transfer? net-payout (as-contract tx-sender) tx-sender)))
                (try! (as-contract (stx-transfer? platform-fee (as-contract tx-sender) CONTRACT_OWNER)))
                
                ;; Record Updates
                (map-set user-predictions 
                    {market-id: market-id, user: tx-sender}
                    (merge prediction {claimed: true})
                )
                
                (update-user-stats tx-sender net-payout true)
                (var-set total-fees-collected (+ (var-get total-fees-collected) platform-fee))
                
                (ok {payout: net-payout, fee: platform-fee})
            )
        )
    )
)

;; READ-ONLY QUERY FUNCTIONS

;; Detailed Market Information
(define-read-only (get-market-details (market-id uint))
    (match (map-get? markets market-id)
        market (ok (merge market 
            {
                total-pool: (+ (get total-up-stake market) (get total-down-stake market)),
                up-percentage: (if (> (+ (get total-up-stake market) (get total-down-stake market)) u0)
                                 (/ (* (get total-up-stake market) u100) 
                                    (+ (get total-up-stake market) (get total-down-stake market)))
                                 u50),
                is-active: (and (>= stacks-block-height (get start-block market))
                               (< stacks-block-height (get end-block market))
                               (not (get resolved market)))
            }))
        ERR_MARKET_NOT_FOUND
    )
)

;; User Prediction Details
(define-read-only (get-user-prediction-details (market-id uint) (user principal))
    (match (map-get? user-predictions {market-id: market-id, user: user})
        prediction (ok prediction)
        ERR_MARKET_NOT_FOUND
    )
)

;; User Performance Statistics
(define-read-only (get-user-stats (user principal))
    (default-to 
        {total-predictions: u0, total-winnings: u0, total-losses: u0}
        (map-get? user-stats user)
    )
)

;; Platform-wide Metrics
(define-read-only (get-platform-stats)
    (ok {
        total-markets: (var-get market-counter),
        total-volume: (var-get total-volume),
        total-fees: (var-get total-fees-collected),
        contract-balance: (stx-get-balance (as-contract tx-sender)),
        is-paused: (var-get protocol-paused)
    })
)

;; Protocol Configuration View
(define-read-only (get-platform-config)
    (ok {
        oracle-address: (var-get oracle-address),
        minimum-stake: (var-get minimum-stake),
        platform-fee: (var-get platform-fee-percentage),
        protocol-paused: (var-get protocol-paused)
    })
)

;; ADMINISTRATIVE CONTROLS

;; Oracle Address Management
(define-public (set-oracle-address (new-address principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (asserts! (not (is-eq new-address CONTRACT_OWNER)) ERR_INVALID_PARAMETER)
        (asserts! (is-standard new-address) ERR_INVALID_PARAMETER)
        (var-set oracle-address new-address)
        (ok true)
    )
)

;; Minimum Stake Configuration
(define-public (set-minimum-stake (new-minimum uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (asserts! (> new-minimum u0) ERR_INVALID_PARAMETER)
        (var-set minimum-stake new-minimum)
        (ok true)
    )
)

;; Fee Structure Management
(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (asserts! (<= new-fee MAX_FEE_PERCENTAGE) ERR_INVALID_PARAMETER)
        (var-set platform-fee-percentage new-fee)
        (ok true)
    )
)

;; Emergency Protocol Controls
(define-public (toggle-protocol-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (var-set protocol-paused (not (var-get protocol-paused)))
        (ok (var-get protocol-paused))
    )
)

;; Fee Collection Management
(define-public (withdraw-fees (amount uint))
    (let
        (
            (contract-balance (stx-get-balance (as-contract tx-sender)))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (asserts! (<= amount contract-balance) ERR_INSUFFICIENT_BALANCE)
        (try! (as-contract (stx-transfer? amount (as-contract tx-sender) CONTRACT_OWNER)))
        (ok amount)
    )
)

;; PRIVATE HELPER FUNCTIONS

;; User Statistics Tracker
(define-private (update-user-stats (user principal) (amount uint) (is-win bool))
    (let
        (
            (current-stats (default-to 
                {total-predictions: u0, total-winnings: u0, total-losses: u0}
                (map-get? user-stats user)))
        )
        (map-set user-stats user
            (merge current-stats
                {
                    total-predictions: (+ (get total-predictions current-stats) u1),
                    total-winnings: (if is-win 
                                   (+ (get total-winnings current-stats) amount)
                                   (get total-winnings current-stats)),
                    total-losses: (if (not is-win)
                                 (+ (get total-losses current-stats) amount)
                                 (get total-losses current-stats))
                }
            )
        )
    )
)