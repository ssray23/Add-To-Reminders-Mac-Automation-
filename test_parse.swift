import Foundation

@main
struct TestApp {
    static func main() {
        let combinedText = "Meeting with John tomorrow at 4pm or Thursday at 2pm"
        let parsed = TextParser.parse(text: combinedText)
        print("Detected dates count: \(parsed.allDetectedDates.count)")
        for d in parsed.allDetectedDates {
            print("Date: \(d)")
        }
    }
}
