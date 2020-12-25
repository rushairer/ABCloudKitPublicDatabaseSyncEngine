import Foundation
import CloudKit
import CoreData

public final class ABCloudKitPublicDatabaseSyncEngine {
    
    public var startCompletionBlock: (() -> Void)?
    public var fetchRecordsCompletionBlock: (([CKRecord]?) -> Void)?
    public var createRecordCompletionBlock: ((CKRecord?) -> Void)?
    public var updateRecordCompletionBlock: ((CKRecord?) -> Void)?
    public var deleteRecordCompletionBlock: ((CKRecord.ID?) -> Void)?
    public lazy var subscription: CKQuerySubscription = {
        let predicate = NSPredicate(format: "TRUEPREDICATE")
        let subscription = CKQuerySubscription(recordType: self.recordType,
                                               predicate: predicate,
                                               subscriptionID: self.publicSubscriptionKey,
                                               options: [CKQuerySubscription.Options.firesOnRecordUpdate, .firesOnRecordCreation, .firesOnRecordDeletion])
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.desiredKeys = [
            "CD_id",
        ]
        subscription.notificationInfo = notificationInfo
        
        return subscription
    }()
    
    private let defaults: UserDefaults
    
    private let zoneID: CKRecordZone.ID
    
    private var recordType: CKRecord.RecordType
    
    private(set) lazy var container: CKContainer = {
        CKContainer.default()
    }()
    
    private(set) lazy var publicDatabase: CKDatabase = {
        self.container.publicCloudDatabase
    }()
    
    private(set) lazy var publicSubscriptionKey: String = {
        return"\(self.container.containerIdentifier!.description).\(self.recordType).subscription.public"
    }()
    
    private(set) lazy var publicSubscriptionIDKey: String = {
        return"\(self.container.containerIdentifier!.description).\(self.recordType).subscription.public.id"
    }()
    
    private(set) lazy var latestModificationDateKey: String = {
        return"\(self.container.containerIdentifier!.description).\(self.recordType).record.latestmodificationdate"
    }()
    
    private(set) lazy var loaclQueue: DispatchQueue = {
        return DispatchQueue(label: "\(self.container.containerIdentifier!.description).\(self.recordType).queue.local", qos: .userInitiated)
    }()
    
    private(set) lazy var cloudQueue: DispatchQueue = {
        return DispatchQueue(label: "\(self.container.containerIdentifier!.description).\(self.recordType).queue.cloud", qos: .userInitiated)
    }()
    
    private(set) lazy var cloudOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.underlyingQueue = self.cloudQueue
        queue.name = "\(self.container.containerIdentifier!.description).\(self.recordType).operationqueue.cloud"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    private var createdPublicSubscription: Bool {
        get {
            return self.defaults.bool(forKey: self.publicSubscriptionKey)
        }
        set {
            self.defaults.set(newValue, forKey: self.publicSubscriptionKey)
        }
    }
    
    private var createdPublicSubscriptionID: String {
        get {
            return self.defaults.string(forKey: self.publicSubscriptionIDKey)!
        }
        set {
            self.defaults.setValue(newValue, forKey: self.publicSubscriptionIDKey)
        }
    }
    
    fileprivate var latestModificationDate: Date {
        get {
            return (self.defaults.object(forKey: self.latestModificationDateKey) ?? Date(timeIntervalSince1970: 0))as! Date
        }
        set {
            self.defaults.set(newValue, forKey: self.latestModificationDateKey)
        }
    }
    
    public init(defaults: UserDefaults, zoneID: CKRecordZone.ID, recordType: String) {
        self.defaults = defaults
        self.zoneID = zoneID
        self.recordType = recordType
    }
    
    public func start() {
        self.prepareCloudEnvironment { [weak self] in
            if self!.startCompletionBlock != nil {
                self!.startCompletionBlock!()
            }
        }
    }
    
    public func updateLatestModificationDate(date: Date) {
        self.latestModificationDate = date
    }
    
    private func prepareCloudEnvironment(then block: @escaping () -> Void) {
        self.loaclQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.createPublicSubscriptionsIfNeeded()
            self.cloudOperationQueue.waitUntilAllOperationsAreFinished()
            
            DispatchQueue.main.async { block() }
        }
    }
    
    private func createPublicSubscriptionsIfNeeded() {
        guard !self.createdPublicSubscription else {
            print("Already subscribed to public database changes, skipping subscription but checking if it really exists")
            self.checkSubscription()
            return
        }
        
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [self.subscription],
                                                       subscriptionIDsToDelete: nil)
        
        operation.database = self.publicDatabase
        operation.qualityOfService = .userInitiated
        
        operation.modifySubscriptionsCompletionBlock = { [weak self] subscriptions, subscriptionIDs, error in
            guard let self = self else { return }
            
            if error != nil {
                print("Failed to create public CloudKit subscription: \(error!)")
                error!.retryCloudKitOperationIfPossible {
                    self.createPublicSubscriptionsIfNeeded()
                }
            } else if (subscriptions != nil) {
                self.createdPublicSubscription = true
                self.createdPublicSubscriptionID = subscriptions!.first!.subscriptionID
            }
        }
        
        self.cloudOperationQueue.addOperation(operation)
    }
    
    private func checkSubscription() {
        let operation = CKFetchSubscriptionsOperation(subscriptionIDs: [self.publicSubscriptionKey])
        
        operation.fetchSubscriptionCompletionBlock = { [weak self] ids, error in
            guard let self = self else { return }
            if error != nil {
                print("Failed to check for public zone subscription existence: \(error!)")
                
                if !error!.retryCloudKitOperationIfPossible(with: { self.checkSubscription() }) {
                    print("Irrecoverable error when fetching public zone subscription, assuming it doesn't exist: \(error!)")
                    
                    DispatchQueue.main.async {
                        self.createdPublicSubscription = false
                        self.createPublicSubscriptionsIfNeeded()
                    }
                }
            } else if ids == nil || ids?.count == 0 {
                print("Public subscription reported as existing, but it doesn't exist. Creating.")
                DispatchQueue.main.async {
                    self.createdPublicSubscription = false
                    self.createPublicSubscriptionsIfNeeded()
                }
            } else if (ids?.first?.value as! CKQuerySubscription).recordType != self.recordType {
                //如果更新了recordType，删除对旧recordType的订阅
                self.removeSubscriptionIfNeeded()
                DispatchQueue.main.async {
                    self.createdPublicSubscription = false
                    self.createPublicSubscriptionsIfNeeded()
                }
            } else {
                self.createdPublicSubscription = true
            }
        }
        
        operation.qualityOfService = .userInitiated
        operation.database = self.publicDatabase
        
        self.cloudOperationQueue.addOperation(operation)
    }
    
    private func removeSubscriptionIfNeeded() {
        guard self.createdPublicSubscription && self.createdPublicSubscriptionID.count > 0 else { return }
        
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [self.createdPublicSubscriptionID])
        operation.database = self.container.publicCloudDatabase
        operation.qualityOfService = .userInitiated
        
        operation.modifySubscriptionsCompletionBlock = { [weak self] _, _, error in
            guard let self = self else { return }
            
            if error != nil {
                print("Failed to create public CloudKit subscription: \(error!)")
                error!.retryCloudKitOperationIfPossible {
                    self.removeSubscriptionIfNeeded()
                }
            } else {
                self.createdPublicSubscription = false
                self.createdPublicSubscriptionID = ""
            }
        }
        
        self.cloudOperationQueue.addOperation(operation)
    }
    
    private func queryCompletionBlock(forInitialOperation initialOperation: CKQueryOperation,
                                      completion: @escaping (Error?) -> Void) -> ((CKQueryOperation.Cursor?, Error?) -> Void) {
        return { cursor, error in
            if error != nil {
                completion(error)
            } else if cursor != nil {
                let newOperation = CKQueryOperation(cursor: cursor!)
                newOperation.database = self.container.publicCloudDatabase
                newOperation.qualityOfService = .userInitiated
                newOperation.resultsLimit = initialOperation.resultsLimit
                newOperation.recordFetchedBlock = initialOperation.recordFetchedBlock
                newOperation.queryCompletionBlock = self.queryCompletionBlock(forInitialOperation: newOperation, completion: completion)
                self.cloudOperationQueue.addOperation(newOperation)
            } else {
                completion(nil)
            }
        }
    }
    
    public func fetchRecentRecords() {
        let predicate = NSPredicate(format: "modificationDate > %@", self.latestModificationDate as CVarArg)
        let query = CKQuery(recordType: self.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        
        var result: [CKRecord] = []
        
        let operation = CKQueryOperation(query: query)
        operation.database = self.container.publicCloudDatabase
        operation.qualityOfService = .userInitiated
        operation.resultsLimit = CKQueryOperation.maximumResults
        
        operation.recordFetchedBlock = { record in
            result.append(record)
        }
        
        operation.queryCompletionBlock = self.queryCompletionBlock(forInitialOperation: operation) { [weak self] error in
            if error != nil {
                print(error!)
            } else if self!.fetchRecordsCompletionBlock != nil {
                DispatchQueue.main.async {
                    self!.fetchRecordsCompletionBlock!(result)
                }
            }
        }
        
        self.cloudOperationQueue.addOperation(operation)
    }
    
    public func fetchRecord(with recordID: CKRecord.ID, recordFetchedBlock: @escaping (CKRecord) -> Void) {
        let predicate = NSPredicate(format: "recordID == %@", recordID as CVarArg)
        let query = CKQuery(recordType: self.recordType, predicate: predicate)
        
        let operation = CKQueryOperation(query: query)
        operation.database = self.container.publicCloudDatabase
        operation.qualityOfService = .userInitiated
        operation.resultsLimit = 1
        operation.recordFetchedBlock = recordFetchedBlock
        self.cloudOperationQueue.addOperation(operation)
    }
}

public extension ABCloudKitPublicDatabaseSyncEngine {
    @discardableResult
    func processSubscriptionNotification(with userInfo: [AnyHashable : Any]) -> Bool {
        
        guard let notification = CKQueryNotification(fromRemoteNotificationDictionary: userInfo) else { return false }
        guard notification.subscriptionID == self.publicSubscriptionKey else { return false }
        
        switch notification.queryNotificationReason {
        case .recordCreated:
            if self.createRecordCompletionBlock != nil {
                self.fetchRecord(with: notification.recordID!) { [weak self] record in
                    self!.createRecordCompletionBlock!(record)
                    self!.updateLatestModificationDate(date: record.modificationDate!)
                    
                }
            }
        case .recordDeleted:
            if self.deleteRecordCompletionBlock != nil {
                self.deleteRecordCompletionBlock!(notification.recordID!)
            }
        case .recordUpdated:
            if self.updateRecordCompletionBlock != nil {
                self.fetchRecord(with: notification.recordID!) { [weak self] record in
                    self!.updateRecordCompletionBlock!(record)
                    self!.updateLatestModificationDate(date: record.modificationDate!)
                }
            }
        @unknown default:
            fatalError()
        }
        return true
    }
}

public extension Error {
    @discardableResult
    func retryCloudKitOperationIfPossible(with block: @escaping () -> Void) -> Bool {
        guard let effectiveError = self as? CKError else { return false }
        guard let retryDelay: Double = effectiveError.retryAfterSeconds else {
            print("Error is not recoverable")
            return false
        }
        print("Error is recoverable. Will retry after \(retryDelay) seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
            block()
        }
        return true
    }
}
