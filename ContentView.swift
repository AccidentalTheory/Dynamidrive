// State variables
@State private var showVolumePage: Bool = false
@State private var createBaseVolume: Double = 0.0  // Changed from Float to Double
@State private var createBaseTitle: String = "Base"
@State private var createBaseAudioURL: URL?
@State private var createBasePlayer: AVAudioPlayer?
@State private var createAdditionalZStacks: [ZStackData] = []
@State private var createAdditionalTitles: [String] = []

private func mapVolume(_ percentage: Double) -> Double {  // Changed from Float to Double
    let mapped = (percentage + 100) / 100
    return max(0.0, min(2.0, mapped))
}

private var volumeScreen: some View {
    VolumeScreen(
        showVolumePage: $showVolumePage,
        createBaseTitle: $createBaseTitle,
        createBaseVolume: $createBaseVolume,  // Now matches the expected type
        createBaseAudioURL: $createBaseAudioURL,
        createBasePlayer: $createBasePlayer,
        createAdditionalZStacks: $createAdditionalZStacks,
        createAdditionalTitles: $createAdditionalTitles
    )
} 