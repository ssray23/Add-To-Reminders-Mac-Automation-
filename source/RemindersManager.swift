import Foundation
import EventKit

class RemindersManager {
    static let shared = RemindersManager()
    let eventStore = EKEventStore()
    
    func requestAccess(completion: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        
        if #available(macOS 14.0, *) {
            if status == .fullAccess || status == .authorized {
                completion(true)
                return
            }
            eventStore.requestFullAccessToReminders { granted, error in
                completion(granted)
            }
        } else {
            if status == .authorized {
                completion(true)
                return
            }
            eventStore.requestAccess(to: .reminder) { granted, error in
                completion(granted)
            }
        }
    }
    
    func createReminder(data: ParsedReminderData, completion: @escaping (Bool) -> Void) {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = data.title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
        if let url = data.url {
            reminder.url = url
        }
        
        if let date = data.date {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            reminder.dueDateComponents = components
            
            // Also set an alarm so it actually notifies
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }
        
        if let recurrence = data.recurrence {
            reminder.recurrenceRules = [recurrence]
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            completion(true)
        } catch {
            print("Failed to save reminder: \(error)")
            completion(false)
        }
    }
}
