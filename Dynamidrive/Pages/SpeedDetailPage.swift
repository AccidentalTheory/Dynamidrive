import SwiftUI
import UIKit

struct SpeedDetailPage: View {
    @Binding var showSpeedDetailPage: Bool
    @Binding var showSettingsPage: Bool
    @Binding var areButtonsVisible: Bool
    @Binding var animatedSpeed: Double
    @Binding var useBlackBackground: Bool
    @Binding var landscapeGaugeStyle: String
    @Binding var landscapeIndicatorStyle: String
    @Binding var landscapeShowMinMax: Bool
    @Binding var landscapeShowCurrentSpeed: Bool
    @Binding var landscapeShowSoundtrackTitle: Bool
    @Binding var syncCircularGaugeSettings: Bool
    @Binding var gaugeFontStyle: String
    @Binding var showPortraitSpeed: Bool
    @Binding var portraitGaugeStyle: String
    @Binding var portraitShowMinMax: Bool
    @Binding var pendingSoundtrack: Soundtrack?
    @Binding var audioController: AudioController
    @Binding var deviceOrientation: UIDeviceOrientation
    let startInactivityTimer: () -> Void
    let invalidateInactivityTimer: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            ZStack {
                if useBlackBackground {
                    Rectangle()
                        .fill(.black)
                        .ignoresSafeArea()
                }
                // Gauge content is now fully outside PageLayout
                VStack {
                    Spacer()
                    if isLandscape {
                        if landscapeGaugeStyle == "line" {
                            landscapeLinearGauge(geometry: geometry)
                        } else {
                            landscapeCircularGauge(geometry: geometry)
                        }
                    } else {
                        portraitGauge(geometry: geometry)
                    }
                    Spacer()
                }
                .animation(.easeInOut(duration: 1.0), value: animatedSpeed)
                // PageLayout is used ONLY for the bottom button bar
                PageLayout(
                    title: "",
                    leftButtonAction: {},
                    rightButtonAction: {},
                    leftButtonSymbol: "",
                    rightButtonSymbol: "",
                    bottomButtons: areButtonsVisible ? [
                        PageButton(label: {
                            Image(systemName: "arrow.uturn.backward").globalButtonStyle()
                        }, action: {
                            OrientationUtils.setDeviceOrientation(.portrait) // Force portrait on back
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showSpeedDetailPage = false
                            }
                        }),
                        PageButton(label: {
                            Image(systemName: audioController.isSoundtrackPlaying ? "pause.fill" : "play.fill").globalButtonStyle()
                        }, action: {
                            audioController.toggleSoundtrackPlayback()
                        }),
                        PageButton(label: {
                            Image(systemName: "gearshape").globalButtonStyle()
                        }, action: {
                            OrientationUtils.setDeviceOrientation(.portrait) // Force portrait on settings
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showSettingsPage = true
                            }
                        })
                    ] : [],
                    showEdgeGradients: false // Hide gradients only on this page
                ) {
                    EmptyView() // No content in PageLayout
                }
            }
            .contentShape(Rectangle())
            .gesture(
                TapGesture()
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            areButtonsVisible = true
                        }
                        startInactivityTimer()
                    }
            )
            .onAppear {
                areButtonsVisible = true
                startInactivityTimer()
                UIApplication.shared.isStatusBarHidden = true
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                areButtonsVisible = true
                invalidateInactivityTimer()
                UIApplication.shared.isStatusBarHidden = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                deviceOrientation = UIDevice.current.orientation
            }
            .zIndex(4)
        }
        .id(deviceOrientation) // <-- Add this line to force layout update on orientation change
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
    }
    
    private func landscapeLinearGauge(geometry: GeometryProxy) -> some View {
        let scaledSpeed = animatedSpeed
        return ZStack(alignment: .center) {
            if landscapeShowSoundtrackTitle {
                Text(pendingSoundtrack?.title ?? (audioController.currentSoundtrackTitle.isEmpty ? " " : audioController.currentSoundtrackTitle))
                    .font(.system(size: 45, weight: .bold, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: landscapeShowMinMax ? .center : .leading)
                    .padding(.bottom, 20)
                    .offset(x: landscapeShowMinMax ? 0 : 80, y: -40)
            }
            Group {
                if landscapeIndicatorStyle == "fill" {
                    if landscapeShowMinMax {
                        Gauge(value: scaledSpeed, in: 0...180) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("0")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        } maximumValueLabel: {
                            Text("180")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .frame(width: geometry.size.width * 0.2, height: 8)
                        .scaleEffect(4.0)
                    } else {
                        Gauge(value: scaledSpeed, in: 0...180) {
                            EmptyView()
                        }
                        .gaugeStyle(.linearCapacity)
                        .frame(width: geometry.size.width * 0.2, height: 8)
                        .scaleEffect(4.0)
                    }
                } else {
                    Gauge(value: scaledSpeed, in: 0...180) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        if landscapeShowMinMax {
                            Text("0")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        }
                    } maximumValueLabel: {
                        if landscapeShowMinMax {
                            Text("180")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        }
                    }
                    .gaugeStyle(.accessoryLinear)
                    .frame(width: geometry.size.width * 0.2, height: 100)
                    .scaleEffect(4.0)
                }
            }
            .tint(.white)
            if landscapeShowCurrentSpeed {
                if landscapeShowMinMax == false {
                    Text("\(Int(animatedSpeed)) mph")
                        .font(.system(size: 40, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                        .foregroundColor(.white.opacity(0.5))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: false))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                        .offset(x:80, y: 40)
                }; if landscapeShowMinMax == true {
                    Text("\(Int(animatedSpeed)) mph")
                        .font(.system(size: 40, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                        .foregroundColor(.white.opacity(0.5))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: false))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                        .offset(y: 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func landscapeCircularGauge(geometry: GeometryProxy) -> some View {
        let scaledSpeed = animatedSpeed
        return ZStack {
            Gauge(value: scaledSpeed, in: 0...180) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            } minimumValueLabel: {
                if landscapeShowMinMax {
                    Text("0")
                        .font(.system(size: 10, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
            } maximumValueLabel: {
                if landscapeShowMinMax {
                    Text("180")
                        .font(.system(size: 10, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.white.opacity(1))
            .frame(width: min(geometry.size.width, geometry.size.height) * 0.7)
            .scaleEffect(4.5)
            if landscapeShowCurrentSpeed {
                Text("\(Int(animatedSpeed))")
                    .font(.system(size: 110, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .offset(y: -5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
    
    private func portraitGauge(geometry: GeometryProxy) -> some View {
        let scaledSpeed = animatedSpeed
        return Group {
            if portraitGaugeStyle == "fullCircle" {
                ZStack {
                    Gauge(value: scaledSpeed, in: 0...180) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        EmptyView()
                    } maximumValueLabel: {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.white.opacity(0.5))
                    .frame(width: geometry.size.width * 0.7, height: geometry.size.width * 0.7)
                    .scaleEffect(5.0)
                    if showPortraitSpeed {
                        Text("\(Int(animatedSpeed))")
                            .font(.system(size: 110, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
            } else {
                ZStack {
                    Gauge(value: scaledSpeed, in: 0...180) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        if portraitShowMinMax {
                            Text("0")
                                .font(.system(size: 10, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.5)
                        }
                    } maximumValueLabel: {
                        if portraitShowMinMax {
                            Text("180")
                                .font(.system(size: 10, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(.white.opacity(1))
                    .frame(width: geometry.size.width * 0.7, height: geometry.size.width * 0.7)
                    .scaleEffect(5.0)
                    if showPortraitSpeed {
                        Text("\(Int(animatedSpeed))")
                            .font(.system(size: 110, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                            .offset(y: -5)
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    

    
    struct InfoRow: View {
        let number: String
        let text: String
        var body: some View {
            HStack(spacing: 15) {
                Text(number)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
                Text(text)
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
} 
