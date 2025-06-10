import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Add completion handler to clean up temp directory
        controller.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            if let url = activityItems.first as? URL {
                // Get the parent temp directory
                let tempBaseURL = url.deletingLastPathComponent()
                
                // Clean up after a short delay to ensure sharing is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    try? FileManager.default.removeItem(at: tempBaseURL)
                }
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 