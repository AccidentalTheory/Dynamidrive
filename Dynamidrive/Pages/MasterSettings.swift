import SwiftUI
import MapKit

struct MasterSettings: View {
    @Binding var currentPage: AppPage
    @AppStorage("mapStyle") private var mapStyle: MapStyle = .standard
    
    enum MapStyle: String {
        case standard
        case satellite
    }
    
    var body: some View {
        ZStack {
            // Main Content
            VStack(spacing: 40) {
                HStack {
                    Text("Settings")
                        .font(.system(size: 35, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, UIScreen.main.bounds.height * 0.01)
                
                // Background Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("BACKGROUND")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack {
                        HStack {
                            Text("Background Style")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("Background Style", selection: $mapStyle) {
                                Text("Default").tag(MapStyle.standard)
                                Text("Satellite").tag(MapStyle.satellite)
                            }
                            .pickerStyle(MenuPickerStyle())
                            .accentColor(.white)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(15)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Blur Layer
            VStack(spacing: 0) {
                ProgressiveBlurView()
                    .frame(height: UIScreen.main.bounds.height * 0.15)
                    .ignoresSafeArea()
                Spacer()
            }
            .ignoresSafeArea()
            
            // Empty stack between content and buttons
            ZStack {
            }
            .frame(height: 150)
            .allowsHitTesting(false)
            
            // Fixed bottom controls
            VStack {
                Spacer()
                HStack(spacing: 80) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            currentPage = .main
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                    
                    // Invisible button for layout balance
                    Button(action: {}) {
                        Color.clear
                            .frame(width: 50, height: 50)
                    }
                    .opacity(0)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.clear)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
    }
} 