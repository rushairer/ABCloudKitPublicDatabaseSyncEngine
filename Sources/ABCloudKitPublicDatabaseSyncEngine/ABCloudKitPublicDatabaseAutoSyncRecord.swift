import Foundation
import CoreData

final public class ABCloudKitPublicDatabaseAutoSyncRecord {
    
    var managedObjectContext: NSManagedObjectContext
    var container: CKContainer
    var defaults: UserDefaults
    var syncEngine: ABCloudKitPublicDatabaseSyncEngine?
    var entity: NSEntityDescription
    
    @discardableResult
    public init(with managedObjectContext: NSManagedObjectContext, entity: NSEntityDescription) {
        
        self.managedObjectContext = managedObjectContext
        self.container =  CKContainer.default()
        self.defaults = UserDefaults.standard
        self.entity = entity
        let zoneID = CKRecordZone.default().zoneID
        
        self.syncEngine = ABCloudKitPublicDatabaseSyncEngine(defaults: self.defaults,
                                                           zoneID: zoneID,
                                                           recordType: "CD_\(self.entity.managedObjectClassName!)")
        
        self.syncEngine?.startCompletionBlock = {
            self.syncEngine?.fetchRecentRecords()
        }
        
        self.syncEngine?.fetchRecordsCompletionBlock = { records, updateLatestModificationDate in
            guard records != nil else { return }
            self.create(records: records!)
            
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 3) {
                if let latestRecord = self.fetchLatestData() {
                    if latestRecord.value(forKey: "timestamp") != nil {
                        updateLatestModificationDate(latestRecord.value(forKey: "timestamp") as! Date)
                    }
                }
            }
        }
        
        self.syncEngine?.createRecordCompletionBlock = { record in
            guard record != nil else { return }
            self.create(records: [record!])
        }
        
        self.syncEngine?.updateRecordCompletionBlock = { record in
            self.update(record: record!)
        }
        
        self.syncEngine?.deleteRecordCompletionBlock = { deleteID in
            self.delete(deleteID: deleteID)
        }
        
        self.syncEngine?.start()
        
    }
    
    @discardableResult
    private func RecordToEntity(record: CKRecord) -> NSManagedObject {
        let entity = NSManagedObject(entity: self.entity, insertInto: self.managedObjectContext)
                    
        record.allKeys().forEach { key in
            let newKey = key.replacingOccurrences(of: "CD_", with: "")
            let value: String = record.value(forKey: key) as! String
            if newKey == "entityName" {
                // entityName 是系统添加，跳过
            } else if newKey == "id" {
                // 取云端数据的 id 为本地数据的 id
                entity.setValue(UUID(uuidString: value), forKey: newKey)
            } else {
                entity.setValue(value, forKey: newKey)
            }
            
            // 取云端数据的 modificationDate 为本地数据的 timestamp
            entity.setValue(record.modificationDate, forKey: "timestamp")

        }
        
        return entity
    }
    
    private func fetchLatestData() -> NSManagedObject? {
        let sortDescriptor =  NSSortDescriptor(key: "timestamp", ascending: false)

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entity.managedObjectClassName!)
        request.fetchLimit = 1
        request.sortDescriptors = [sortDescriptor]
        
        do {
            if let result = try self.managedObjectContext.fetch(request) as? [NSManagedObject] {
                return result.first
            } else {
                return nil
            }
        } catch let error {
            print(error)
            return nil
        }
    }
    
    private func create(records: [CKRecord]) {
        records.forEach { record in
            RecordToEntity(record: record)
        }
        self.saveContext()
    }
    
    private func update(record: CKRecord) {
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entity.managedObjectClassName)
        request.fetchLimit = 1
        let predicate = NSPredicate(format: "id == %@", record.value(forKey: "CD_id") as! CVarArg)
        request.predicate = predicate
        
        do {
            if let result = try self.managedObjectContext.fetch(request) as? [NSManagedObject] {
                let entity = result.first!
                
                record.allKeys().forEach { key in
                    let newKey = key.replacingOccurrences(of: "CD_", with: "")
                    let value: String = record.value(forKey: key) as! String
                    if newKey == "entityName" {
                        // entityName 是系统添加，跳过
                    } else if newKey == "id" {
                        // 取云端数据的 id 为本地数据的 id
                        entity.setValue(UUID(uuidString: value), forKey: newKey)
                    } else {
                        entity.setValue(value, forKey: newKey)
                    }
                    
                    // 取云端数据的 modificationDate 为本地数据的 timestamp
                    entity.setValue(record.modificationDate, forKey: "timestamp")
                }
                self.saveContext()
            }
        } catch let error {
            print(error)
        }
    }
    
    private func delete(deleteID: String) {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entity.managedObjectClassName)
        request.fetchLimit = 1
        if let uuid = UUID(uuidString: deleteID) {
            let predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.predicate = predicate
            
            do {
                if let result = try self.managedObjectContext.fetch(request) as? [NSManagedObject] {
                    if result.count > 0 {
                        self.managedObjectContext.delete(result.first!)
                    }
                }
                
            } catch let error {
                print(error)
            }
        }
    }
    
    private func saveContext() {
        do {
            try self.managedObjectContext.save()
        } catch {
            print("Error saving managed object context: \(error)")
        }
    }
    
    public func processSubscriptionNotification(with userInfo: [AnyHashable : Any]) {
        self.syncEngine?.processSubscriptionNotification(with: userInfo)
    }
}


