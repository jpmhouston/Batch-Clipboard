//
//  AppStorePurchases.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-10.
//  Copyright © 2024 Bananameter Labs. All rights reserved.
//

import AppKit
import StoreKit
import Flare
import TPInAppReceipt
import os.log

class AppStorePurchases: NSObject {
  // observer scheme described in https://www.swiftbysundell.com/articles/observers-in-swift-part-2/
  class ObservationToken {
    private let cancellationClosure: () -> Void
    init(cancellationClosure: @escaping () -> Void) {
      self.cancellationClosure = cancellationClosure
    }
    func cancel() {
      cancellationClosure()
    }
  }
  
  enum Item {
    case bonus
    case corporateSubscription
  }
  
  enum SubscriptionOption {
    case not
    case monthly
    case yearly
  }
  
  protocol ProductDetail {
    var identifier: String { get }
    var item: Item { get }
    var localizedTitle: String { get }
    var localizedPrice: String { get }
    var subscription: SubscriptionOption { get }
  }

  struct DummyProductDetail: ProductDetail {
    let identifier: String
    let item: Item
    let localizedTitle: String
    let localizedPrice: String
    let subscription: SubscriptionOption
  }
  
  struct FlareProductDetail: ProductDetail {
    var product: StoreProduct
    var item: Item { itemValueForProductIdentifier(product.productIdentifier) }
    var identifier: String { product.productIdentifier }
    var localizedTitle: String { product.localizedTitle }
    var localizedPrice: String { product.localizedPriceString ?? "" }
    var subscription: SubscriptionOption {
      switch product.subscriptionPeriod?.unit {
        case .year: .yearly
        case .month: .monthly
        default: .not
      }
    }
    init(_ p: StoreProduct) { self.product = p } // unlike autogenerated init, omits the `product:` label
  }
  
  enum UpdateItem {
    case purchases(Set<Item>)
    case restorations(Set<Item>)
    case products([ProductDetail])
  }
  
  enum PurchaseError: Error, CaseIterable {
    case prohibited
    case malformedReceipt, invalidReceipt
    case unreachable, unknown
    case malformedProducts
    case cancelled
    //case unrecognized, unavailable, noneToRestore
    //case declined
  }
  
  typealias ObservationUpdate = Result<UpdateItem, PurchaseError>
  typealias ProductResult = Result<[ProductDetail], PurchaseError>
  typealias ReceiptResult = Result<Set<Item>, PurchaseError>
  typealias PurchaseResult = Result<Set<Item>, PurchaseError>
  
  private var observations: [UUID: (ObservationUpdate) -> Void] = [:]
  
  private static let basicProductIdentifier = "lol.bananameter.batchclip.basicsupport"
  private static let corporateProductIdentifier = "lol.bananameter.batchclip.subcription.corporate1"
  private lazy var knownProductIdentifiers = [Self.basicProductIdentifier, Self.corporateProductIdentifier]
  
  var hasBoughtExtras: Bool { !boughtItems.isEmpty }
  var boughtItems: Set<Item> = []
  var lastError: PurchaseError? // possibly not needed
  
  // MARK: -
  
  @discardableResult
  func start<T: AnyObject>(withObserver observer: T, callback: @escaping (T, ObservationUpdate) -> Void) -> ObservationToken {
    let token = addObserver(observer, callback: callback)
    start()
    return token
  }
  
  func start() {
    setupStoreKit()
    
    #if !IGNORE_RECEIPT_ON_LAUNCH
    switch checkLocalReceipt() {
    case .success(let items):
      callObservers(withUpdate: .success(.purchases(items)))
    case .failure(let err):
      callObservers(withUpdate: .failure(err))
    }
    #endif
  }
  
  func finish(andRemoveObserver token: ObservationToken? = nil) {
    if let token = token {
      token.cancel()
    }
    teardownStoreKit()
  }
  
  @discardableResult
  func addObserver<T: AnyObject>(_ observer: T, callback: @escaping (T, ObservationUpdate) -> Void) -> ObservationToken {
    let id = UUID()
    observations[id] = { [weak self, weak observer] update in
      guard let observer = observer else {
        self?.observations.removeValue(forKey: id)
        return
      }
      callback(observer, update)
    }
    return ObservationToken { [weak self] in
      self?.observations.removeValue(forKey: id)
    }
  }
  
  func removeObserver(_ token: ObservationToken) {
    token.cancel()
  }
  
  static func itemValueForProductIdentifier(_ productIdentifier: String) -> Item {
    switch productIdentifier {
    case corporateProductIdentifier: Item.corporateSubscription
    default: Item.bonus
    }
  }
  
  // MARK: -
  
  func startFetchingProductDetails() throws {
    guard SKPaymentQueue.canMakePayments() else {
      throw PurchaseError.prohibited
    }
    
    fetchProducts(withIDs: knownProductIdentifiers) { [weak self] productsResult in
      guard let self = self else { return }
      
      switch productsResult {
      case .success(let products):
        callObservers(withUpdate: .success(.products(products)))
      case .failure(let error):
        callObservers(withUpdate: .failure(error))
      }
    }
  }
  
  func startFetchingDummyProductDetails() throws {
    #if DEBUG
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self = self else { return }
      let productList = [
        DummyProductDetail(identifier: Self.basicProductIdentifier, item: .bonus, localizedTitle: "Support us and unlock bonus features", localizedPrice: "$3.99", subscription: .not),
        DummyProductDetail(identifier: Self.corporateProductIdentifier, item: .corporateSubscription, localizedTitle: "Corporate yearly subscription", localizedPrice: "$9.99", subscription: .yearly)
      ]
      callObservers(withUpdate: .success(.products(productList)))
    }
    #else
    throw PurchaseError.unknown
    #endif
  }
  
  func startPurchase(_ product: ProductDetail) throws {
    guard SKPaymentQueue.canMakePayments() else {
      throw PurchaseError.prohibited
    }
    
    if product is DummyProductDetail {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        guard let self = self else { return }
        boughtItems.insert(product.item)
        callObservers(withUpdate: .success(.purchases(boughtItems)))
      }
      return
    }
    
    guard let productDetail = product as? FlareProductDetail else {
      throw PurchaseError.unreachable
    }
    
    purchase(productDetail) { [weak self] purchaseResult in
      guard let self = self else { return }
      
      switch purchaseResult {
      case .success(let items):
        boughtItems.formUnion(items)
        callObservers(withUpdate: .success(.purchases(items)))
      case .failure(let error):
        callObservers(withUpdate: .failure(error))
      }
    }
  }
  
  func startRestore() throws {
    guard SKPaymentQueue.canMakePayments() else {
      throw PurchaseError.prohibited
    }
    
    // previously called refreshReceipt() first here, but now the helper/wrapper
    // method restorePurchases() is expected to transparently refresh the receipt first
    
    restorePurchases() { [weak self] restoreResult in
      guard let self = self else { return }
      
      switch restoreResult {
      case .success(let items):
        boughtItems.formUnion(items)
        callObservers(withUpdate: .success(.restorations(items)))
      case .failure(let error):
        callObservers(withUpdate: .failure(error))
      }
    }
  }
  
  func callObservers(withUpdate update: ObservationUpdate) {
    observations.values.forEach { closure in
      closure(update)
    }
  }
  
  // MARK: - wrappers for StoreKit helper framework
  
  func setupStoreKit() {
    Flare.shared.addTransactionObserver { [weak self] transactionResult in
      self?.completeTransactionsCallback(withResult: transactionResult)
    }
  }
  
  func teardownStoreKit() {
  }
  
  @discardableResult
  private func checkLocalReceipt() -> ReceiptResult {
    boughtItems = []
    let result = Self.validateReceipt(nil) // nil parameter lets InAppReceipt grab the local receipt
    if case .success(let items) = result {
      boughtItems = items
    }
    return result
  }
  
  class func validateReceipt(_ receiptData: Data? = nil) -> ReceiptResult {
    let errorValue: PurchaseError
    do {
      let receipt: InAppReceipt
      if let receiptData = receiptData {
        receipt = try InAppReceipt(receiptData: receiptData)
      } else {
        receipt = try InAppReceipt()
      }
      try receipt.validate()
      
      let restoredItems = receipt.purchases.map { itemValueForProductIdentifier($0.productIdentifier) }
      return .success(Set(restoredItems))
      
    } catch IARError.initializationFailed(let reason) {
      // catch let error as IARError.initializationFailed(reason) .. can swift let us do this?
      if reason == .appStoreReceiptNotFound {
        return .success([]) // short-circuit to return success after all
        
      } else {
        os_log(.default, "failure validating receipt: validator itself")
        errorValue = .malformedReceipt
      }
      
    } catch IARError.validationFailed {
      // wanted something like: `catch let error as IARError.validationFailed(reason)`
      os_log(.default, "failure validating receipt: did not validate")
      errorValue = .invalidReceipt
      
    } catch {
      os_log(.default, "error during local receipt validation: %@", error.localizedDescription)
      errorValue = .unknown
    }
    
    return .failure(errorValue)
  }
  
  func refreshReceipt(_ completion: @escaping (ReceiptResult)->Void) {
    Flare.shared.receipt(updateTransactions: false) { fetchResult in
      switch fetchResult {
      case .success(let receipt64String):
        if let receipt = Data(base64Encoded: receipt64String) {
          let validationResult = Self.validateReceipt(receipt)
          
          completion(validationResult)
          
        } else {
          completion(.failure(.malformedReceipt))
        }
        
      case .failure(.receiptNotFound):
        completion(.success([]))
        
      case .failure(.with(let underlyingError)):
        os_log(.default, "error during receipt refresh: %@", underlyingError.localizedDescription)
        completion(.failure(.unreachable))
      case .failure(let error):
        os_log(.default, "error during receipt refresh: %@", error.localizedDescription)
        completion(.failure(.unknown))
      }
    }
  }
  
  func restorePurchases(_ completion: @escaping (ReceiptResult)->Void) {
    // currently nearly identical to refreshReceipt
    Flare.shared.receipt(updateTransactions: true) { restoreResult in
      switch restoreResult {
      case .success(let receipt64String):
        if let receipt = Data(base64Encoded: receipt64String) {
          let validationResult = Self.validateReceipt(receipt)
          
          completion(validationResult)
          
        } else {
          completion(.failure(.malformedReceipt))
        }
        
      case .failure(.receiptNotFound):
        completion(.success([]))
        
      case .failure(.with(let underlyingError)):
        os_log(.default, "error during restore: %@", underlyingError.localizedDescription)
        completion(.failure(.unreachable))
      case .failure(let error):
        os_log(.default, "error during restore: %@", error.localizedDescription)
        completion(.failure(.unknown))
      }
    }
  }
  
  private func fetchProducts(withIDs ids: [String], _ completion: @escaping (ProductResult)->Void) {
    Flare.shared.fetch(productIDs: ids) { fetchResult in
      switch fetchResult {
      case .success(let storeProducts):
        if let productMissingPrice = storeProducts.first(where: { $0.localizedPriceString == nil }) {
          os_log(.default, "product missing its price during product fetch: %@", productMissingPrice.productIdentifier)
          completion(.failure(.malformedProducts))
        }
        let productDetails: [FlareProductDetail] = storeProducts.map { FlareProductDetail($0) }
        completion(.success(productDetails))
      case .failure(let error):
        os_log(.default, "error during product fetch: %@", error.localizedDescription)
        completion(.failure(.unknown))
      }
    }
  }
  
  private func purchase(_ productDetail: FlareProductDetail, _ completion: @escaping (PurchaseResult)->Void) {
    Flare.shared.purchase(product: productDetail.product) { flarePurchaseResult in
      switch flarePurchaseResult {
      case .success(_):
        completion(.success(([productDetail.item])))
      case .failure(let error):
        os_log(.default, "error during purchase: %@", error.localizedDescription)
        switch error {
        case .paymentCancelled:
          completion(.failure(.cancelled))
        default:
          completion(.failure(.unknown))
        }
      }
    }
  }
  
  private func completeTransactionsCallback(withResult transactionResult: Result<StoreTransaction, IAPError>) {
    switch transactionResult {
    case .success(_): // .success(let transaction):
      //print("A transaction was received: \(transaction)")
      break
      // I don't think purchase or restore relies on this callback, although I think we could
      // in theory we could take out the existing data flow through completions and use this.
      // Keeping below the original version of this callback from attempt to use SwiftyStoreKit
      // for an idea of what could be done here.
      
    case .failure(.paymentCancelled):
      //print("A transaction cancellation was received")
      callObservers(withUpdate: .failure(.cancelled))
    case .failure(let error):
      os_log(.default, "transaction failure received: %@", error.localizedDescription)
      callObservers(withUpdate: .failure(.unknown))
    }
  }
  
}
