import Foundation
import AVFoundation

// Notification names for AI download progress
extension Notification.Name {
    static let aiDownloadCompleted = Notification.Name("aiDownloadCompleted")
    static let aiDownloadProgress = Notification.Name("aiDownloadProgress")
}

struct SeparatedTrack {
    let name: String
    let url: URL
    let trackType: String // e.g., "Drums", "Bass", "Vocals", "Other"
    let baseName: String // The base name of the original audio file
}

class AIHandler {
    static let backendBaseURL = "https://demucs.dynamidrive.app"
    static let expectedTracks = ["vocals.wav", "drums.wav", "bass.wav", "other.wav"]
    
    // Helper function to sanitize filenames by removing special characters
    static func sanitizeFileName(_ fileName: String) -> String {
        // Remove special characters that could cause issues in URLs or file systems
        // Keep alphanumeric characters, spaces, hyphens, and underscores
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        let sanitized = fileName.components(separatedBy: allowedCharacters.inverted).joined()
        
        // Remove leading/trailing whitespace and replace multiple spaces with single space
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleSpaced = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Ensure the filename is not empty
        return singleSpaced.isEmpty ? "audio_file" : singleSpaced
    }

    static func uploadAudio(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        print("[AIHandler] Starting upload for file: \(url.lastPathComponent)")
        var fileData: Data?
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            fileData = try Data(contentsOf: url)
            print("[AIHandler] Successfully read file data for: \(url.lastPathComponent), size: \(fileData?.count ?? 0) bytes")
        } catch {
            print("[AIHandler] Failed to read file data: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        guard let fileData = fileData else {
            print("[AIHandler] File data is nil after reading: \(url.lastPathComponent)")
            completion(.failure(NSError(domain: "AIHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read file data."])));
            return
        }
        
        var request = URLRequest(url: URL(string: "\(backendBaseURL)/upload")!)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let fieldName = "file"
        let originalFileName = url.lastPathComponent
        let sanitizedFileName = sanitizeFileName(originalFileName)
        let mimeType = "audio/wav"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(sanitizedFileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Set up a custom session configuration with longer timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600 // 10 minutes
        config.timeoutIntervalForResource = 600 // 10 minutes
        let session = URLSession(configuration: config)
        
        let task = session.uploadTask(with: request, from: body) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[AIHandler] Upload failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                print("[AIHandler] Upload succeeded for file: \(sanitizedFileName) (original: \(originalFileName))")
                let baseName = sanitizeFileName(url.deletingPathExtension().lastPathComponent)
                completion(.success(baseName))
            }
        }
        task.resume()
    }

    static func pollForTracks(baseName: String, completion: @escaping ([SeparatedTrack]?) -> Void) {
        print("[AIHandler] Polling for separated tracks for baseName: \(baseName)")
        let url = URL(string: "\(backendBaseURL)/")!
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[AIHandler] Polling failed: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                guard let data = data, let html = String(data: data, encoding: .utf8) else {
                    print("[AIHandler] Polling failed: Unable to decode server response.")
                    completion(nil)
                    return
                }
                let foundTracks = parseTrackLinks(from: html, baseName: baseName)
                print("[AIHandler] Polling result: found \(foundTracks.count) tracks for baseName: \(baseName)")
                if foundTracks.count == expectedTracks.count {
                    print("[AIHandler] All expected tracks found for baseName: \(baseName)")
                    // Return the tracks immediately when discovered (before download)
                    completion(foundTracks)
                    // Download all found tracks to AI_Downloaded_Files directory in background
                    downloadTracks(tracks: foundTracks, baseName: baseName) { downloadedTracks in
                        // Download completion is handled separately
                        print("[AIHandler] Background download completed for \(downloadedTracks?.count ?? 0) tracks")
                        // Call the download completion handler if provided
                        if let downloadedTracks = downloadedTracks {
                            // Notify that download is complete
                            print("[AIHandler] Posting aiDownloadCompleted notification with \(downloadedTracks.count) tracks")
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .aiDownloadCompleted, object: downloadedTracks)
                                print("[AIHandler] Posted aiDownloadCompleted notification")
                            }
                        }
                    }
                } else {
                    print("[AIHandler] Not all tracks found yet for baseName: \(baseName). Found: \(foundTracks.map { $0.name })")
                    completion(nil)
                }
            }
        }
        task.resume()
    }

    static func downloadTracks(tracks: [SeparatedTrack], baseName: String, completion: @escaping ([SeparatedTrack]?) -> Void) {
        print("[AIHandler] Starting download of \(tracks.count) tracks for baseName: \(baseName)")
        
        // Create AI_Downloaded_Files directory if it doesn't exist
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let aiDownloadedFilesPath = documentsPath.appendingPathComponent("AI_Downloaded_Files")
        
        do {
            try fileManager.createDirectory(at: aiDownloadedFilesPath, withIntermediateDirectories: true, attributes: nil)
            print("[AIHandler] Created/verified AI_Downloaded_Files directory at: \(aiDownloadedFilesPath)")
        } catch {
            print("[AIHandler] Failed to create AI_Downloaded_Files directory: \(error.localizedDescription)")
            completion(nil)
            return
        }
        
        var downloaded: [SeparatedTrack] = []
        let group = DispatchGroup()
        var downloadError: String? = nil
        var completedDownloads = 0
        let totalDownloads = tracks.count
        
        for track in tracks {
            group.enter()
            let downloadURL = track.url
            print("[AIHandler] Downloading from URL: \(downloadURL)")
            
            // Create a custom session with longer timeout for downloads
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 600 // 10 minutes
            config.timeoutIntervalForResource = 600 // 10 minutes
            let downloadSession = URLSession(configuration: config)
            
            let task = downloadSession.downloadTask(with: downloadURL) { tempURL, response, error in
                defer { group.leave() }
                
                if let error = error {
                    // Check if it's a timeout error
                    let nsError = error as NSError
                    if nsError.code == NSURLErrorTimedOut {
                        print("[AIHandler] Timeout downloading \(track.name), but download may still be in progress...")
                        // Don't set downloadError for timeout, as the download might still complete
                        return
                    } else {
                        downloadError = "Failed to download \(track.name): \(error.localizedDescription)"
                        print("[AIHandler] \(downloadError!)")
                        return
                    }
                }
                
                guard let tempURL = tempURL else {
                    downloadError = "Failed to download \(track.name): No file URL."
                    print("[AIHandler] \(downloadError!)")
                    return
                }
                
                // Create destination URL in AI_Downloaded_Files with proper naming
                let fileName = track.url.lastPathComponent
                let destURL = aiDownloadedFilesPath.appendingPathComponent(fileName)
                
                // Remove existing file if it exists
                try? fileManager.removeItem(at: destURL)
                
                do {
                    try fileManager.moveItem(at: tempURL, to: destURL)
                    
                    // Debug: print file URL and size
                    if let attrs = try? fileManager.attributesOfItem(atPath: destURL.path), let fileSize = attrs[.size] as? UInt64 {
                        print("[AIHandler] Downloaded \(fileName) to \(destURL), size: \(fileSize) bytes")
                    } else {
                        print("[AIHandler] Downloaded \(fileName) to \(destURL), size: unknown")
                    }
                    
                    // Convert WAV to compressed audio format (.mp3 extension) for app compatibility
                    if let mp3URL = convertWAVToMP3(wavURL: destURL) {
                        // Delete the original WAV file after successful conversion
                        try? fileManager.removeItem(at: destURL)
                        print("[AIHandler] Successfully converted \(fileName) to compressed audio format and deleted original WAV file")
                        
                        // Create track with compressed audio URL for app use
                        let downloadedTrack = SeparatedTrack(name: track.name, url: mp3URL, trackType: track.trackType, baseName: baseName)
                        downloaded.append(downloadedTrack)
                    } else {
                        print("[AIHandler] Failed to convert \(fileName) to compressed audio format, keeping original WAV file as fallback")
                        // Keep original WAV file if conversion fails (fallback)
                        let downloadedTrack = SeparatedTrack(name: track.name, url: destURL, trackType: track.trackType, baseName: baseName)
                        downloaded.append(downloadedTrack)
                    }
                    
                    // Update progress
                    completedDownloads += 1
                    let progress = Double(completedDownloads) / Double(totalDownloads)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiDownloadProgress, object: progress)
                    }
                    
                } catch {
                    downloadError = "Failed to save \(track.name): \(error.localizedDescription)"
                    print("[AIHandler] \(downloadError!)")
                }
            }
            task.resume()
        }
        
        group.notify(queue: .main) {
            // Check if files actually exist, even if there were timeout errors
            let existingFiles = downloaded.filter { fileManager.fileExists(atPath: $0.url.path) }
            print("[AIHandler] Verification: \(existingFiles.count) out of \(downloaded.count) files actually exist on disk")
            
            if let error = downloadError {
                print("[AIHandler] Download failed: \(error)")
                completion(nil)
            } else {
                print("[AIHandler] Successfully downloaded, converted to compressed audio format, and stored all \(downloaded.count) tracks in AI_Downloaded_Files")
                print("[AIHandler] Processed tracks: \(downloaded.map { $0.name })")
                print("[AIHandler] Final track URLs (compressed audio): \(downloaded.map { $0.url.path })")
                completion(downloaded)
            }
        }
    }

    // MARK: - Audio Conversion
    static func convertWAVToMP3(wavURL: URL) -> URL? {
        print("[AIHandler] Converting WAV to compressed audio: \(wavURL.lastPathComponent)")
        
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let aiDownloadedFilesPath = documentsPath.appendingPathComponent("AI_Downloaded_Files")
        
        // Create compressed audio filename by replacing .wav extension with .m4a
        // We'll use .m4a extension to match the actual format being created
        let compressedFileName = wavURL.lastPathComponent.replacingOccurrences(of: ".wav", with: ".m4a")
        let compressedURL = aiDownloadedFilesPath.appendingPathComponent(compressedFileName)
        
        // Remove existing compressed file if it exists
        try? fileManager.removeItem(at: compressedURL)
        
        // Create AVURLAsset from WAV file
        let asset = AVURLAsset(url: wavURL)
        
        // Create export session with high quality preset
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            print("[AIHandler] Failed to create export session for \(wavURL.lastPathComponent)")
            return nil
        }
        
        // Configure export session for compressed audio
        exportSession.outputURL = compressedURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Set up audio settings for high quality compressed audio
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        exportSession.audioTimePitchAlgorithm = .spectral
        
        // Debug: Print basic asset info
        print("[AIHandler] Converting file: \(wavURL.lastPathComponent)")
        print("[AIHandler] Output file: \(compressedURL.lastPathComponent)")
        
        // Create a semaphore to wait for export completion
        let semaphore = DispatchSemaphore(value: 0)
        var exportSuccess = false
        var exportError: String?
        
        print("[AIHandler] Starting export session for \(wavURL.lastPathComponent)")
        
        exportSession.exportAsynchronously {
            print("[AIHandler] Export session completed for \(wavURL.lastPathComponent)")
            
            // Check if the export was successful by checking if the file exists
            if fileManager.fileExists(atPath: compressedURL.path) {
                print("[AIHandler] Successfully converted \(wavURL.lastPathComponent) to compressed audio format")
                if let attrs = try? fileManager.attributesOfItem(atPath: compressedURL.path), let fileSize = attrs[.size] as? UInt64 {
                    print("[AIHandler] Compressed audio file size: \(fileSize) bytes")
                }
                exportSuccess = true
            } else {
                exportError = "Export failed - file not created"
                print("[AIHandler] Failed to convert \(wavURL.lastPathComponent): \(exportError!)")
            }
            semaphore.signal()
        }
        
        // Wait for export to complete (with timeout)
        let timeout = DispatchTime.now() + .seconds(60) // 60 second timeout
        let waitResult = semaphore.wait(timeout: timeout)
        
        if waitResult == .timedOut {
            print("[AIHandler] Conversion timed out for \(wavURL.lastPathComponent)")
            return nil
        }
        
        if exportSuccess && fileManager.fileExists(atPath: compressedURL.path) {
            print("[AIHandler] Successfully created compressed audio file with .m4a extension")
            
            // Debug: Check the actual file format
            if let data = try? Data(contentsOf: compressedURL) {
                let header = data.prefix(16)
                print("[AIHandler] File header (hex): \(header.map { String(format: "%02x", $0) }.joined())")
                
                // Check if it's actually an M4A file (should start with 'ftyp')
                if header.count >= 4 && String(data: header.prefix(4), encoding: .ascii) == "ftyp" {
                    print("[AIHandler] File is actually M4A format (expected for iOS export)")
                } else {
                    print("[AIHandler] File format unknown")
                }
            }
            
            return compressedURL
        } else {
            print("[AIHandler] Conversion failed or file doesn't exist: \(compressedURL.path)")
            if let error = exportError {
                print("[AIHandler] Export error: \(error)")
            }
            
            // Fallback: Keep original WAV file if conversion fails
            print("[AIHandler] Conversion failed, keeping original WAV file as fallback")
            return wavURL
        }
    }

    static func parseTrackLinks(from html: String, baseName: String) -> [SeparatedTrack] {
        var tracks: [SeparatedTrack] = []
        for track in expectedTracks {
            let newFileName = "\(baseName)_\(track)"
            // Always use /download/ prefix for separated files
            let downloadPath = "/download/\(newFileName)"
            if html.contains(newFileName) {
                if let url = URL(string: "\(backendBaseURL)\(downloadPath)") {
                    let trackType = parseTrackType(from: track)
                    tracks.append(SeparatedTrack(name: track, url: url, trackType: trackType, baseName: baseName))
                    print("[AIHandler] Found track: \(trackType) at \(url)")
                }
            } else {
                print("[AIHandler] Track not found in HTML: \(newFileName)")
            }
        }
        return tracks
    }

    static func parseTrackType(from filename: String) -> String {
        // Remove .wav extension and map to display names
        let baseName = filename.replacingOccurrences(of: ".wav", with: "")
        switch baseName.lowercased() {
        case "drums":
            return "Drums"
        case "bass":
            return "Bass"
        case "vocals":
            return "Vocals"
        case "other":
            return "Other"
        default:
            return baseName.capitalized
        }
    }
}

// Helper to append Data
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
} 
