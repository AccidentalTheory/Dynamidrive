import SwiftUI

struct LocationDeniedView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            
            
            Image(systemName: "location.slash.fill")
                .font(.system(size: 100))
                .foregroundColor(.red)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .padding(.top, 80)
            
            Text("Where are you?")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .padding(.top, 20)
            
            Text("Dynamidrive needs location access to determine your speed and adjust the music accordingly. Please enable location services in Settings to continue.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)
            
            Text("Choose \"Always Allow\" so the music can update in the background.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 5)
            
            
            
            Spacer()
            
            Button(action: {
                if let url = URL(string: "https://b-dog.co/pp") {
#if os(macOS)
                    NSWorkspace.shared.open(url)
#else
                    UIApplication.shared.open(url)
#endif
                }
            }) {
                Text("Privacy Policy")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .cornerRadius(99)
                    .glassEffect(.regular.tint(.clear).interactive())
            }
            .padding(.horizontal, 20)
            .offset(y: 7)
            
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
#if os(macOS)
                    NSWorkspace.shared.open(url)
#else
                    UIApplication.shared.open(url)
#endif
                }
            }) {
                Text("Open Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .cornerRadius(99)
                    .glassEffect(.regular.tint(.blue).interactive())
            }
            .padding(.horizontal, 20)
            
            
        }
        .padding()
    }
}

#Preview {
    LocationDeniedView()
        .preferredColorScheme(.dark)
}
