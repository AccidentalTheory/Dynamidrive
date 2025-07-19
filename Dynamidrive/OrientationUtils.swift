import UIKit

enum OrientationUtils {
    static func setDeviceOrientation(_ orientation: UIInterfaceOrientationMask) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("Failed to get window scene for orientation change")
            return
        }
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
            print("Failed to update orientation: \(error)")
        }
    }
} 