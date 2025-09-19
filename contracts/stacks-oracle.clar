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