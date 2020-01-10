//
//  BRBlockChainDB.swift
//  BRCrypto
//
//  Created by Ed Gamble on 3/27/19.
//  Copyright © 2019 Breadwinner AG. All rights reserved.
//
//  See the LICENSE file at the project root for license information.
//  See the CONTRIBUTORS file at the project root for a list of contributors.
//
import Foundation // DispatchQueue

public class BlockChainDB {

    /// Base URL (String) for the BRD BlockChain DB
    let bdbBaseURL: String

    /// Base URL (String) for BRD API Services
    let apiBaseURL: String

    // The seesion to use for DataTaskFunc as in `session.dataTask (with: request, ...)`
    let session: URLSession

    /// A DispatchQueue Used for certain queries that can't be accomplished in the session's data
    /// task.  Such as when multiple request are needed in getTransactions().
    let queue = DispatchQueue.init(label: "BlockChainDB")

    /// A function type that decorates a `request`, handles 'challenges', performs decrypting and/or
    /// uncompression of response data, redirects if requires and creates a `URLSessionDataTask`
    /// for the provided `session`.
    public typealias DataTaskFunc = (URLSession, URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask

    /// A DataTaskFunc for submission to the BRD API
    internal let apiDataTaskFunc: DataTaskFunc

    /// A DataTaskFunc for submission to the BRD BlockChain DB
    internal let bdbDataTaskFunc: DataTaskFunc

    /// A default DataTaskFunc that simply invokes `session.dataTask (with: request, ...)`
    static let defaultDataTaskFunc: DataTaskFunc = {
        (_ session: URLSession,
        _ request: URLRequest,
        _ completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask in
        session.dataTask (with: request, completionHandler: completionHandler)
    }

    ///
    /// A Subscription allows for BlockchainDB 'Asynchronous Notifications'.
    ///
    public struct Subscription {
        
        /// A unique identifier for the subscription
        public let subscriptionId: String

        /// A unique identifier for the device.
        public let deviceId: String

        ///
        /// An endpoint definition allowing the BlockchainDB to 'target' this App.  Allows
        /// for APNS, FCM and other notification systems.  This is an optional value; when set to
        /// .none, any existing notification will be disabled
        ///
        /// environment : { unknown, production, development }
        /// kind        : { unknown, apns, fcm, ... }
        /// value       : For apns/fcm this will be the registration token, apns should be hex-encoded
        public let endpoint: (environment: String, kind: String, value: String)?

        public init (id: String, deviceId: String? = nil, endpoint: (environment: String, kind: String, value: String)?) {
            self.subscriptionId = id
            self.deviceId = deviceId ?? id
            self.endpoint = endpoint
        }
    }

    /// A User-specific identifier - a string representation of a UUIDv4
    internal var walletId: String? = nil

    /// A Subscription specificiation
    internal var subscription: Subscription? = nil

    #if false
    private var modelSubscription: Model.Subscription? {
        guard let _ = walletId,  let subscription = subscription, let endpoint = subscription.endpoint
            else { return nil }

        return (id: subscription.subscriptionId,
                device: subscription.deviceId,
                endpoint: (environment: endpoint.environment, kind: endpoint.kind, value: endpoint.value))
    }
    #endif

    // A BlockChainDB wallet requires at least one 'currency : [<addr>+]' entry.  Create a minimal,
    // default one using a compromised ETH address.  This will get replaced as soon as we have
    // a real ETH account.
    internal static let minimalCurrencies = ["eth" : ["A9De3DBd7D561e67527BC1ECB025C59D53B9F7EF"]]

    internal func subscribe (walletId: String, subscription: Subscription) {
        self.walletId = walletId
        self.subscription = subscription

        // TODO: Update caller System.subscribe
        #if false
        // Subscribing requires a wallet on the BlockChainDD, so start by create the BlockChainDB
        // Model.Wallet and then get or create one on the DB.

        let wallet = (id: walletId, currencies: BlockChainDB.minimalCurrencies)

        getOrCreateWallet (wallet) { (walletRes: Result<Model.Wallet, QueryError>) in
            guard case .success = walletRes
                else { print ("SYS: BDB:Wallet: Missed"); return }

            if let model = self.modelSubscription {
                // If the subscription included an endpoint, then put the subscription on the
                // blockchainDB - via POST or PUT.
                self.getSubscription (id: model.id) { (subRes: Result<Model.Subscription, QueryError>) in
                    switch subRes {
                    case let .success (subscription):
                        self.updateSubscription (subscription) {
                            (resSub: Result<BlockChainDB.Model.Subscription, BlockChainDB.QueryError>) in
                        }

                    case .failure:
                        self.createSubscription (model) {
                            (resSub: Result<BlockChainDB.Model.Subscription, BlockChainDB.QueryError>) in
                        }
                    }
                }
            }

            else {
                // Otherwise delete it.
                self.deleteSubscription(id: subscription.subscriptionId) {
                    (subRes: Result<BlockChainDB.Model.Subscription, BlockChainDB.QueryError>) in
                }
            }
        }
        #endif
    }

    ///
    /// Initialize a BlockChainDB
    ///
    /// - Parameters:
    ///   - session: the URLSession to use.  Defaults to `URLSession (configuration: .default)`
    ///   - bdbBaseURL: the baseURL for the BRD BlockChain DB.  Defaults to "http://blockchain-db.us-east-1.elasticbeanstalk.com"
    ///   - bdbDataTaskFunc: an optional DataTaskFunc for BRD BlockChain DB.  This defaults to
    ///       `session.dataTask (with: request, ...)`
    ///   - apiBaseURL: the baseRUL for the BRD API Server.  Defaults to "https://api.breadwallet.com".
    ///       if this is a DEBUG build then "https://stage2.breadwallet.com" will be used instead.
    ///   - apiDataTaskFunc: an optional DataTaskFunc for BRD API services.  For a non-DEBUG build,
    ///       this function would need to properly authenticate with BRD.  This means 'decorating
    ///       the request' header, perhaps responding to a 'challenge', perhaps decripting and/or
    ///       uncompressing response data.  This defaults to `session.dataTask (with: request, ...)`
    ///       which suffices for DEBUG builds.
    ///
    public init (session: URLSession = URLSession (configuration: .default),
                 bdbBaseURL: String = "https://api.blockset.com",
                 bdbDataTaskFunc: DataTaskFunc? = nil,
                 apiBaseURL: String = "https://api.breadwallet.com",
                 apiDataTaskFunc: DataTaskFunc? = nil) {

        self.session = session

        self.bdbBaseURL = bdbBaseURL
        self.apiBaseURL = apiBaseURL

        self.bdbDataTaskFunc = bdbDataTaskFunc ?? BlockChainDB.defaultDataTaskFunc
        self.apiDataTaskFunc = apiDataTaskFunc ?? BlockChainDB.defaultDataTaskFunc
    }

    // this token has no expiration - testing only.
    public static let createForTestBDBBaseURL = "https://api.blockset.com"
    public static let createForTestBDBToken   = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjNzQ5NTA2ZS02MWUzLTRjM2UtYWNiNS00OTY5NTM2ZmRhMTAiLCJpYXQiOjE1NzI1NDY1MDAuODg3LCJleHAiOjE4ODAxMzA1MDAuODg3LCJicmQ6Y3QiOiJ1c3IiLCJicmQ6Y2xpIjoiZGViNjNlMjgtMDM0NS00OGY2LTlkMTctY2U4MGNiZDYxN2NiIn0.460_GdAWbONxqOhWL5TEbQ7uEZi3fSNrl0E_Zg7MAg570CVcgO7rSMJvAPwaQtvIx1XFK_QZjcoNULmB8EtOdg"

    ///
    /// Create a BlockChainDB using a specified Authorization token.  This is declared 'public'
    /// so that the Crypto Demo can use it.
    ///
    public static func createForTest (bdbBaseURL: String = BlockChainDB.createForTestBDBBaseURL,
                                      bdbToken:   String = BlockChainDB.createForTestBDBToken) -> BlockChainDB {
        return BlockChainDB (bdbBaseURL: bdbBaseURL,
                             bdbDataTaskFunc: { (session, request, completion) -> URLSessionDataTask in
                                var decoratedReq = request
                                decoratedReq.setValue ("Bearer \(bdbToken)", forHTTPHeaderField: "Authorization")
                                return session.dataTask (with: decoratedReq, completionHandler: completion)
        })
    }

    ///
    /// A QueryError subtype of Error
    ///
    /// - url:
    /// - submission:
    /// - noData:
    /// - jsonParse:
    /// - model:
    /// - noEntity:
    ///
    public enum QueryError: Error {
        // HTTP URL build failed
        case url (String)

        // HTTP submission error
        case submission (Error)

        // HTTP response unexpected (typically not 200/OK)
        case response (Int) // includes the status code

        // HTTP submission didn't error but returned no data
        case noData

        // JSON parse failed, generically
        case jsonParse (Error?)

        // Could not convert JSON -> T
        case model (String)

        // JSON entity expected but not provided - e.g. requested a 'transferId' that doesn't exist.
        case noEntity (id: String?)
    }

    ///
    /// The BlockChainDB Model (aka Schema-ish)
    ///
    public struct Model {

        /// Blockchain

        public typealias BlockchainFee = (amount: String, tier: String, confirmationTimeInMilliseconds: UInt64) // currency?
        public typealias Blockchain = (
            id: String,
            name: String,
            network: String,
            isMainnet: Bool,
            currency: String,
            blockHeight: UInt64?,
            feeEstimates: [BlockchainFee],
            confirmationsUntilFinal: UInt32)

        static internal func asBlockchainFee (json: JSON) -> Model.BlockchainFee? {
            guard let confirmationTime = json.asUInt64(name: "estimated_confirmation_in"),
                let amountValue = json.asDict(name: "fee")?["amount"] as? String,
                let _ = json.asDict(name: "fee")?["currency_id"] as? String,
                let tier = json.asString(name: "tier")
                else { return nil }

            return (amount: amountValue, tier: tier, confirmationTimeInMilliseconds: confirmationTime)
        }

        static internal func asBlockchain (json: JSON) -> Model.Blockchain? {
            guard let id = json.asString (name: "id"),
                let name = json.asString (name: "name"),
                let network = json.asString (name: "network"),
                let isMainnet = json.asBool (name: "is_mainnet"),
                let currency = json.asString (name: "native_currency_id"),
                let blockHeight = json.asInt64 (name: "block_height"),
                let confirmationsUntilFinal = json.asUInt32(name: "confirmations_until_final")
                else { return nil }

            guard let feeEstimates = json.asArray(name: "fee_estimates")?
                .map ({ JSON (dict: $0) })
                .map ({ asBlockchainFee (json: $0) }) as? [Model.BlockchainFee]
            else { return nil }

            return (id: id, name: name, network: network, isMainnet: isMainnet, currency: currency,
                    blockHeight: (-1 == blockHeight ? nil : UInt64 (blockHeight)),
                    feeEstimates: feeEstimates,
                    confirmationsUntilFinal: confirmationsUntilFinal)
        }

        /// Currency & CurrencyDenomination

        public typealias CurrencyDenomination = (name: String, code: String, decimals: UInt8, symbol: String /* extra */)
        public typealias Currency = (
            id: String,
            name: String,
            code: String,
            type: String,
            blockchainID: String,
            address: String?,
            verified: Bool,
            demoninations: [CurrencyDenomination])

       static internal func asCurrencyDenomination (json: JSON) -> Model.CurrencyDenomination? {
            guard let name = json.asString (name: "name"),
                let code = json.asString (name: "short_name"),
                let decimals = json.asUInt8 (name: "decimals")
                // let symbol = json.asString (name: "symbol")
                else { return nil }

            let symbol = lookupSymbol (code)

            return (name: name, code: code, decimals: decimals, symbol: symbol)
        }

        static internal let currencySymbols = ["btc":"₿", "eth":"Ξ"]
        static internal func lookupSymbol (_ code: String) -> String {
            return currencySymbols[code] ?? code.uppercased()
        }

        static private let currencyInternalAddress = "__native__"

        static internal func asCurrency (json: JSON) -> Model.Currency? {
            guard let id = json.asString (name: "currency_id"),
                let name = json.asString (name: "name"),
                let code = json.asString (name: "code"),
                let type = json.asString (name: "type"),
                let bid  = json.asString (name: "blockchain_id"),
                let verified = json.asBool(name: "verified")
                else { return nil }

            // Address is optional
            let address = json.asString(name: "address")

            // All denomincations must parse
            guard let demoninations = json.asArray (name: "denominations")?
                .map ({ JSON (dict: $0 )})
                .map ({ asCurrencyDenomination(json: $0)}) as? [Model.CurrencyDenomination]
                else { return nil }
            
            return (id: id, name: name, code: code, type: type,
                    blockchainID: bid,
                    address: (address == currencyInternalAddress ? nil : address),
                    verified: verified,
                    demoninations: demoninations)
        }

        static internal let addressBRDTestnet = "0x7108ca7c4718efa810457f228305c9c71390931a" // testnet
        static internal let addressBRDMainnet = "0x558ec3152e2eb2174905cd19aea4e34a23de9ad6" // mainnet

        /// Transfer

        public typealias Transfer = (
            id: String,
            source: String?,
            target: String?,
            amountValue: String,
            amountCurrency: String,
            acknowledgements: UInt64,
            index: UInt64,
            transactionId: String?,
            blockchainId: String)

        static internal func asTransfer (json: JSON) -> Model.Transfer? {
            guard let id   = json.asString (name: "transfer_id"),
                let bid    = json.asString (name: "blockchain_id"),
                let index  = json.asUInt64 (name: "index"),
                let amount = json.asDict (name: "amount").map ({ JSON (dict: $0) }),
                let amountValue    = amount.asString (name: "amount"),
                let amountCurrency = amount.asString (name: "currency_id")
                else { return nil }

            // TODO: Resolve if optional or not
            let acks   = json.asUInt64 (name: "acknowledgements") ?? 0
            let source = json.asString (name: "from_address")
            let target = json.asString (name: "to_address")
            let tid    = json.asString (name: "transaction_id")

            return (id: id, source: source, target: target,
                    amountValue: amountValue, amountCurrency: amountCurrency,
                    acknowledgements: acks, index: index,
                    transactionId: tid, blockchainId: bid)
        }

        /// Transaction

        public typealias Transaction = (
            id: String,
            blockchainId: String,
            hash: String,
            identifier: String,
            blockHash: String?,
            blockHeight: UInt64?,
            index: UInt64?,
            confirmations: UInt64?,
            status: String,
            size: UInt64,
            timestamp: Date?,
            firstSeen: Date?,
            raw: Data?,
            transfers: [Transfer],
            acknowledgements: UInt64
        )

        static internal func asTransaction (json: JSON) -> Model.Transaction? {
            guard let id = json.asString(name: "transaction_id"),
                let bid        = json.asString (name: "blockchain_id"),
                let hash       = json.asString (name: "hash"),
                let identifier = json.asString (name: "identifier"),
                let status     = json.asString (name: "status"),
                let size       = json.asUInt64 (name: "size")
                else { return nil }

            // TODO: Resolve if optional or not
            let acks       = json.asUInt64 (name: "acknowledgements") ?? 0
            // TODO: Resolve if optional or not
            let firstSeen     = json.asDate   (name: "first_seen")
            let blockHash     = json.asString (name: "block_hash")
            let blockHeight   = json.asUInt64 (name: "block_height")
            let index         = json.asUInt64 (name: "index")
            let confirmations = json.asUInt64 (name: "confirmations")
            let timestamp     = json.asDate   (name: "timestamp")

            let raw = json.asData (name: "raw")

            // Require "_embedded" : "transfers" as [JSON.Dict]
            guard let transfersJSON = json.asDict (name: "_embedded")?["transfers"] as? [JSON.Dict]
                else { return nil }

            // Require asTransfer is not .none
            guard let transfers = transfersJSON
                .map ({ JSON (dict: $0) })
                .map ({ asTransfer (json: $0) }) as? [Model.Transfer]
                else { return nil }

            return (id: id, blockchainId: bid,
                     hash: hash, identifier: identifier,
                     blockHash: blockHash, blockHeight: blockHeight, index: index, confirmations: confirmations, status: status,
                     size: size, timestamp: timestamp, firstSeen: firstSeen,
                     raw: raw,
                     transfers: transfers,
                     acknowledgements: acks)
        }

        /// Block

        public typealias Block = (
            id: String,
            blockchainId: String,
            hash: String,
            height: UInt64,
            header: String?,
            raw: Data?,
            mined: Date,
            size: UInt64,
            prevHash: String?,
            nextHash: String?, // fees
            transactions: [Transaction]?,
            acknowledgements: UInt64
        )

        static internal func asBlock (json: JSON) -> Model.Block? {
            guard let id = json.asString(name: "block_id"),
                let bid      = json.asString(name: "blockchain_id"),
                let hash     = json.asString (name: "hash"),
                let height   = json.asUInt64 (name: "height"),
                let mined    = json.asDate   (name: "mined"),
                let size     = json.asUInt64 (name: "size")
                else { return nil }

            let acks     = json.asUInt64 (name: "acknowledgements") ?? 0
            let header   = json.asString (name: "header")
            let raw      = json.asData   (name: "raw")
            let prevHash = json.asString (name: "prev_hash")
            let nextHash = json.asString (name: "next_hash")

            let transactions = json.asArray (name: "transactions")?
                .map ({ JSON (dict: $0 )})
                .map ({ asTransaction (json: $0)}) as? [Model.Transaction]  // not quite

            return (id: id, blockchainId: bid,
                    hash: hash, height: height, header: header, raw: raw, mined: mined, size: size,
                    prevHash: prevHash, nextHash: nextHash,
                    transactions: transactions,
                    acknowledgements: acks)
        }

        /// Subscription Endpoint

        public typealias SubscriptionEndpoint = (environment: String, kind: String, value: String)

        static internal func asSubscriptionEndpoint (json: JSON) -> SubscriptionEndpoint? {
            guard let environment = json.asString (name: "environment"),
                let kind = json.asString(name: "kind"),
                let value = json.asString(name: "value")
                else { return nil }

            return (environment: environment, kind: kind, value: value)
        }

        static internal func asJSON (subscriptionEndpoint: SubscriptionEndpoint) -> JSON.Dict {
            return [
                "environment"   : subscriptionEndpoint.environment,
                "kind"          : subscriptionEndpoint.kind,
                "value"         : subscriptionEndpoint.value
            ]
        }


        /// Subscription Event

        public typealias SubscriptionEvent = (name: String, confirmations: [UInt32]) // More?

        static internal func asSubscriptionEvent (json: JSON) -> SubscriptionEvent? {
            guard let name = json.asString(name: "name")
                else { return nil }
            return (name: name, confirmations: [])
        }

        static internal func asJSON (subscriptionEvent: SubscriptionEvent) -> JSON.Dict {
            switch subscriptionEvent.name {
            case "submitted":
                return [
                    "name" : subscriptionEvent.name
                ]
            case "confirmed":
                return [
                    "name"          : subscriptionEvent.name,
                    "confirmations" : subscriptionEvent.confirmations
                ]
            default:
                preconditionFailure()
            }
        }

        /// Subscription Currency

        public typealias SubscriptionCurrency = (addresses: [String], currencyId: String, events: [SubscriptionEvent])

        static internal func asSubscriptionCurrency (json: JSON) -> SubscriptionCurrency? {
            guard let addresses = json.asStringArray (name: "addresses"),
                let currencyId = json.asString (name: "currency_id"),
                let events = json.asArray(name: "events")?
                    .map ({ JSON (dict: $0) })
                    .map ({ asSubscriptionEvent(json: $0) }) as? [SubscriptionEvent] // not quite
                else { return nil }

            return (addresses: addresses, currencyId: currencyId, events: events)
        }

        static internal func asJSON (subscriptionCurrency: SubscriptionCurrency) -> JSON.Dict {
            return [
                "addresses"   : subscriptionCurrency.addresses,
                "currency_id" : subscriptionCurrency.currencyId,
                "events"       : subscriptionCurrency.events.map { asJSON(subscriptionEvent: $0) }
            ]
        }

        /// Subscription

        // TODO: Apparently `currences` can not be empty.
        public typealias Subscription = (
            id: String,     // subscriptionId
            device: String, //  devcieId
            endpoint: SubscriptionEndpoint,
            currencies: [SubscriptionCurrency]
        )

       static internal func asSubscription (json: JSON) -> Subscription? {
            guard let id = json.asString (name: "subscription_id"),
                let device = json.asString (name: "device_id"),
                let endpoint = json.asDict(name: "endpoint")
                    .flatMap ({ asSubscriptionEndpoint (json: JSON (dict: $0)) }),
                let currencies = json.asArray(name: "currencies")?
                    .map ({ JSON (dict: $0) })
                    .map ({ asSubscriptionCurrency (json: $0) }) as? [SubscriptionCurrency]
                else { return nil }

            return (id: id,
                    device: device,
                    endpoint: endpoint,
                    currencies: currencies)
        }

        static internal func asJSON (subscription: Subscription) -> JSON.Dict {
            return [
                "subscription_id" : subscription.id,
                "device_id"       : subscription.device,
                "endpoint"        : asJSON (subscriptionEndpoint: subscription.endpoint),
                "currencies"      : subscription.currencies.map { asJSON (subscriptionCurrency: $0) }
            ]
        }

    } // End of Model

    public func getBlockchains (mainnet: Bool? = nil, completion: @escaping (Result<[Model.Blockchain],QueryError>) -> Void) {
        bdbMakeRequest (path: "blockchains", query: mainnet.map { zip (["testnet"], [($0 ? "false" : "true")]) }) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            precondition (nil == more)
            completion (res.flatMap {
                BlockChainDB.getManyExpected(data: $0, transform: Model.asBlockchain)
            })
        }
    }

    public func getBlockchain (blockchainId: String, completion: @escaping (Result<Model.Blockchain,QueryError>) -> Void) {
        bdbMakeRequest(path: "blockchains/\(blockchainId)", query: nil, embedded: false) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            precondition (nil == more)
            completion (res.flatMap {
                BlockChainDB.getOneExpected (id: blockchainId, data: $0, transform: Model.asBlockchain)
            })
        }
    }

    public func getCurrencies (blockchainId: String? = nil, completion: @escaping (Result<[Model.Currency],QueryError>) -> Void) {
        bdbMakeRequest (path: "currencies", query: blockchainId.map { zip(["blockchain_id"], [$0]) }) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            precondition (nil == more)
            completion (res.flatMap {
                BlockChainDB.getManyExpected(data: $0, transform: Model.asCurrency)
            })
        }
    }

    public func getCurrency (currencyId: String, completion: @escaping (Result<Model.Currency,QueryError>) -> Void) {
        bdbMakeRequest (path: "currencies/\(currencyId)", query: nil, embedded: false) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            precondition (nil == more)
            completion (res.flatMap {
                BlockChainDB.getOneExpected(id: currencyId, data: $0, transform: Model.asCurrency)
            })
        }
    }

    /// Subscription

    internal func makeSubscriptionRequest (path: String, data: JSON.Dict?, httpMethod: String,
                                           completion: @escaping (Result<Model.Subscription, QueryError>) -> Void) {
        makeRequest (bdbDataTaskFunc, bdbBaseURL,
                     path: path,
                     query: nil,
                     data: data,
                     httpMethod: httpMethod) {
                        (res: Result<JSON.Dict, QueryError>) in
                        completion (res.flatMap {
                            Model.asSubscription(json: JSON(dict: $0))
                                .map { Result.success ($0) }
                                ?? Result.failure(QueryError.model("Missed Subscription"))
                        })
        }
    }

    public func getSubscriptions (completion: @escaping (Result<[Model.Subscription], QueryError>) -> Void) {
        bdbMakeRequest (path: "subscriptions", query: nil, embedded: true) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            completion (res.flatMap {
                BlockChainDB.getManyExpected(data: $0, transform: Model.asSubscription)
            })
        }
    }

    public func getSubscription (id: String, completion: @escaping (Result<Model.Subscription, QueryError>) -> Void) {
        bdbMakeRequest (path: "subscriptions/\(id)", query: nil, embedded: false) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            precondition (nil == more)
            completion (res.flatMap {
                BlockChainDB.getOneExpected (id: id, data: $0, transform: Model.asSubscription)
            })
        }
    }

    public func getOrCreateSubscription (_ subscription: Model.Subscription,
                                         completion: @escaping (Result<Model.Subscription, QueryError>) -> Void) {
        getSubscription(id: subscription.id) {
            (res: Result<BlockChainDB.Model.Subscription, BlockChainDB.QueryError>) in
            if case .success = res { completion (res) }
            else {
                self.createSubscription (subscription, completion: completion)
            }
        }
    }

    public func createSubscription (_ subscription: Model.Subscription, // TODO: Hackily
                                    completion: @escaping (Result<Model.Subscription, QueryError>) -> Void) {
        makeSubscriptionRequest (
            path: "subscriptions",
            data: [
                // We can not use asJSON(Subscription) because that will include the 'id'
                "device_id"       : subscription.device,
                "endpoint"        : BlockChainDB.Model.asJSON (subscriptionEndpoint: subscription.endpoint),
                "currencies"      : subscription.currencies.map { BlockChainDB.Model.asJSON (subscriptionCurrency: $0) }],
            httpMethod: "POST",
            completion: completion)
    }

    public func updateSubscription (_ subscription: Model.Subscription, completion: @escaping (Result<Model.Subscription, QueryError>) -> Void) {
        makeSubscriptionRequest (
            path: "subscriptions/\(subscription.id )",
            data: Model.asJSON (subscription: subscription),
            httpMethod: "PUT",
            completion: completion)
    }

    public func deleteSubscription (id: String, completion: @escaping (Result<Void, QueryError>) -> Void) {
        let path = "subscriptions/\(id)"
        makeRequest (bdbDataTaskFunc, bdbBaseURL,
                     path: path,
                     query: nil,
                     data: nil,
                     httpMethod: "DELETE",
                     deserializer: { (data: Data?) in
                        return (nil == data || 0 == data!.count 
                            ? Result.success (())
                            : Result.failure (QueryError.model ("Unexpected Data on DELETE"))) },
                     completion: completion)
    }

    // Transfers

    public func getTransfers (blockchainId: String,
                              addresses: [String],
                              begBlockNumber: UInt64,
                              endBlockNumber: UInt64,
                              maxPageSize: Int? = nil,
                              completion: @escaping (Result<[Model.Transfer], QueryError>) -> Void) {
        self.queue.async {
            var error: QueryError? = nil
            var results = [Model.Transfer]()

            for addresses in addresses.chunked(into: BlockChainDB.ADDRESS_COUNT) {
                if nil != error { break }
                var queryKeys = ["blockchain_id", "start_height", "end_height"] + Array (repeating: "address", count: addresses.count)

                var queryVals = [blockchainId, begBlockNumber.description, endBlockNumber.description] + addresses

                if let maxPageSize = maxPageSize {
                    queryKeys += ["max_page_size"]
                    queryVals += [String(maxPageSize)]
                }

                let semaphore = DispatchSemaphore (value: 0)

                var nextURL: URL? = nil

                self.bdbMakeRequest (path: "transfers", query: zip (queryKeys, queryVals)) {
                    (more: URL?, res: Result<[JSON], QueryError>) in

                    // Append `blocks` with the resulting blocks.
                    results += try! res
                        .flatMap { BlockChainDB.getManyExpected(data: $0, transform: Model.asTransfer) }
                        .recover { error = $0; return [] }.get()

                    nextURL = more

                    semaphore.signal()
                }

                // Wait for the first request
                semaphore.wait()

                // Loop until all 'nextURL' values are queried
                while let url = nextURL, nil == error {
                    self.bdbMakeRequest (url: url, embedded: true, embeddedPath: "transfers") {
                        (more: URL?, res: Result<[JSON], QueryError>) in

                        // Append `transactions` with the resulting transactions.
                        results += try! res
                            .flatMap { BlockChainDB.getManyExpected(data: $0, transform: Model.asTransfer) }
                            .recover { error = $0; return [] }.get()

                        nextURL = more

                        semaphore.signal()
                    }

                    semaphore.wait()
                }
            }

            completion (nil == error
                ? Result.success (results)
                : Result.failure (error!))
        }
    }

    public func getTransfer (transferId: String, completion: @escaping (Result<Model.Transfer, QueryError>) -> Void) {
        bdbMakeRequest (path: "transfers/\(transferId)", query: nil, embedded: false) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            precondition (nil == more)
            completion (res.flatMap {
                BlockChainDB.getOneExpected (id: transferId, data: $0, transform: Model.asTransfer)
            })
        }
    }

    // Transactions

    static let ADDRESS_COUNT = 50

    public func getTransactions (blockchainId: String,
                                 addresses: [String],
                                 begBlockNumber: UInt64? = nil,
                                 endBlockNumber: UInt64? = nil,
                                 includeRaw: Bool = false,
                                 includeProof: Bool = false,
                                 maxPageSize: Int? = nil,
                                 completion: @escaping (Result<[Model.Transaction], QueryError>) -> Void) {
        // This query could overrun the endpoint's page size (typically 5,000).  If so, we'll need
        // to repeat the request for the next batch.
        self.queue.async {
            var error: QueryError? = nil
            var results = [Model.Transaction]()

            let queryKeysBase = [
                "blockchain_id",
                begBlockNumber.map { (_) in "start_height" },
                endBlockNumber.map { (_) in "end_height" },
                "include_proof",
                "include_raw",
                maxPageSize.map { (_) in "max_page_size" }]
                .compactMap { $0 } // Remove `nil` from {beg,end}BlockNumber

            let queryValsBase: [String] = [
                blockchainId,
                begBlockNumber.map { $0.description },
                endBlockNumber.map { $0.description },
                includeProof.description,
                includeRaw.description,
                maxPageSize.map { $0.description }]
                .compactMap { $0 }  // Remove `nil` from {beg,end}BlockNumber

            let semaphore = DispatchSemaphore (value: 0)
            var nextURL: URL? = nil

            func handleResult (more: URL?, res: Result<[JSON], QueryError>) {
                // Append `transactions` with the resulting transactions.
                results += res
                    .flatMap { BlockChainDB.getManyExpected(data: $0, transform: Model.asTransaction) }
                    .getWithRecovery { error = $0; return [] }

                // Record if more exist
                nextURL = more

                // signal completion
                semaphore.signal()
            }

            for addresses in addresses.chunked(into: BlockChainDB.ADDRESS_COUNT) {
                if nil != error { break }

                let queryKeys = queryKeysBase + Array (repeating: "address", count: addresses.count)
                let queryVals = queryValsBase + addresses

                // Ensure a 'clean' start for this set of addresses
                nextURL = nil
                
                // Make the first request.  Ideally we'll get all the transactions in one gulp
                self.bdbMakeRequest (path: "transactions",
                                     query: zip (queryKeys, queryVals),
                                     completion: handleResult)

                // Wait for the first request
                semaphore.wait()

                // Loop until all 'nextURL' values are queried
                while let url = nextURL, nil == error {
                    self.bdbMakeRequest (url: url,
                                         embedded: true,
                                         embeddedPath: "transactions",
                                         completion: handleResult)

                    // Wait for each subsequent result
                    semaphore.wait()
                }
            }

            completion (nil == error
                ? Result.success (results)
                : Result.failure (error!))
        }
    }

    public func getTransaction (transactionId: String,
                                includeRaw: Bool = false,
                                includeProof: Bool = false,
                                completion: @escaping (Result<Model.Transaction, QueryError>) -> Void) {
        let queryKeys = ["include_proof", "include_raw"]
        let queryVals = [includeProof.description, includeRaw.description]

        bdbMakeRequest (path: "transactions/\(transactionId)", query: zip (queryKeys, queryVals), embedded: false) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            precondition (nil == more)
            completion (res.flatMap {
                BlockChainDB.getOneExpected (id: transactionId, data: $0, transform: Model.asTransaction)
            })
        }
    }

    public func createTransaction (blockchainId: String,
                                   hashAsHex: String,
                                   transaction: Data,
                                   completion: @escaping (Result<Void, QueryError>) -> Void) {
        let json: JSON.Dict = [
            "blockchain_id": blockchainId,
            "transaction_id": hashAsHex,
            "data" : transaction.base64EncodedString()
        ]

        makeRequest (bdbDataTaskFunc, bdbBaseURL,
                     path: "/transactions",
                     data: json,
                     httpMethod: "POST",
                     deserializer: { (_) in Result.success(()) },
                     completion: completion)
    }

    // Blocks

    public func getBlocks (blockchainId: String,
                           begBlockNumber: UInt64 = 0,
                           endBlockNumber: UInt64 = 0,
                           includeRaw: Bool = false,
                           includeTx: Bool = false,
                           includeTxRaw: Bool = false,
                           includeTxProof: Bool = false,
                           maxPageSize: Int? = nil,
                           completion: @escaping (Result<[Model.Block], QueryError>) -> Void) {
        self.queue.async {
            var error: QueryError? = nil
            var results = [Model.Block]()

            var queryKeys = ["blockchain_id", "start_height", "end_height",  "include_raw",
                             "include_tx", "include_tx_raw", "include_tx_proof"]

            var queryVals = [blockchainId, begBlockNumber.description, endBlockNumber.description, includeRaw.description,
                             includeTx.description, includeTxRaw.description, includeTxProof.description]

            if let maxPageSize = maxPageSize {
                queryKeys += ["max_page_size"]
                queryVals += [String(maxPageSize)]
            }

            let semaphore = DispatchSemaphore (value: 0)

            var nextURL: URL? = nil

            self.bdbMakeRequest (path: "blocks", query: zip (queryKeys, queryVals)) {
                (more: URL?, res: Result<[JSON], QueryError>) in

                // Append `blocks` with the resulting blocks.
                results += try! res
                    .flatMap { BlockChainDB.getManyExpected(data: $0, transform: Model.asBlock) }
                    .recover { error = $0; return [] }.get()

                nextURL = more

                semaphore.signal()
            }

            // Wait for the first request
            semaphore.wait()

            // Loop until all 'nextURL' values are queried
            while let url = nextURL, nil == error {
                self.bdbMakeRequest (url: url, embedded: true, embeddedPath: "blocks") {
                    (more: URL?, res: Result<[JSON], QueryError>) in

                    // Append `transactions` with the resulting transactions.
                    results += try! res
                        .flatMap { BlockChainDB.getManyExpected(data: $0, transform: Model.asBlock) }
                        .recover { error = $0; return [] }.get()

                    nextURL = more

                    semaphore.signal()
                }

                semaphore.wait()
            }

            completion (nil == error
                ? Result.success (results)
                : Result.failure (error!))
        }
    }

    public func getBlock (blockId: String,
                          includeRaw: Bool = false,
                          includeTx: Bool = false,
                          includeTxRaw: Bool = false,
                          includeTxProof: Bool = false,
                          completion: @escaping (Result<Model.Block, QueryError>) -> Void) {
        let queryKeys = ["include_raw", "include_tx", "include_tx_raw", "include_tx_proof"]

        let queryVals = [includeRaw.description, includeTx.description, includeTxRaw.description, includeTxProof.description]

        bdbMakeRequest (path: "blocks/\(blockId)", query: zip (queryKeys, queryVals), embedded: false) {
            (more: URL?, res: Result<[JSON], QueryError>) in
            precondition (nil == more)
            completion (res.flatMap {
                BlockChainDB.getOneExpected (id: blockId, data: $0, transform: Model.asBlock)
            })
        }
    }

    /// BTC - nothing

    /// ETH

    /// The ETH JSON_RPC request identifier.
    var rid: UInt32 = 0

    /// Return the current request identifier and then increment it.
    var ridIncr: UInt32 {
        let rid = self.rid
        self.rid += 1
        return rid
    }

    public struct ETH {
        public typealias Transaction = (
            hash: String,
            sourceAddr: String,
            targetAddr: String,
            contractAddr: String,
            amount: String,
            gasLimit: String,
            gasPrice: String,
            data: String,
            nonce: String,
            gasUsed: String,
            blockNumber: String,
            blockHash: String,
            blockConfirmations: String,
            blockTransactionIndex: String,
            blockTimestamp: String,
            isError: String)

        static internal func asTransaction (json: JSON) -> ETH.Transaction? {
            guard let hash = json.asString(name: "hash"),
                let sourceAddr   = json.asString(name: "from"),
                let targetAddr   = json.asString(name: "to"),
                let contractAddr = json.asString(name: "contractAddress"),
                let amount       = json.asString(name: "value"),
                let gasLimit     = json.asString(name: "gas"),
                let gasPrice     = json.asString(name: "gasPrice"),
                let data         = json.asString(name: "input"),
                let nonce        = json.asString(name: "nonce"),
                let gasUsed      = json.asString(name: "gasUsed"),
                let blockNumber  = json.asString(name: "blockNumber"),
                let blockHash    = json.asString(name: "blockHash"),
                let blockConfirmations    = json.asString(name: "confirmations"),
                let blockTransactionIndex = json.asString(name: "transactionIndex"),
                let blockTimestamp        = json.asString(name: "timeStamp"),
                let isError      = json.asString(name: "isError")
                else { return nil }

            return (hash: hash,
                    sourceAddr: sourceAddr, targetAddr: targetAddr, contractAddr: contractAddr,
                    amount: amount, gasLimit: gasLimit, gasPrice: gasPrice,
                    data: data, nonce: nonce, gasUsed: gasUsed,
                    blockNumber: blockNumber, blockHash: blockHash,
                    blockConfirmations: blockConfirmations, blockTransactionIndex: blockTransactionIndex, blockTimestamp: blockTimestamp,
                    isError: isError)
        }

        public typealias Log = (
            hash: String,
            contract: String,
            topics: [String],
            data: String,
            gasPrice: String,
            gasUsed: String,
            logIndex: String,
            blockNumber: String,
            blockTransactionIndex: String,
            blockTimestamp: String)

        // BRD API servcies *always* appends `topics` with ""; we need to axe that.
        static internal func dropLastIfEmpty (_ strings: [String]?) -> [String]? {
            return (nil != strings && !strings!.isEmpty && "" == strings!.last!
                ? strings!.dropLast()
                : strings)
        }

        static internal func asLog (json: JSON) -> ETH.Log? {
            guard let hash = json.asString(name: "transactionHash"),
                let contract    = json.asString(name: "address"),
                let topics      = dropLastIfEmpty (json.asStringArray (name: "topics")),
                let data        = json.asString(name: "data"),
                let gasPrice    = json.asString(name: "gasPrice"),
                let gasUsed     = json.asString(name: "gasUsed"),
                let logIndex    = json.asString(name: "logIndex"),
                let blockNumber = json.asString(name: "blockNumber"),
                let blockTransactionIndex = json.asString(name: "transactionIndex"),
                let blockTimestamp        = json.asString(name: "timeStamp")
                else { return nil }

            return (hash: hash, contract: contract, topics: topics, data: data,
                    gasPrice: gasPrice, gasUsed: gasUsed,
                    logIndex: logIndex,
                    blockNumber: blockNumber, blockTransactionIndex: blockTransactionIndex, blockTimestamp: blockTimestamp)
        }

        public typealias Token = (
            address: String,
            symbol: String,
            name: String,
            description: String,
            decimals: UInt32,
            defaultGasLimit: String?,
            defaultGasPrice: String?)

        static internal func asToken (json: JSON) -> ETH.Token? {
            guard let name   = json.asString(name: "name"),
                let symbol   = json.asString(name: "code"),
                let address  = json.asString(name: "contract_address"),
                let decimals = json.asUInt8(name: "scale")
                else { return nil }

            let description = "Token for '\(symbol)'"

            return (address: address, symbol: symbol, name: name, description: description,
                    decimals: UInt32(decimals),
                    defaultGasLimit: nil,
                    defaultGasPrice: nil)
        }
    }

    public func getBalanceAsETH (network: String,
                                 address: String,
                                 completion: @escaping (Result<String,QueryError>) -> Void) {
        let json: JSON.Dict = [
            "jsonrpc" : "2.0",
            "method"  : "eth_getBalance",
            "params"  : [address, "latest"],
            "id"      : ridIncr
        ]

        apiMakeRequestJSON (network: network, data: json,
                            completion: BlockChainDB.getOneResultString(completion))
    }

    public func getBalanceAsTOK (network: String,
                                 address: String,
                                 contract: String,
                                 completion: @escaping (Result<String,QueryError>) -> Void) {
        let json: JSON.Dict = [ "id" : ridIncr ]

        let queryDict = [
            "module"    : "account",
            "action"    : "tokenbalance",
            "address"   : address,
            "contractaddress" : contract
        ]

        apiMakeRequestQUERY (network: network,
                             query: zip (Array(queryDict.keys), Array(queryDict.values)),
                             data: json,
                             completion: BlockChainDB.getOneResultString (completion))
    }

    public func getGasPriceAsETH (network: String,
                                  completion: @escaping (Result<String,QueryError>) -> Void) {
        let json: JSON.Dict = [
            "method" : "eth_gasPrice",
            "params" : [],
            "id" : ridIncr
        ]

        apiMakeRequestJSON (network: network, data: json,
                            completion: BlockChainDB.getOneResultString(completion))
    }

    public func getGasEstimateAsETH (network: String,
                                     from: String,
                                     to: String,
                                     amount: String,
                                     data: String,
                                     completion: @escaping (Result<String,QueryError>) -> Void) {
        var param = ["from":from, "to":to]
        if amount != "0x" { param["value"] = amount }
        if data   != "0x" { param["data"]  = data }

        let json: JSON.Dict = [
            "jsonrpc" : "2.0",
            "method"  : "eth_estimateGas",
            "params"  : [param],
            "id"      : ridIncr
        ]

        apiMakeRequestJSON (network: network, data: json,
                            completion: BlockChainDB.getOneResultString(completion))
    }

    public func submitTransactionAsETH (network: String,
                                        transaction: String,
                                        completion: @escaping (Result<String,QueryError>) -> Void) {
        let json: JSON.Dict = [
            "jsonrpc" : "2.0",
            "method"  : "eth_sendRawTransaction",
            "params"  : [transaction],
            "id"      : ridIncr
        ]

        apiMakeRequestJSON (network: network, data: json,
                            completion: BlockChainDB.getOneResultString(completion))
    }

    public func getTransactionsAsETH (network: String,
                                      address: String,
                                      begBlockNumber: UInt64,
                                      endBlockNumber: UInt64,
                                      completion: @escaping (Result<[ETH.Transaction],QueryError>) -> Void) {
        let json: JSON.Dict = [
            "account" : address,
            "id"      : ridIncr ]

        let queryDict = [
            "module"    : "account",
            "action"    : "txlist",
            "address"   : address,
            "startBlock": begBlockNumber.description,
            "endBlock"  : endBlockNumber.description
        ]

        apiMakeRequestQUERY (network: network, query: zip (Array(queryDict.keys), Array(queryDict.values)), data: json) {
            (res: Result<JSON, QueryError>) in

            completion (res
                .flatMap { (json: JSON) -> Result<[ETH.Transaction], QueryError> in
                    guard let _ = json.asString (name: "status"),
                        let   _ = json.asString (name: "message"),
                        let   result  = json.asArray (name:  "result")
                        else { return Result.failure(QueryError.model("Missed {status, message, result")) }

                    let transactions = result.map { ETH.asTransaction (json: JSON (dict: $0)) }

                    return transactions.contains(where: { nil == $0 })
                        ? Result.failure (QueryError.model ("ETH.Transaction parse error"))
                        : Result.success (transactions as! [ETH.Transaction])
            })
        }
    }

    public func getLogsAsETH (network: String,
                              contract: String?,
                              address: String,
                              event: String,
                              begBlockNumber: UInt64,
                              endBlockNumber: UInt64,
                              completion: @escaping (Result<[ETH.Log],QueryError>) -> Void) {
        let json: JSON.Dict = [ "id" : ridIncr ]

        var queryDict = [
            "module"    : "logs",
            "action"    : "getLogs",
            "fromBlock" : begBlockNumber.description,
            "toBlock"   : endBlockNumber.description,
            "topic0"    : event,
            "topic1"    : address,
            "topic_1_2_opr" : "or",
            "topic2"    : address
        ]
        if nil != contract { queryDict["address"] = contract! }

        apiMakeRequestQUERY (network: network, query: zip (Array(queryDict.keys), Array(queryDict.values)), data: json) {
            (res: Result<JSON, QueryError>) in

            completion (res
                .flatMap { (json: JSON) -> Result<[ETH.Log], QueryError> in
                    guard let _ = json.asString (name: "status"),
                        let   _ = json.asString (name: "message"),
                        let   result  = json.asArray (name:  "result")
                        else { return Result.failure(QueryError.model("Missed {status, message, result")) }

                    let logs = result.map { ETH.asLog (json: JSON (dict: $0)) }

                    return logs.contains(where: { nil == $0 })
                        ? Result.failure (QueryError.model ("ETH.Log parse error"))
                        : Result.success (logs as! [ETH.Log])
                })
        }
    }

    public func getTokensAsETH (completion: @escaping (Result<[ETH.Token],QueryError>) -> Void) {

        // Everything returned by BRD must/absolutely-must be in BlockChainDB currencies.  Thus,
        // when stubbed, so too must these.
        apiMakeRequestTOKEN () { (res: Result<[JSON.Dict], QueryError>) in
            completion (res
                .flatMap { (jsonArray: [JSON.Dict]) -> Result<[ETH.Token], QueryError> in
                    let tokens = jsonArray.map { ETH.asToken (json: JSON (dict: $0)) }

                    return tokens.contains(where: { nil == $0 })
                        ? Result.failure (QueryError.model ("ETH.Tokens parse error"))
                        : Result.success (tokens as! [ETH.Token])
                })
        }
    }

    public func getBlocksAsETH (network: String,
                                address: String,
                                interests: UInt32,
                                blockStart: UInt64,
                                blockStop: UInt64,
                                completion: @escaping (Result<[UInt64],QueryError>) -> Void) {
        func parseBlockNumber (_ s: String) -> UInt64? {
            return s.starts(with: "0x")
                ? UInt64 (s.dropFirst(2), radix: 16)
                : UInt64 (s)
        }

        queue.async {
            let semaphore = DispatchSemaphore (value: 0)

            var transactions: [ETH.Transaction] = []
            var transactionsSuccess: Bool = false

            var logs: [ETH.Log] = []
            var logsSuccess: Bool = false

            self.getTransactionsAsETH (network: network,
                                       address: address,
                                       begBlockNumber: blockStart,
                                       endBlockNumber: blockStop) {
                                        (res: Result<[ETH.Transaction],QueryError>) in
                                        res.resolve (
                                            success: {
                                                transactions.append (contentsOf: $0)
                                                transactionsSuccess = true },
                                            failure: { (_) in transactionsSuccess = false })
                                        semaphore.signal() }

            self.getLogsAsETH (network: network,
                               contract: nil,
                               address: address,
                               event: "0xa9059cbb",  // ERC20 Transfer
                               begBlockNumber: blockStart,
                               endBlockNumber: blockStop) {
                                (res: Result<[ETH.Log],QueryError>) in
                                res.resolve (
                                    success: {
                                        logs.append (contentsOf: $0)
                                        logsSuccess = true },
                                    failure: { (_) in logsSuccess = false })
                                semaphore.signal() }

            semaphore.wait()
            semaphore.wait()

            var numbers: [UInt64] = []
            if transactionsSuccess && logsSuccess {
                numbers += transactions
                    .filter {
                        return (
                            /* CLIENT_GET_BLOCKS_TRANSACTIONS_AS_TARGET */
                            (0 != (interests & UInt32 (1 << 0)) && address == $0.sourceAddr) ||

                                /* CLIENT_GET_BLOCKS_TRANSACTIONS_AS_TARGET */
                                (0 != (interests & UInt32 (1 << 1)) && address == $0.targetAddr))
                    }
                    .map { parseBlockNumber ($0.blockNumber) ?? 0 }

                numbers += logs
                    .filter {
                        if $0.topics.count != 3 { return false }
                        return (
                            /* CLIENT_GET_BLOCKS_LOGS_AS_SOURCE */
                            (0 != (interests & UInt32 (1 << 2)) && address == $0.topics[1]) ||
                                /* CLIENT_GET_BLOCKS_LOGS_AS_TARGET */
                                (0 != (interests & UInt32 (1 << 3)) && address == $0.topics[2]))
                    }
                    .map { parseBlockNumber($0.blockNumber) ?? 0}

                completion (Result.success (numbers))
            }
            else {
                completion (Result.failure(QueryError.noData))
            }
        }
    }

    public func getBlockNumberAsETH (network: String,
                                     completion: @escaping (Result<String,QueryError>) -> Void) {
        let json: JSON.Dict = [
            "method" : "eth_blockNumber",
            "params" : [],
            "id" : ridIncr
        ]

        apiMakeRequestJSON (network: network, data: json,
                            completion: BlockChainDB.getOneResultString (completion))
    }
    
    public func getNonceAsETH (network: String,
                               address: String,
                               completion: @escaping (Result<String,QueryError>) -> Void) {
        let json: JSON.Dict = [
            "method" : "eth_getTransactionCount",
            "params" : [address, "latest"],
            "id" : ridIncr
        ]

        apiMakeRequestJSON (network: network, data: json,
                            completion: BlockChainDB.getOneResultString (completion))
    }

     static internal let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    internal struct JSON {
        typealias Dict = [String:Any]

        let dict: Dict

        init (dict: Dict) {
            self.dict = dict
        }

        internal func asString (name: String) -> String? {
            return dict[name] as? String
        }

        internal func asBool (name: String) -> Bool? {
            return dict[name] as? Bool
        }

        internal func asInt64 (name: String) -> Int64? {
            return (dict[name] as? NSNumber)
                .flatMap { Int64 (exactly: $0)}
        }

        internal func asUInt64 (name: String) -> UInt64? {
            return (dict[name] as? NSNumber)
                .flatMap { UInt64 (exactly: $0)}
        }

        internal func asUInt32 (name: String) -> UInt32? {
            return (dict[name] as? NSNumber)
                .flatMap { UInt32 (exactly: $0)}
        }

        internal func asUInt8 (name: String) -> UInt8? {
            return (dict[name] as? NSNumber)
                .flatMap { UInt8 (exactly: $0)}
        }

        internal func asDate (name: String) -> Date? {
            return (dict[name] as? String)
                .flatMap { dateFormatter.date (from: $0) }
        }

        internal func asData (name: String) -> Data? {
            return (dict[name] as? String)
                .flatMap { Data (base64Encoded: $0)! }
        }

        internal func asArray (name: String) -> [Dict]? {
            return dict[name] as? [Dict]
        }

        internal func asDict (name: String) -> Dict? {
            return dict[name] as? Dict
        }

        internal func asStringArray (name: String) -> [String]? {
            return dict[name] as? [String]
        }

        internal func asJSON (name: String) -> JSON? {
            return asDict(name: name).map { JSON (dict: $0) }
        }
    }

    private static func deserializeAsJSON<T> (_ data: Data?) -> Result<T, QueryError> {
        guard let data = data else {
            return Result.failure (QueryError.noData);
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? T
                else {
                    print ("SYS: BDB:API: ERROR: JSON.Dict: '\(data.map { String(format: "%c", $0) }.joined())'")
                    return Result.failure(QueryError.jsonParse(nil)) }

            return Result.success (json)
        }
        catch let jsonError as NSError {
            print ("SYS: BDB:API: ERROR: JSON.Error: '\(data.map { String(format: "%c", $0) }.joined())'")
            return Result.failure (QueryError.jsonParse (jsonError))
        }
    }

    private func sendRequest<T> (_ request: URLRequest,
                                 _ dataTaskFunc: DataTaskFunc,
                                 _ responseSuccess: [Int],
                                 deserializer: @escaping (_ data: Data?) -> Result<T, QueryError>,
                                 completion: @escaping (Result<T, QueryError>) -> Void) {
        dataTaskFunc (session, request) { (data, res, error) in
            guard nil == error else {
                completion (Result.failure(QueryError.submission (error!))) // NSURLErrorDomain
                return
            }

            guard let res = res as? HTTPURLResponse else {
                completion (Result.failure (QueryError.url ("No Response")))
                return
            }

            // Short-circuit ripple
            #if true
            if "transactions" == request.url?.lastPathComponent &&
                true == request.url?.query?.starts (with: "blockchain_id=ripple") {
                completion (deserializer (BlockChainDB.xrpStubbedTransactionsDataOne))
                return
            }
            #endif

            guard responseSuccess.contains(res.statusCode) else {
                completion (Result.failure (QueryError.response(res.statusCode)))
                return
            }

            completion (deserializer (data))
        }.resume()
    }

    /// Update `request` with 'application/json' headers and the httpMethod
    internal func decorateRequest (_ request: inout URLRequest, httpMethod: String) {
        request.addValue ("application/json", forHTTPHeaderField: "Accept")
        request.addValue ("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = httpMethod
    }

    /// https://tools.ietf.org/html/rfc7231#page-24
    internal func responseSuccess (_ httpMethod: String) -> [Int] {
        switch httpMethod {
        case "GET":
            //            The 200 (OK) status code indicates that the request has succeeded.
            return [200]

        case "POST":
            //            If one or more resources has been created on the origin server as a
            //            result of successfully processing a POST request, the origin server
            //            SHOULD send a 201 (Created) response containing a Location header
            //            field that provides an identifier for the primary resource created
            //            (Section 7.1.2) and a representation that describes the status of the
            //            request while referring to the new resource(s).
            //
            //            Responses to POST requests are only cacheable when they include
            //            explicit freshness information (see Section 4.2.1 of [RFC7234]).
            //            However, POST caching is not widely implemented.  For cases where an
            //            origin server wishes the client to be able to cache the result of a
            //            POST in a way that can be reused by a later GET, the origin server
            //            MAY send a 200 (OK) response containing the result and a
            //            Content-Location header field that has the same value as the POST's
            //            effective request URI (Section 3.1.4.2).
            return [200, 201]

        case "DELETE":
            //            If a DELETE method is successfully applied, the origin server SHOULD
            //            send a 202 (Accepted) status code if the action will likely succeed
            //            but has not yet been enacted, a 204 (No Content) status code if the
            //            action has been enacted and no further information is to be supplied,
            //            or a 200 (OK) status code if the action has been enacted and the
            //            response message includes a representation describing the status.
            return [200, 202, 204]

        case "PUT":
            //            If the target resource does not have a current representation and the
            //            PUT successfully creates one, then the origin server MUST inform the
            //            user agent by sending a 201 (Created) response.  If the target
            //            resource does have a current representation and that representation
            //            is successfully modified in accordance with the state of the enclosed
            //            representation, then the origin server MUST send either a 200 (OK) or
            //            a 204 (No Content) response to indicate successful completion of the
            //            request.
            return [200, 201, 204]

        default:
            return [200]
        }
    }

    /// Make a reqeust but w/o the need to create a URL.  Just create a URLRequest, decorate it,
    /// and then send it off.
    internal func makeRequest<T> (_ dataTaskFunc: DataTaskFunc,
                                  url: URL,
                                  httpMethod: String = "POST",
                                  deserializer: @escaping (_ data: Data?) -> Result<T, QueryError> = deserializeAsJSON,
                                  completion: @escaping (Result<T, QueryError>) -> Void) {
        var request = URLRequest (url: url)
        decorateRequest(&request, httpMethod: httpMethod)
        sendRequest (request, dataTaskFunc, responseSuccess (httpMethod), deserializer: deserializer, completion: completion)
    }

    /// Make a request by building a URL request from baseURL, path, query and data.  Once we have
    /// a request, decorate it and then send it off.
    internal func makeRequest<T> (_ dataTaskFunc: DataTaskFunc,
                                  _ baseURL: String,
                                  path: String,
                                  query: Zip2Sequence<[String],[String]>? = nil,
                                  data: JSON.Dict? = nil,
                                  httpMethod: String = "POST",
                                  deserializer: @escaping (_ data: Data?) -> Result<T, QueryError> = deserializeAsJSON,
                                  completion: @escaping (Result<T, QueryError>) -> Void) {
        guard var urlBuilder = URLComponents (string: baseURL)
            else { completion (Result.failure(QueryError.url("URLComponents"))); return }

        urlBuilder.path = path.starts(with: "/") ? path : "/\(path)"
        if let query = query {
            urlBuilder.queryItems = query.map { URLQueryItem (name: $0, value: $1) }
        }

        guard let url = urlBuilder.url
            else { completion (Result.failure (QueryError.url("URLComponents.url"))); return }

        print ("SYS: BDB: Request: \(url.absoluteString): Method: \(httpMethod): Data: \(data?.description ?? "[]")")

        var request = URLRequest (url: url)
        decorateRequest(&request, httpMethod: httpMethod)

        // If we have data as a JSON.Dict, then add it as the httpBody to the request.
        if let data = data {
            do { request.httpBody = try JSONSerialization.data (withJSONObject: data, options: []) }
            catch let jsonError as NSError {
                completion (Result.failure (QueryError.jsonParse(jsonError)))
            }
        }

        sendRequest (request, dataTaskFunc, responseSuccess (httpMethod), deserializer: deserializer, completion: completion)
    }

    /// We have two flavors of bdbMakeRequest but they both handle their result identically.
    /// Provide this helper function to process the JSON result to extract the content and then
    /// to call the completion handler.
    internal func bdbHandleResult (_ res: Result<JSON.Dict, QueryError>,
                                   embedded: Bool = true,
                                   embeddedPath path: String,
                                   completion: @escaping (URL?, Result<[JSON], QueryError>) -> Void) {
        let res = res.map { JSON (dict: $0) }

        // Determine is there are more results for this query.  The BlockChainDB
        // will provide a "_links" JSON dictionary with a "next" field that provides
        // a URL to use for the remaining values.  The "_links" dictionary looks
        // like
        // "_links":{ "next": { "href": <url> },
        //            "self": { "href": <url> }}

        let moreURL = try? res
            .map {  $0.asJSON (name: "_links") }
            .map { $0?.asJSON (name: "next")   }
            .map { $0?.asString(name: "href")  }      // -> Result<String?, ...>
            .map { $0.flatMap { URL (string: $0) } }  // -> Result<URL?,    ...>
            .recover { (ignore) in return nil }       // -> ...
            .get ()
        // moreURL will be `nil` if `res` was not .success

        // Invoke the callback with `moreURL` and Result with [JSON]
        completion (moreURL,
                    res.flatMap { (json: JSON) -> Result<[JSON], QueryError> in
                        let json = (embedded
                            ? (json.asDict(name: "_embedded")?[path] ?? [])
                            : [json.dict])

                        guard let data = json as? [JSON.Dict]
                            else { return Result.failure(QueryError.model ("[JSON.Dict] expected")) }

                        return Result.success (data.map { JSON (dict: $0) })
        })
    }

    /// In the case where a BDB request has 'paged' (with more results than and be returned in
    /// one query, the BDB will give us a URL to use for the next page.  Thus this function
    /// is identical to the following bdbMakeReqeust(path:query:embedded:completion) except that
    /// instead of building a URL, we've got a URL.  In this function, we need to pass in
    /// the 'embeddedPath' so that the JSON parser can find the data.
    internal func bdbMakeRequest (url: URL,
                                  embedded: Bool = true,
                                  embeddedPath: String,
                                  completion: @escaping (URL?, Result<[JSON], QueryError>) -> Void) {
        makeRequest(bdbDataTaskFunc, url: url, httpMethod: "GET") {
            self.bdbHandleResult ($0, embedded: embedded, embeddedPath: embeddedPath, completion: completion)
        }
    }

    internal func bdbMakeRequest (path: String,
                                  query: Zip2Sequence<[String],[String]>?,
                                  embedded: Bool = true,
                                  completion: @escaping (URL?, Result<[JSON], QueryError>) -> Void) {
        makeRequest (bdbDataTaskFunc, bdbBaseURL,
                     path: path,
                     query: query,
                     data: nil,
                     httpMethod: "GET") {
                        self.bdbHandleResult ($0, embedded: embedded, embeddedPath: path, completion: completion)
        }
    }

    private func apiGetNetworkName (_ name: String) -> String {
        let name = name.lowercased()
        return name == "testnet" ? "ropsten" : name
    }
    
    internal func apiMakeRequestJSON (network: String,
                                      data: JSON.Dict,
                                      completion: @escaping (Result<JSON, QueryError>) -> Void) {
        let path = "/ethq/\(apiGetNetworkName(network))/proxy"
        makeRequest (apiDataTaskFunc, apiBaseURL,
                     path: path,
                     query: nil,
                     data: data,
                     httpMethod: "POST") { (res: Result<JSON.Dict, QueryError>) in
                        completion (res.map { JSON (dict: $0) })
        }
    }

    internal func apiMakeRequestQUERY (network: String,
                                       query: Zip2Sequence<[String],[String]>?,
                                       data: JSON.Dict,
                                       completion: @escaping (Result<JSON, QueryError>) -> Void) {
        let path = "/ethq/\(apiGetNetworkName(network))/query"
        makeRequest (apiDataTaskFunc, apiBaseURL,
                     path: path,
                     query: query,
                     data: data,
                     httpMethod: "POST") { (res: Result<JSON.Dict, QueryError>) in
                        completion (res.map { JSON (dict: $0) })
        }
    }

    internal func apiMakeRequestTOKEN (completion: @escaping (Result<[JSON.Dict], QueryError>) -> Void) {
        let path = "/currencies"
        makeRequest (apiDataTaskFunc, apiBaseURL,
                     path: path,
                     query: zip(["type"], ["erc20"]),
                     data: nil,
                     httpMethod: "GET",
                     completion: completion)
    }

    ///
    /// Convert an array of JSON into a single value using a specified transform
    ///
    /// - Parameters:
    ///   - id: If not value exists, report QueryError.NoEntity (id: id)
    ///   - data: The array of JSON
    ///   - transform: Function to tranfrom JSON -> T?
    ///
    /// - Returns: A `Result` with success of `T`
    ///
    private static func getOneExpected<T> (id: String, data: [JSON], transform: (JSON) -> T?) -> Result<T, QueryError> {
        switch data.count {
        case  0:
            return Result.failure (QueryError.noEntity(id: id))
        case  1:
            guard let transfer = transform (data[0])
                else { return Result.failure (QueryError.model ("(JSON) -> T transform error (one)"))}
            return Result.success (transfer)
        default:
            return Result.failure (QueryError.model ("(JSON) -> T expected one only"))
        }
    }

    ///
    /// Convert an array of JSON into an array of `T` using a specified transform.  If any
    /// individual JSON cannot be converted, then a QueryError is return for `Result`
    ///
    /// - Parameters:
    ///   - data: Array of JSON
    ///   - transform: Function to transform JSON -> T?
    ///
    /// - Returns: A `Result` with success of `[T]`
    ///
    private static func getManyExpected<T> (data: [JSON], transform: (JSON) -> T?) -> Result<[T], QueryError> {
        let results = data.map (transform)
        return results.contains(where: { $0 == nil })
            ? Result.failure(QueryError.model ("(JSON) -> T transform error (many)"))
            : Result.success(results as! [T])
    }

    ///
    /// Given JSON extract a value and then apply a completion
    ///
    /// - Parameters:
    ///   - extract: A function that extracts the "result" field from JSON to return T?
    ///   - completion: A function to process a Result on T
    ///
    /// - Returns: A function to process a Result on JSON
    ///
    private static func getOneResult<T> (_ extract: @escaping (JSON) -> (String) ->T?,
                                         _ completion: @escaping (Result<T,QueryError>) -> Void) -> ((Result<JSON,QueryError>) -> Void) {
        return { (res: Result<JSON,QueryError>) in
            completion (res.flatMap {
                extract ($0)("result").map { Result.success ($0) } // extract()() returns an optional
                    ?? Result<T,QueryError>.failure(QueryError.noData) })
        }
    }


    /// Given JSON extract a value with JSON.asString (returning String?) and then apply a completion
    ///
    /// - Parameter completion: A function to process a Result on String
    ///
    /// - Returns: A function to process a Result on JSON
    ///
    private static func getOneResultString (_ completion: @escaping (Result<String,QueryError>) -> Void) -> ((Result<JSON,QueryError>) -> Void) {
        return getOneResult (JSON.asString, completion)
    }

    private static let xrpStubbedTransactionsDataTwo: Data = """
{
    "_embedded": {
        "transactions": [
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "171",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rP7APMvtTo84B93t4zMr121pPt9XXsPa1E",
                            "index": 0,
                            "meta": {
                                "receiver_balance": "11817352213",
                                "receiver_previous_balance": "11817352384"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258",
                            "transfer_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "136779",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "unknown",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "11817488992",
                                "receiver_previous_balance": "11817352213",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rP7APMvtTo84B93t4zMr121pPt9XXsPa1E",
                            "transaction_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258",
                            "transfer_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258:1"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258:2"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "279864407",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rs54sSB5u8jK9eiugdyy96aBfshVfKehQJ",
                            "index": 2,
                            "meta": {
                                "sender_balance": "31792035554",
                                "sender_previous_balance": "32071899961",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "unknown",
                            "transaction_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258",
                            "transfer_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258:2"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258:3"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "279727628",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "unknown",
                            "index": 3,
                            "meta": {
                                "receiver_balance": "59175645428",
                                "receiver_previous_balance": "58895917800",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rhsqnxYoZ6r19i6mEDmsY7XnkGEuy7FAA2",
                            "transaction_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258",
                            "transfer_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258:3"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:94F04CAD573D245E4FE30DA6FFAA5E349C041584419CB895818BC435A0335CD6"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "94F04CAD573D245E4FE30DA6FFAA5E349C041584419CB895818BC435A0335CD6",
                "block_height": 48899100,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1,
                "fee": {
                    "amount": "171",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-25T19:18:50.000+0000",
                "hash": "8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258",
                "identifier": "8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258",
                "index": 41,
                "proof": null,
                "raw": "EgAAIoAHAAAkAAQxlyAbAuokJGHVw41+pMaAAAAAAAAAAAAAAAAAAENOWQAAAAAAu5jWHpoSzgaHiz5Vun/A8QfYR2hoQAAAAAAAAKtpQAAAF0h26ABzIQJn/Dphz2XrJ8rDCifRBj+txVF6t5bPM3dDvSTcnaQQqXRGMEQCIEiAS7OrzPFUbY/wLNXg89UaU+W3tpoUDZmOOkb+5SEiAiB45COYEx3PY8ocvQoAQ7ohYd6775xJXrx76pxNhVh3DYEU9ptln6NAN8DYxflsXrmZ0pvzhxGDFLuY1h6aEs4Gh4s+Vbp/wPEH2EdoARIwAAAAAAAAAAAAAAAAQ05ZAAAAAABByL4sCmqhdHG59tCvkqqxyU1aJTAAAAAAAAAAAAAAAABDTlkAAAAAAM7W6ZNw1cAO9Ov3JWfamfVmG/s6MAAAAAAAAAAAAAAAAFVMVAAAAAAAztbpk3DVwA706/clZ9qZ9WYb+zoQAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                "size": 384,
                "status": "confirmed",
                "timestamp": "2019-07-25T19:18:50.000+0000",
                "transaction_id": "ripple-testnet:8CF8DAAA703FABA4A3235B6D7F3AF70A808DEB3B47EA9684CB5E91087F9EF258"
            }
        ]
    },
    "_links": {
        "self": {
            "href": "http://localhost:8080/transactions?blockchain_id=ripple-testnet&start_height=0&end_height=50000000&include_proof=false&include_raw=true&address=rP7APMvtTo84B93t4zMr121pPt9XXsPa1E"
        }
    }
}
""".data(using: String.Encoding.utf8)!

    private static let xrpStubbedTransactionsDataOne: Data = """
{
    "_embedded": {
        "transactions": [
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "r32MZ4sbsLHmbssegmNShrrm16Jwo9SAd1",
                            "index": 0,
                            "meta": {
                                "sender_balance": "169658961",
                                "sender_previous_balance": "169658973"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
                            "transfer_id": "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "31392246",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "r32MZ4sbsLHmbssegmNShrrm16Jwo9SAd1",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "31392246",
                                "receiver_previous_balance": "0",
                                "sender_balance": "138266715",
                                "sender_previous_balance": "169658961",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "transaction_id": "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
                            "transfer_id": "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:BAF970FCFE59BCBF3C5725B707B5F62FB655DA0591078CE5A7392F5D6E4C5F9A"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "BAF970FCFE59BCBF3C5725B707B5F62FB655DA0591078CE5A7392F5D6E4C5F9A",
                "block_height": 48719657,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1833584,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-17T18:13:50.000+0000",
                "hash": "21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
                "identifier": "21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
                "index": 24,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAAAS4AAeJAIBsC52c7YUAAAAAB3wH2aEAAAAAAAAAMcyECI3hnmlFvOFWBfd4BKH5rcf8x4uTMj7GI+ivq+K6/puB0RzBFAiEAuPdjiDK4gUhAdiBGV68ZtJb1duKtwZ7muhQXmjfaT9wCIEkbpstJX7FElHQvs4mJWRnvF6Qe7miw0mVMAz6DEhK8gRRTF8SmU6dMT9Nq6abIFsuLil12K4MUE/BRV/qT3A6nGfx3ZEweNgR4geA=",
                "size": 194,
                "status": "CONFIRMED",
                "timestamp": "2019-07-17T18:13:50.000+0000",
                "transaction_id": "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "r32MZ4sbsLHmbssegmNShrrm16Jwo9SAd1",
                            "index": 0,
                            "meta": {
                                "sender_balance": "138266703",
                                "sender_previous_balance": "138266715"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A",
                            "transfer_id": "ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "31294007",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "r32MZ4sbsLHmbssegmNShrrm16Jwo9SAd1",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "62686253",
                                "receiver_previous_balance": "31392246",
                                "sender_balance": "106972696",
                                "sender_previous_balance": "138266703",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "transaction_id": "ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A",
                            "transfer_id": "ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:113390823C178E94433AE8A879DEDA0C413EBE3ABFFB03B00221BE267F241754"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "113390823C178E94433AE8A879DEDA0C413EBE3ABFFB03B00221BE267F241754",
                "block_height": 48720292,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1832949,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-17T18:55:02.000+0000",
                "hash": "A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A",
                "identifier": "A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A",
                "index": 65,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAAAiAbAudptmFAAAAAAd2CN2hAAAAAAAAADHMhAiN4Z5pRbzhVgX3eASh+a3H/MeLkzI+xiPor6viuv6bgdEYwRAIgarjwKOljVFOTHhSOWudTttDKwcO+5jL1LXsEFgfOfhQCIF/KS1l2pAG74EnsvGo1ueN9C6ZxiqPhlfgLsFwBdFwvgRRTF8SmU6dMT9Nq6abIFsuLil12K4MUE/BRV/qT3A6nGfx3ZEweNgR4geA=",
                "size": 188,
                "status": "CONFIRMED",
                "timestamp": "2019-07-17T18:55:02.000+0000",
                "transaction_id": "ripple-testnet:A3A8C79A4D1938001BFC32843E0BBBABA99F8ACEC770FC20B001AB41CF3E9E3A"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 0,
                            "meta": {
                                "sender_balance": "62686241",
                                "sender_previous_balance": "62686253",
                                "txresult": "tecNO_DST_INSUF_XRP"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6",
                            "transfer_id": "ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "0",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 1,
                            "meta": {
                                "txresult": "tecNO_DST_INSUF_XRP"
                            },
                            "to_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "transaction_id": "ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6",
                            "transfer_id": "ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:0005EB10BD6888B60E318EAF91362B1E3B411168B65E536AFFAEAC6DB20D0C52"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "0005EB10BD6888B60E318EAF91362B1E3B411168B65E536AFFAEAC6DB20D0C52",
                "block_height": 48720606,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1832635,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-17T19:15:30.000+0000",
                "hash": "1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6",
                "identifier": "1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6",
                "index": 44,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAAAWFAAAAAAC3GwGhAAAAAAAAADHMhA3hFAZZqqFLTNCX2xvdvqySlU2wphW1x6nF/rRTrC+gfdEcwRQIhAPKwaT+a+gMuFrfdrwfczXiy+6A9mU2dMpr1wuFUnEo5AiAnRFxhsQdQ8LvUx/hx88fGabDY8Xgk0L1S7Y50zEQHfoEUE/BRV/qT3A6nGfx3ZEweNgR4geCDFDpmdWFn7gyz/vCrflnErItW4wZc",
                "size": 183,
                "status": "FAILED",
                "timestamp": "2019-07-17T19:15:30.000+0000",
                "transaction_id": "ripple-testnet:1F163749FDC34C09E3D533104C59AC2889A4D36E3104BF56E61EF6BEA87508A6"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 0,
                            "meta": {
                                "sender_balance": "62686229",
                                "sender_previous_balance": "62686241"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8",
                            "transfer_id": "ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "30000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "30000000",
                                "receiver_previous_balance": "0",
                                "sender_balance": "32686229",
                                "sender_previous_balance": "62686229",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "transaction_id": "ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8",
                            "transfer_id": "ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:7B2A13386497D7A6F385A615795AC9DA986559ED2E996C7E26D59F42C0EA2239"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "7B2A13386497D7A6F385A615795AC9DA986559ED2E996C7E26D59F42C0EA2239",
                "block_height": 48720680,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1832561,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-17T19:20:11.000+0000",
                "hash": "50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8",
                "identifier": "50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8",
                "index": 16,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAAAmFAAAAAAcnDgGhAAAAAAAAADHMhA3hFAZZqqFLTNCX2xvdvqySlU2wphW1x6nF/rRTrC+gfdEcwRQIhAJ975wQsEE5V/oUcEkryOsMhUNGTbXvidioJUJHYVpDOAiBRvp7rDXGCWNLbtNdOCyvm3JJy4vBMB4UetZP0tdbeGoEUE/BRV/qT3A6nGfx3ZEweNgR4geCDFDpmdWFn7gyz/vCrflnErItW4wZc",
                "size": 183,
                "status": "CONFIRMED",
                "timestamp": "2019-07-17T19:20:11.000+0000",
                "transaction_id": "ripple-testnet:50EA9C78E4BEDCC99EC1B26CDF919D8A75C25D7FEC1748154EDB09F9F13DE7B8"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 0,
                            "meta": {
                                "sender_balance": "29999988",
                                "sender_previous_balance": "30000000"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4",
                            "transfer_id": "ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "1000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "33686229",
                                "receiver_previous_balance": "32686229",
                                "sender_balance": "28999988",
                                "sender_previous_balance": "29999988",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "transaction_id": "ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4",
                            "transfer_id": "ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:4BB076598B6DC89EC0EC0DA1BFB896961164CE5B9DC6B05689B44A909C16E582"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "4BB076598B6DC89EC0EC0DA1BFB896961164CE5B9DC6B05689B44A909C16E582",
                "block_height": 48722114,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1831127,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-17T20:53:11.000+0000",
                "hash": "E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4",
                "identifier": "E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4",
                "index": 10,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAAAWFAAAAAAA9CQGhAAAAAAAAADHMhAjsy4/swbmNnxBZW7YNOKZWzaQCMzm9+XGf7gj/yZDWCdEcwRQIhANrDHQ4Ef8THaMBbicbNKXg3/elm0SXUuare9nBnVxgCAiA6cXCjpLBtL0nq3Alov2pAN33dJ+B68RWMeI1O5FJcGIEUOmZ1YWfuDLP+8Kt+WcSsi1bjBlyDFBPwUVf6k9wOpxn8d2RMHjYEeIHg",
                "size": 183,
                "status": "CONFIRMED",
                "timestamp": "2019-07-17T20:53:11.000+0000",
                "transaction_id": "ripple-testnet:E46F8FF406A5A0328C61276CC747748B48CE1E14A0C6BF66ADAA8AC6278D5AA4"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 0,
                            "meta": {
                                "sender_balance": "28999976",
                                "sender_previous_balance": "28999988"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534",
                            "transfer_id": "ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "1000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "34686229",
                                "receiver_previous_balance": "33686229",
                                "sender_balance": "27999976",
                                "sender_previous_balance": "28999976",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "transaction_id": "ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534",
                            "transfer_id": "ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:FD22E7334CBDC2C46C81288FF5F66E127471FCA8A7EE9BF1DC574CEFAE6810AC"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "FD22E7334CBDC2C46C81288FF5F66E127471FCA8A7EE9BF1DC574CEFAE6810AC",
                "block_height": 48722180,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1831061,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-17T20:57:30.000+0000",
                "hash": "B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534",
                "identifier": "B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534",
                "index": 43,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAAAmFAAAAAAA9CQGhAAAAAAAAADHMhAjsy4/swbmNnxBZW7YNOKZWzaQCMzm9+XGf7gj/yZDWCdEcwRQIhALzmqpEs0XaXtoN6CM9hAsSaLScdgOuqsLcX40Bo9XxBAiA3zPgaOSb47q9AsJx8ZNP4LYkN48FhWXSwGPxTUe/WE4EUOmZ1YWfuDLP+8Kt+WcSsi1bjBlyDFBPwUVf6k9wOpxn8d2RMHjYEeIHg",
                "size": 183,
                "status": "CONFIRMED",
                "timestamp": "2019-07-17T20:57:30.000+0000",
                "transaction_id": "ripple-testnet:B96534138737DD80FDB371FE2EE4A5F3D427D20119AA625576B0C0B3F27D9534"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 0,
                            "meta": {
                                "sender_balance": "27999964",
                                "sender_previous_balance": "27999976"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623",
                            "transfer_id": "ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "1000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "35686229",
                                "receiver_previous_balance": "34686229",
                                "sender_balance": "26999964",
                                "sender_previous_balance": "27999964",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "transaction_id": "ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623",
                            "transfer_id": "ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:4F47EAD8B4CF03A43D5CA63F14ABC2BE6B2476A263B72B07ABFF912836223977"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "4F47EAD8B4CF03A43D5CA63F14ABC2BE6B2476A263B72B07ABFF912836223977",
                "block_height": 48738510,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1814731,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-18T14:34:01.000+0000",
                "hash": "3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623",
                "identifier": "3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623",
                "index": 11,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAAA2FAAAAAAA9CQGhAAAAAAAAADHMhAjsy4/swbmNnxBZW7YNOKZWzaQCMzm9+XGf7gj/yZDWCdEcwRQIhAMc7DSB2nt92UBip+zzSC5UhiMVCPjFpRpcrhtneWbwtAiA6Ujf9qSIc6avGqSCFE5j9kqw6Zet9ufuYMUmp5ezjGYEUOmZ1YWfuDLP+8Kt+WcSsi1bjBlyDFBPwUVf6k9wOpxn8d2RMHjYEeIHg",
                "size": 183,
                "status": "CONFIRMED",
                "timestamp": "2019-07-18T14:34:01.000+0000",
                "transaction_id": "ripple-testnet:3BCDD413424AF1C6EDE29A5DA09F38DEAFDC4C07AC014999FD87EB7EF58CA623"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 0,
                            "meta": {
                                "sender_balance": "35686217",
                                "sender_previous_balance": "35686229"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE",
                            "transfer_id": "ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "1000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "27999964",
                                "receiver_previous_balance": "26999964",
                                "sender_balance": "34686217",
                                "sender_previous_balance": "35686217",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "transaction_id": "ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE",
                            "transfer_id": "ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:E0F4AACD8BD602E067BEC4E18CFD2618E7698B50810E8E6BAF96B206C10BED2C"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "E0F4AACD8BD602E067BEC4E18CFD2618E7698B50810E8E6BAF96B206C10BED2C",
                "block_height": 48738642,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1814599,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-18T14:42:41.000+0000",
                "hash": "3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE",
                "identifier": "3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE",
                "index": 33,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAAA2FAAAAAAA9CQGhAAAAAAAAADHMhA3hFAZZqqFLTNCX2xvdvqySlU2wphW1x6nF/rRTrC+gfdEcwRQIhAOdIj1LOhHoG9XZxRe9RrmPKfHqo40IMiPP8eBKq8Gc2AiAWGhQLfeE8A9RAUwygEhdAYb8h+CGGlPzLl/2xAhjFXYEUE/BRV/qT3A6nGfx3ZEweNgR4geCDFDpmdWFn7gyz/vCrflnErItW4wZc",
                "size": 183,
                "status": "CONFIRMED",
                "timestamp": "2019-07-18T14:42:41.000+0000",
                "transaction_id": "ripple-testnet:3701A083926D4F6C4790468CAEF5B513A42B5FA48396D1659B8DCD6E531125AE"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 0,
                            "meta": {
                                "sender_balance": "27999952",
                                "sender_previous_balance": "27999964"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775",
                            "transfer_id": "ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "1000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "35686217",
                                "receiver_previous_balance": "34686217",
                                "sender_balance": "26999952",
                                "sender_previous_balance": "27999952",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "transaction_id": "ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775",
                            "transfer_id": "ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:411431BBF23DEF375E2D1CD7EEC2A5BD9C32CB63ACB7BE110C41B4C7DBCDCEBB"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "411431BBF23DEF375E2D1CD7EEC2A5BD9C32CB63ACB7BE110C41B4C7DBCDCEBB",
                "block_height": 48738649,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1814592,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-18T14:43:10.000+0000",
                "hash": "9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775",
                "identifier": "9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775",
                "index": 13,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAABGFAAAAAAA9CQGhAAAAAAAAADHMhAjsy4/swbmNnxBZW7YNOKZWzaQCMzm9+XGf7gj/yZDWCdEcwRQIhAJ8Jz84mTq1baEhmXMxWX83SE/bVuFiB0r6O+THe0bHuAiAm0XwsMsPi6hguENfGYpI4Q9jouqClqnsIEB5LiP8pDoEUOmZ1YWfuDLP+8Kt+WcSsi1bjBlyDFBPwUVf6k9wOpxn8d2RMHjYEeIHg",
                "size": 183,
                "status": "CONFIRMED",
                "timestamp": "2019-07-18T14:43:10.000+0000",
                "transaction_id": "ripple-testnet:9C2C2FF0D9BA71937FC8271477E09FC33AC8C8D435D228F5D429EC903F3A4775"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 0,
                            "meta": {
                                "sender_balance": "35686205",
                                "sender_previous_balance": "35686217"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F",
                            "transfer_id": "ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "1000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "27999952",
                                "receiver_previous_balance": "26999952",
                                "sender_balance": "34686205",
                                "sender_previous_balance": "35686205",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "transaction_id": "ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F",
                            "transfer_id": "ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:C9A92D393695E0CE2A7940282E26265E3D0C8B7793E7CDACA3799699A56E5AD1"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "C9A92D393695E0CE2A7940282E26265E3D0C8B7793E7CDACA3799699A56E5AD1",
                "block_height": 48738656,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1814585,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-18T14:43:32.000+0000",
                "hash": "B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F",
                "identifier": "B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F",
                "index": 42,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAABGFAAAAAAA9CQGhAAAAAAAAADHMhA3hFAZZqqFLTNCX2xvdvqySlU2wphW1x6nF/rRTrC+gfdEYwRAIgb9qaDoePfZnyfLtBvRJuxtIr+8deAvlp56aAvvjbE8kCIFLMG9fwGMaq2kBvzNlMkKnlxZjc87DFIf4fFJ7cWK/OgRQT8FFX+pPcDqcZ/HdkTB42BHiB4IMUOmZ1YWfuDLP+8Kt+WcSsi1bjBlw=",
                "size": 182,
                "status": "CONFIRMED",
                "timestamp": "2019-07-18T14:43:32.000+0000",
                "transaction_id": "ripple-testnet:B97406484F8C4D2ECBCD90E8C6B43F07F35DD58EE6F570832A865E44561D1C3F"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 0,
                            "meta": {
                                "sender_balance": "27999940",
                                "sender_previous_balance": "27999952"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730",
                            "transfer_id": "ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "1000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "35686205",
                                "receiver_previous_balance": "34686205",
                                "sender_balance": "26999940",
                                "sender_previous_balance": "27999940",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "transaction_id": "ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730",
                            "transfer_id": "ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:FCABA67FA66B32246207A827B0D626E2B430C3D0520949A3EBF12E4079304691"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "FCABA67FA66B32246207A827B0D626E2B430C3D0520949A3EBF12E4079304691",
                "block_height": 48738664,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1814577,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-18T14:44:10.000+0000",
                "hash": "65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730",
                "identifier": "65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730",
                "index": 27,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAABWFAAAAAAA9CQGhAAAAAAAAADHMhAjsy4/swbmNnxBZW7YNOKZWzaQCMzm9+XGf7gj/yZDWCdEYwRAIgRgfH6rf25HqK9eOkuQm9PCan7VmxIIBSPz0nlp6vBKECIGfvEay3eInhlDMMlSXVMMElQDv3cuHyd01L/kl/SmcigRQ6ZnVhZ+4Ms/7wq35ZxKyLVuMGXIMUE/BRV/qT3A6nGfx3ZEweNgR4geA=",
                "size": 182,
                "status": "CONFIRMED",
                "timestamp": "2019-07-18T14:44:10.000+0000",
                "transaction_id": "ripple-testnet:65D8206D8AC8482CB6D81DB4B4D6F9A47C939174880E92067AF1140C9CBCA730"
            },
            {
                "_embedded": {
                    "transfers": [
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE:0"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "12",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 0,
                            "meta": {
                                "sender_balance": "35686193",
                                "sender_previous_balance": "35686205"
                            },
                            "to_address": "__fee__",
                            "transaction_id": "ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE",
                            "transfer_id": "ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE:0"
                        },
                        {
                            "_links": {
                                "self": {
                                    "href": "http://localhost:8080/transfers/ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE:1"
                                },
                                "transaction": {
                                    "href": "http://localhost:8080/transactions/ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE"
                                }
                            },
                            "acknowledgements": null,
                            "amount": {
                                "amount": "1000000",
                                "currency_id": "ripple-testnet:__native__"
                            },
                            "blockchain_id": "ripple-testnet",
                            "from_address": "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
                            "index": 1,
                            "meta": {
                                "receiver_balance": "27999940",
                                "receiver_previous_balance": "26999940",
                                "sender_balance": "34686193",
                                "sender_previous_balance": "35686193",
                                "txresult": "tesSUCCESS"
                            },
                            "to_address": "raK8AhzLG3HdWqtVogLGieydYWzbXY5xdF",
                            "transaction_id": "ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE",
                            "transfer_id": "ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE:1"
                        }
                    ]
                },
                "_links": {
                    "block": {
                        "href": "http://localhost:8080/blocks/ripple-testnet:958A37E75245F5E4607B01E9514844D40D14C0C1C4AA097D108C58517133E362"
                    },
                    "self": {
                        "href": "http://localhost:8080/transactions/ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE"
                    }
                },
                "acknowledgements": 1,
                "block_hash": "958A37E75245F5E4607B01E9514844D40D14C0C1C4AA097D108C58517133E362",
                "block_height": 48738670,
                "blockchain_id": "ripple-testnet",
                "confirmations": 1814571,
                "fee": {
                    "amount": "12",
                    "currency_id": "ripple-testnet:__native__"
                },
                "first_seen": "2019-07-18T14:44:31.000+0000",
                "hash": "B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE",
                "identifier": "B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE",
                "index": 18,
                "proof": null,
                "raw": "EgAAIoAAAAAkAAAABWFAAAAAAA9CQGhAAAAAAAAADHMhA3hFAZZqqFLTNCX2xvdvqySlU2wphW1x6nF/rRTrC+gfdEYwRAIgE7RNoU9oRkiZcSF+XeNGzRTnQw+hi4pysvKhrghfTPwCICAGVkR/7rsbOE8CwQbKELReEgtT3cGubvfdLLmQEzGogRQT8FFX+pPcDqcZ/HdkTB42BHiB4IMUOmZ1YWfuDLP+8Kt+WcSsi1bjBlw=",
                "size": 182,
                "status": "CONFIRMED",
                "timestamp": "2019-07-18T14:44:31.000+0000",
                "transaction_id": "ripple-testnet:B2EBE9C3DDAD48BD3DABD3276AA79E1C0B1E94A7B26843BB54E23D15BDAFF7BE"
            }
        ]
    },
    "_links": {
        "self": {
            "href": "http://localhost:8080/transactions?blockchain_id=ripple-testnet&start_height=0&end_height=50000000&include_proof=false&include_raw=true&address=rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE"
        }
    }
}
""".data(using: String.Encoding.utf8)!

    private static let xrpStubbedTransactionOne: BlockChainDB.Model.Transaction = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

        return (id: "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
         blockchainId: "ripple-testnet",
         hash: "21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
         identifier: "21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
         blockHash: "BAF970FCFE59BCBF3C5725B707B5F62FB655DA0591078CE5A7392F5D6E4C5F9A",
         blockHeight: 48719657,
         index: 24,
         confirmations: 1833584,
         status: "CONFIRMED",
         size: 194,
         timestamp: formatter.date (from: "2019-07-17T18:13:50.000+0000"),
         firstSeen: formatter.date (from: "2019-07-17T18:13:50.000+0000"),
         raw: Data (base64Encoded:"EgAAIoAAAAAkAAAAAS4AAeJAIBsC52c7YUAAAAAB3wH2aEAAAAAAAAAMcyECI3hnmlFvOFWBfd4BKH5rcf8x4uTMj7GI+ivq+K6/puB0RzBFAiEAuPdjiDK4gUhAdiBGV68ZtJb1duKtwZ7muhQXmjfaT9wCIEkbpstJX7FElHQvs4mJWRnvF6Qe7miw0mVMAz6DEhK8gRRTF8SmU6dMT9Nq6abIFsuLil12K4MUE/BRV/qT3A6nGfx3ZEweNgR4geA"),

         transfers: [
            (id: "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778:0",
             source: "r32MZ4sbsLHmbssegmNShrrm16Jwo9SAd1",
             target: "__fee__",
             amountValue: "12",
             amountCurrency: "ripple-testnet:__native__",
             acknowledgements: 0,
             index: 0,
             transactionId: "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
             blockchainId: "ripple-testnet"),

            (id: "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778:1",
             source: "r32MZ4sbsLHmbssegmNShrrm16Jwo9SAd1",
             target: "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
             amountValue: "31392246",
             amountCurrency: "ripple-testnet:__native__",
             acknowledgements: 0,
             index: 1,
             transactionId: "ripple-testnet:21BF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
             blockchainId: "ripple-testnet")

            ],
         acknowledgements: 1)
    }()

    private static let xrpStubbedTransactionTwo: BlockChainDB.Model.Transaction = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

        return (id: "ripple-testnet:FFBF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
         blockchainId: "ripple-testnet",
         hash: "FFBF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
         identifier: "FFBF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
         blockHash: "FFF970FCFE59BCBF3C5725B707B5F62FB655DA0591078CE5A7392F5D6E4C5F9A",
         blockHeight: 48719658,
         index: 25,
         confirmations: 1833583,
         status: "CONFIRMED",
         size: 194,
         timestamp: formatter.date (from: "2019-07-17T18:13:55.000+0000"),
         firstSeen: formatter.date (from: "2019-07-17T18:13:55.000+0000"),
         raw: Data (base64Encoded:"EgAAIoAAAAAkAAAAAS4AAeJAIBsC52c7YUAAAAAB3wH2aEAAAAAAAAAMcyECI3hnmlFvOFWBfd4BKH5rcf8x4uTMj7GI+ivq+K6/puB0RzBFAiEAuPdjiDK4gUhAdiBGV68ZtJb1duKtwZ7muhQXmjfaT9wCIEkbpstJX7FElHQvs4mJWRnvF6Qe7miw0mVMAz6DEhK8gRRTF8SmU6dMT9Nq6abIFsuLil12K4MUE/BRV/qT3A6nGfx3ZEweNgR4geA"),

         transfers: [
            (id: "ripple-testnet:FFBF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778:0",
             source: "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
             target: "__fee__",
             amountValue: "12",
             amountCurrency: "ripple-testnet:__native__",
             acknowledgements: 0,
             index: 0,
             transactionId: "ripple-testnet:FFBF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
             blockchainId: "ripple-testnet"),

            (id: "ripple-testnet:FFBF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778:1",
             source: "rpFRjDTUmUdVgMjwurx3osy4rNmXsoz7FE",
             target: "r32MZ4sbsLHmbssegmNShrrm16Jwo9SAd1",
             amountValue: "21392246",
             amountCurrency: "ripple-testnet:__native__",
             acknowledgements: 0,
             index: 1,
             transactionId: "ripple-testnet:FFBF49117E1649EC0C64594CA4A911030539CFF4E333795F5FD16132744F8778",
             blockchainId: "ripple-testnet")

            ],
         acknowledgements: 1)
    }()

    static let xrpStubbedTransactions = [xrpStubbedTransactionOne,
                                         xrpStubbedTransactionTwo]
}
