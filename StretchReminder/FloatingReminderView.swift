import SwiftUI

struct FloatingReminderView: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.clear
            Text(message)
                .font(.title)
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.8))
                )
                .shadow(radius: 10)
        }
    }
}
