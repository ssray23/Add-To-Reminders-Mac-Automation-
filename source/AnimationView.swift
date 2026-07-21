import SwiftUI

struct AnimationView: View {
    let state: HUDState
    
    @State private var appear = false
    
    var body: some View {
        VStack(spacing: 12) {
            switch state {
            case .processing:
                ProgressView()
                    .controlSize(.large)
                Text("Parsing Text...")
                    .font(.headline)
            case .success(let data):
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.green)
                    .scaleEffect(appear ? 1.0 : 0.5)
                    .opacity(appear ? 1.0 : 0.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appear)
                
                Text("Reminder Created")
                    .font(.headline)
                
                if let date = data.date {
                    Text(formattedDate(date))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            case .error(let msg):
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.red)
                Text(msg)
                    .font(.headline)
            }
        }
        .padding(20)
        .frame(minWidth: 200)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .onAppear {
            appear = true
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Helper to use NSVisualEffectView in SwiftUI
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
