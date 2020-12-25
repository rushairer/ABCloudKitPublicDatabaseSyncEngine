# ABCloudKitPublicDatabaseSyncEngine

## Usage 

### Public Database SyncEngine
#### 1. Login CloudKit Dashboard, Create "New Type".

* The "Custom Fields" must with prefix "CD_", like: CD_name, CD_preview
* Must have "CD_id"(String), "CD_timestamp"(Date/Time) fields
* Custom Fields must have "Queryable,Sortable or Searchable" indexs
* Create "Queryable,Sortable" indexes to "modifiedAt" field
* Create "Sortable" index to "createAt" field
* Create "Queryable" index to "recordName" field

#### 2. Create ".xcdatamodeld" in XCode.

* Have the same fields like the Type on CloudKit Dashboard, but remove prefix "CD_", like: name, preview

#### 3 Create "PersistenceController" file

``` swift
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    var records: [ABCloudKitPublicDatabaseAutoSyncRecord] = []

    init() {
//        if #available(iOS 14.0, *) {
//            self.container = NSPersistentCloudKitContainer(name: "Metronome")
//        } else {
//            self.container = NSPersistentContainer(name: "Metronome")
//        }
        self.container = NSPersistentContainer(name: "Metronome")


        guard let persistentStoreDescriptions = self.container.persistentStoreDescriptions.first else {
            fatalError("\(#function): Failed to retrieve a persistent store description.")
        }
        persistentStoreDescriptions.setOption(true as NSNumber,
                                              forKey: NSPersistentHistoryTrackingKey)
        persistentStoreDescriptions.setOption(true as NSNumber,
                                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
//        if #available(iOS 14.0, *) {
//            persistentStoreDescriptions.cloudKitContainerOptions!.databaseScope = .public
//        } else {
//            self.container.managedObjectModel.entities.forEach { entity in
//                let record = ABCloudKitPublicDatabaseAutoSyncRecord(with: self.container.viewContext, entity: entity)
//                self.records.append(record)
//            }
//        }
             
        self.container.managedObjectModel.entities.forEach { entity in
            let record = ABCloudKitPublicDatabaseAutoSyncRecord(with: self.container.viewContext, entity: entity)
            self.records.append(record)
        }
        
        self.container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        self.container.viewContext.automaticallyMergesChangesFromParent = true
        self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    func saveContext () {
        let context = self.container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}

```

#### 4. AppDelegate file

``` swift

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var cloudNotification: CloudNotification = CloudNotification()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // public database
        application.registerForRemoteNotifications()
       
        return true
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        PersistenceController.shared.records.forEach({ record in
            record.processSubscriptionNotification(with: userInfo)
        })
        
        completionHandler(.newData)
    }
}
```

### Use CloudNotification


#### 1. Create Record Type on CloudKit Dashboard named "CloudNotification"

* Create fields: content(String), info(String), title(String with "Queryable,Sortable or Searchable" indexes. `!!This step is Not necessary!!`
* Create "Queryable" index to "recordName" field


#### 2. If need i18n support, create the same type named "CloudNotification_KEY" like: CloudNotification_zh, CloudNotification_jp

* Add key to "Localizable.strings" file, like: "current_lang" = "zh"; 

#### 3. AppDelegate file

``` swift

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var cloudNotification: CloudNotification = CloudNotification()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // public database
        application.registerForRemoteNotifications()
        application.applicationIconBadgeNumber = 0
        
        // Ask Permission for Notifications
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { authorized, error in })
        
         return true
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
        center.removeAllDeliveredNotifications()
    }
    
}
```

#### 4. SceneDelegate file

``` swift
...
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        
        UIApplication.shared.applicationIconBadgeNumber = 0
        (UIApplication.shared.delegate as! AppDelegate).cloudNotification.resetBadgeCounter()
    }
...

```

