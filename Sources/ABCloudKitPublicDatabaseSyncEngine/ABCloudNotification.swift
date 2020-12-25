import Foundation
import CloudKit

final public class CloudNotification {
    static private(set) var langKey: String = {
        let currentLang = NSLocalizedString("current_lang", comment: "")
        var langKey = ""
        if currentLang != "current_lang" {
            langKey = "_\(currentLang)"
        }
        return langKey
    }()
    static let cloudNotification = "CloudNotification\(langKey)"
    
    var container: CKContainer
    var defaults: UserDefaults
    var syncEngine: ABCloudKitPublicDatabaseSyncEngine?
    
    @discardableResult
    init() {
        let zoneID = CKRecordZone.default().zoneID
        self.container =  CKContainer.default()
        self.defaults = UserDefaults.standard
        
        self.syncEngine = ABCloudKitPublicDatabaseSyncEngine(defaults: self.defaults,
                                                           zoneID: zoneID,
                                                           recordType: Self.cloudNotification)
        
        let predicate = NSPredicate(format: "TRUEPREDICATE")
        let subscription = CKQuerySubscription(recordType: Self.cloudNotification,
                                               predicate: predicate,
                                               subscriptionID: self.syncEngine!.publicSubscriptionKey,
                                               options: [.firesOnRecordCreation])
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        
        notificationInfo.titleLocalizationKey = "%1$@"
        notificationInfo.titleLocalizationArgs = ["title"]
        notificationInfo.alertLocalizationKey = "%1$@"
        notificationInfo.alertLocalizationArgs = ["content"]
        notificationInfo.soundName = "default"
        notificationInfo.shouldBadge = true

        notificationInfo.desiredKeys = [
            "info",
        ]
        
        subscription.notificationInfo = notificationInfo

        self.syncEngine?.subscription = subscription
        
        self.syncEngine?.start()
    }
    
    public func resetBadgeCounter() {
        let operation = CKModifyBadgeOperation(badgeValue: 0)
        operation.modifyBadgeCompletionBlock = { (error) -> Void in
        }
        operation.qualityOfService = .userInitiated
        
        self.container.add(operation)
    }
}
