import SwiftUI

struct LocationDeniedView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
                .padding(.top, 40)
            
            Text("Location Access Required")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Dynamidrive needs location access to determine your speed and adjust the music accordingly. Please enable location services in Settings to continue.")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .foregroundColor(.secondary)
            
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
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Button(action: {
                dismiss()
            }) {
                Text("Cancel")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    LocationDeniedView()
        .preferredColorScheme(.dark)
}