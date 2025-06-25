import SwiftUI

struct FloatingReminderView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.title)
            .padding()
            .foregroundColor(.white)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            .shadow(radius: 10)
    }
}
