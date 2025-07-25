import Foundation

struct SeparatedTrack {
    let name: String
    let url: URL
}

class AIHandler {
    static let backendBaseURL = "https://demucs.dynamidrive.app"
    static let expectedTracks = ["drums.wav", "other.wav", "bass.wav", "vocals.wav"]

    static func uploadAudio(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        print("[AIHandler] Starting upload for file: \(url)")
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
        let fileName = url.lastPathComponent
        let mimeType = "audio/wav"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        let task = session.uploadTask(with: request, from: body) { data, response, error in
            if let error = error {
                print("[AIHandler] Upload failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            print("[AIHandler] Upload succeeded for file: \(fileName)")
            let baseName = url.deletingPathExtension().lastPathComponent
            completion(.success(baseName))
        }
        task.resume()
    }

    static func pollForTracks(baseName: String, completion: @escaping ([SeparatedTrack]?) -> Void) {
        print("[AIHandler] Polling for separated tracks for baseName: \(baseName)")
        let url = URL(string: "\(backendBaseURL)/")!
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
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
                completion(foundTracks)
            } else {
                print("[AIHandler] Not all tracks found yet for baseName: \(baseName). Found: \(foundTracks.map { $0.name })")
                completion(nil)
            }
        }
        task.resume()
    }

    static func parseTrackLinks(from html: String, baseName: String) -> [SeparatedTrack] {
        var tracks: [SeparatedTrack] = []
        for track in expectedTracks {
            let newFileName = "\(baseName)_\(track)"
            let downloadPath = "/download/\(newFileName)"
            if html.contains(newFileName) {
                if let url = URL(string: "\(backendBaseURL)\(downloadPath)") {
                    tracks.append(SeparatedTrack(name: track, url: url))
                }
            }
        }
        return tracks
    }

    static func downloadTracks(tracks: [SeparatedTrack], completion: @escaping ([URL]?) -> Void) {
        print("[AIHandler] Starting download of \(tracks.count) tracks...")
        var downloaded: [URL] = Array(repeating: URL(fileURLWithPath: "/"), count: tracks.count)
        let group = DispatchGroup()
        var downloadError: Bool = false
        for (i, track) in tracks.enumerated() {
            group.enter()
            let downloadURL = track.url
            print("[AIHandler] Downloading from URL: \(downloadURL)")
            let task = URLSession.shared.downloadTask(with: downloadURL) { tempURL, response, error in
                defer { group.leave() }
                if let error = error {
                    print("[AIHandler] Failed to download \(track.name): \(error.localizedDescription)")
                    downloadError = true
                    return
                }
                guard let tempURL = tempURL else {
                    print("[AIHandler] Failed to download \(track.name): No file URL.")
                    downloadError = true
                    return
                }
                if let data = try? Data(contentsOf: tempURL) {
                    let prefix = data.prefix(100)
                    let prefixString = String(decoding: prefix, as: UTF8.self)
                    print("[AIHandler] First 100 bytes of \(track.name): \(prefixString)")
                }
                let fileManager = FileManager.default
                let fileName = track.url.lastPathComponent
                let destURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: destURL)
                do {
                    try fileManager.moveItem(at: tempURL, to: destURL)
                    if let attrs = try? fileManager.attributesOfItem(atPath: destURL.path), let fileSize = attrs[.size] as? UInt64 {
                        print("[AIHandler] Downloaded \(fileName) to \(destURL), size: \(fileSize) bytes")
                    } else {
                        print("[AIHandler] Downloaded \(fileName) to \(destURL), size: unknown")
                    }
                    downloaded[i] = destURL
                } catch {
                    print("[AIHandler] Failed to save \(track.name): \(error.localizedDescription)")
                    downloadError = true
                }
            }
            task.resume()
        }
        group.notify(queue: .main) {
            if downloadError {
                print("[AIHandler] One or more downloads failed.")
                completion(nil)
            } else {
                print("[AIHandler] All tracks downloaded successfully.")
                completion(downloaded)
            }
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