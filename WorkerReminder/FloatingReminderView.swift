import SwiftUI

struct FloatingReminderView: View {
    @ObservedObject var model: ReminderOverlayModel
    
    var body: some View {
        ZStack {
            Color.clear
            Text(model.message)
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
