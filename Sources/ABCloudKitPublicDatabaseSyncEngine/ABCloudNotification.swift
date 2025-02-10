import Foundation
import CloudKit
import UserNotifications

final public class ABCloudNotification {
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
    public init() {
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

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
    @available(watchOS, unavailable)
    public func resetBadgeCounter() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("Failed to reset badge counter: \(error)")
            }
        }
    }
}
