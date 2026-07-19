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
    
    func getReminderLists() -> [EKCalendar] {
        var calendars = eventStore.calendars(for: .reminder)
        if !calendars.contains(where: { $0.title == "Suddha's Reminders" }) {
            if let newCal = createReminderList(title: "Suddha's Reminders") {
                calendars.append(newCal)
            }
        }
        return calendars
    }
    
    private func createReminderList(title: String) -> EKCalendar? {
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = title
        
        if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
            newCalendar.source = defaultCalendar.source
        } else {
            newCalendar.source = eventStore.sources.first
        }
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            print("Failed to create calendar '\(title)': \(error)")
            return nil
        }
    }
    
    func createReminder(data: ParsedReminderData, listIdentifier: String? = nil, completion: @escaping (Bool) -> Void) {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = data.title
        
        if let listId = listIdentifier, let list = eventStore.calendar(withIdentifier: listId) {
            reminder.calendar = list
        } else {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }
        
        if let url = data.url {
            reminder.url = url // Still set it just in case Apple fixes the UI bug
            
            // Due to a known macOS EventKit bug, the UI often ignores reminder.url. 
            // We must place it in the Notes field to ensure it is visible and clickable.
            if let existingNotes = reminder.notes, !existingNotes.isEmpty {
                reminder.notes = existingNotes + "\n\n" + url.absoluteString
            } else {
                reminder.notes = url.absoluteString
            }
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
