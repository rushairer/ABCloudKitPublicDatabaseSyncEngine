import Foundation
import CoreData

final class ABCloudKitPublicDatabaseAutoSyncRecord {
    
    var managedObjectContext: NSManagedObjectContext
    var container: CKContainer
    var defaults: UserDefaults
    var syncEngine: ABCloudKitPublicDatabaseSyncEngine?
    var entity: NSEntityDescription
    
    @discardableResult
    init(with managedObjectContext: NSManagedObjectContext, entity: NSEntityDescription) {
        
        self.managedObjectContext = managedObjectContext
        self.container =  CKContainer.default()
        self.defaults = UserDefaults.standard
        self.entity = entity
        let zoneID = CKRecordZone.default().zoneID
        
        self.syncEngine = ABCloudKitPublicDatabaseSyncEngine(defaults: self.defaults,
                                                           zoneID: zoneID,
                                                           recordType: "CD_\(self.entity.managedObjectClassName!)")
        
        self.syncEngine?.startCompletionBlock = {
            if let latestRecord = self.fetchLatestData() {
                self.syncEngine?.updateLatestModificationDate(date: latestRecord.value(forKey: "timestamp") as! Date)
            }
            self.syncEngine?.fetchRecentRecords()
        }
        
        self.syncEngine?.fetchRecordsCompletionBlock = { records in
            guard records != nil else { return }
            self.create(records: records!)
        }
        self.syncEngine?.createRecordCompletionBlock = { record in
            guard record != nil else { return }
            self.create(records: [record!])
        }
        
        self.syncEngine?.updateRecordCompletionBlock = { record in
            self.update(record: record!)
        }
        
        self.syncEngine?.deleteRecordCompletionBlock = { recordID in
            self.delete(recordID: recordID!)
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
    
    func fetchLatestData() -> NSManagedObject? {
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
    
    func create(records: [CKRecord]) {
        records.forEach { record in
            RecordToEntity(record: record)
        }
        self.saveContext()
    }
    
    func update(record: CKRecord) {
        
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
    
    func delete(recordID: CKRecord.ID) {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entity.managedObjectClassName)
        request.fetchLimit = 1
        let predicate = NSPredicate(format: "id == %@", recordID.recordName as CVarArg)
        request.predicate = predicate
        
        //let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        do {
            if let result = try self.managedObjectContext.fetch(request) as? [NSManagedObject] {
                self.managedObjectContext.delete(result.first!)
            }
            //try self.managedObjectContext.execute(deleteRequest)

        } catch let error {
            print(error)
        }
    }
    
    func processSubscriptionNotification(with userInfo: [AnyHashable : Any]) {
        self.syncEngine?.processSubscriptionNotification(with: userInfo)
    }
    
    func saveContext() {
        do {
            try self.managedObjectContext.save()
        } catch {
            print("Error saving managed object context: \(error)")
        }
    }
}


