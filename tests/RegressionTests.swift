import Foundation
import EventKit

@main
struct RegressionTests {
    static var testsPassed = 0
    static var testsFailed = 0

    static func assertTest(_ name: String, _ condition: Bool, _ details: String = "") {
        if condition {
            testsPassed += 1
            print("  ✅ [PASS] \(name)")
        } else {
            testsFailed += 1
            print("  ❌ [FAIL] \(name) - \(details)")
        }
    }

    static func main() {
        print("==================================================")
        print("         RUNNING TEXTPARSER REGRESSION SUITE       ")
        print("==================================================")

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // 1. Relative duration tests (Hours & Minutes)
        print("\n--- 1. Relative Duration Tests ---")
        let r1 = TextParser.parse(text: "Koreaverse Recharge in 2 hours")
        assertTest("Relative 'in 2 hours' title", r1.title == "Koreaverse Recharge", "Got '\(r1.title)'")
        if let d = r1.date {
            let expectedHour = calendar.component(.hour, from: Date().addingTimeInterval(7200))
            let actualHour = calendar.component(.hour, from: d)
            assertTest("Relative 'in 2 hours' hour (\(actualHour))", actualHour == expectedHour, "Expected hour \(expectedHour), got \(actualHour)")
        } else {
            assertTest("Relative 'in 2 hours' date exists", false, "Date was nil")
        }

        let r2 = TextParser.parse(text: "Remind me in 30 mins")
        assertTest("Relative 'in 30 mins' title", r2.title == "Remind me", "Got '\(r2.title)'")
        if let d = r2.date {
            let diff = abs(d.timeIntervalSince(Date().addingTimeInterval(1800)))
            assertTest("Relative 'in 30 mins' time offset", diff < 120, "Time diff too large: \(diff)s")
        } else {
            assertTest("Relative 'in 30 mins' date exists", false, "Date was nil")
        }

        let r3 = TextParser.parse(text: "Call Mom in 6 hrs")
        assertTest("Relative 'in 6 hrs' title", r3.title == "Call Mom", "Got '\(r3.title)'")
        if let d = r3.date {
            let actualHour = calendar.component(.hour, from: d)
            let expectedHour = calendar.component(.hour, from: Date().addingTimeInterval(21600))
            assertTest("Relative 'in 6 hrs' hour (\(actualHour))", actualHour == expectedHour, "Expected \(expectedHour), got \(actualHour)")
        } else {
            assertTest("Relative 'in 6 hrs' date exists", false, "Date was nil")
        }

        // 2. Relative Duration Ranges
        print("\n--- 2. Relative Duration Ranges ---")
        let r4 = TextParser.parse(text: "Call Mom in 6 hrs or 8 hrs")
        assertTest("Multi-duration date count (2)", r4.allDetectedDates.count == 2, "Got \(r4.allDetectedDates.count) dates")

        // 3. Date-Only Durations (Default 7:00 AM)
        print("\n--- 3. Date-Only Durations (Default 7:00 AM) ---")
        let r5 = TextParser.parse(text: "Buy groceries in 3 days")
        assertTest("Relative 'in 3 days' title", r5.title == "Buy groceries", "Got '\(r5.title)'")
        if let d = r5.date {
            let hour = calendar.component(.hour, from: d)
            let min = calendar.component(.minute, from: d)
            assertTest("Relative 'in 3 days' defaults to 7:00 AM", hour == 7 && min == 0, "Got \(hour):\(min)")
        } else {
            assertTest("Relative 'in 3 days' date exists", false, "Date was nil")
        }

        // 4. Absolute Times & Typo Fixes
        print("\n--- 4. Absolute Times & Typo Fixes ---")
        let r6 = TextParser.parse(text: "Meeting tommorow at 3pm")
        assertTest("Typo 'tommorow' + '3pm' title", r6.title == "Meeting", "Got '\(r6.title)'")
        if let d = r6.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("3pm maps to 15:00", hour == 15, "Got hour \(hour)")
        } else {
            assertTest("Typo 'tommorow' date exists", false, "Date was nil")
        }

        let r7 = TextParser.parse(text: "Workout tmrw")
        assertTest("Typo 'tmrw' title", r7.title == "Workout", "Got '\(r7.title)'")
        if let d = r7.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("'tmrw' without time defaults to 7:00 AM", hour == 7, "Got hour \(hour)")
        } else {
            assertTest("Typo 'tmrw' date exists", false, "Date was nil")
        }

        // 5. Tricky Words (due, before, by, until)
        print("\n--- 5. Tricky Words Handling ---")
        let r8 = TextParser.parse(text: "Project due tomorrow")
        assertTest("Tricky word 'due' title", r8.title == "Project", "Got '\(r8.title)'")

        let r9 = TextParser.parse(text: "Report before Friday")
        assertTest("Tricky word 'before' title", r9.title == "Report", "Got '\(r9.title)'")

        // 6. Weekend Phrase Parsing
        print("\n--- 6. Weekend Phrase Parsing ---")
        let r10 = TextParser.parse(text: "Do laundry this weekend")
        assertTest("Weekend generates 2 candidate dates (Sat & Sun)", r10.allDetectedDates.count == 2, "Got \(r10.allDetectedDates.count)")
        if let d = r10.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("Weekend default time is 7:00 AM", hour == 7, "Got hour \(hour)")
        }

        let r11 = TextParser.parse(text: "Do laundry this weekend at 2pm")
        if let d = r11.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("Weekend with 'at 2pm' sets 14:00", hour == 14, "Got hour \(hour)")
        } else {
            assertTest("Weekend 'at 2pm' date exists", false, "Date was nil")
        }

        // 7. URL Extraction
        print("\n--- 7. URL Extraction ---")
        let r12 = TextParser.parse(text: "Read article https://apple.com tomorrow")
        assertTest("URL parsed correctly", r12.url?.absoluteString == "https://apple.com", "Got '\(r12.url?.absoluteString ?? "nil")'")
        assertTest("URL stripped from title", r12.title == "Read article", "Got '\(r12.title)'")

        // 8. Recurrence Parsing
        print("\n--- 8. Recurrence Parsing ---")
        let r13 = TextParser.parse(text: "Water plants every day")
        assertTest("Recurrence rule extracted", r13.recurrence != nil, "Recurrence was nil")
        assertTest("Recurrence title clean", r13.title == "Water plants", "Got '\(r13.title)'")

        print("==================================================")
        print("  SUMMARY: \(testsPassed) PASSED, \(testsFailed) FAILED")
        print("==================================================")

        if testsFailed > 0 {
            exit(1)
        }
    }
}
