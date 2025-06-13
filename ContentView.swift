@State private var createBaseVolume: Double = 0.0
@State private var createBaseTitle: String = "Base"
@State private var createAdditionalZStacks: [ZStackData] = []
@State private var createAdditionalTitles: [String] = []

private func mapVolume(_ percentage: Double) -> Float {
    let mapped = (percentage + 100) / 100
    return Float(max(0.0, min(2.0, mapped)))
}

private var volumeScreen: some View {
    VolumeScreen(
        showVolumePage: $showVolumePage,
        createBaseTitle: $createBaseTitle,
        createBaseVolume: Binding(
            get: { Double(createBaseVolume) },
            set: { createBaseVolume = Float($0) }
        ),
        createBaseAudioURL: $createBaseAudioURL,
        createBasePlayer: $createBasePlayer,
        createAdditionalZStacks: $createAdditionalZStacks,
        createAdditionalTitles: $createAdditionalTitles
    )
} 