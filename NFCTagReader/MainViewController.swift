import UIKit
import CoreNFC
import Foundation

class MainViewController: UIViewController, NFCNDEFReaderSessionDelegate {
    // MARK: - Properties
    let reuseIdentifier = "reuseIdentifier"
    var detectedMessages = [NFCNDEFMessage]()
    var session: NFCNDEFReaderSession?

    @IBAction func beginScanning(_ sender: Any) {
        self.startNFCSession()
    }

    func startNFCSession() {
        guard NFCNDEFReaderSession.readingAvailable else {
            let alertController = UIAlertController(
                title: "Scanning Not Supported",
                message: "This device doesn't support tag scanning.",
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true, completion: nil)
            return
        }

        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Start looking for treasure!"
        session?.begin()
    }

    /// - Tag: processingTagData
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        DispatchQueue.main.async {
            // Process detected NFCNDEFMessage objects.
            self.detectedMessages.append(contentsOf: messages)
        }
    }

    /// - Tag: processingNDEFTag
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        var foundError = false
        let tag = tags.first!

        session.connect(to: tag, completionHandler: { (error: Error?) in
            if nil != error {
                foundError = true
                return
            }

            tag.queryNDEFStatus(completionHandler: { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
                if .notSupported == ndefStatus {
                    foundError = true
                    return
                } else if nil != error {
                    foundError = true
                    return
                }

                tag.readNDEF(completionHandler: { (message: NFCNDEFMessage?, error: Error?) in
                    if error != nil {
                        foundError = true
                        return
                    }

                    guard let message = message, let record = message.records.first else {
                        foundError = true
                        return
                    }

                    var id: Int?
                    if let payloadString = String(data: record.payload, encoding: .utf8),
                       let jsonData = payloadString.data(using: .utf8),
                       let payloadDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                       let extractedId = payloadDict["id"] as? Int {
                        print("Extracted ID: \(extractedId)")
                        id = extractedId // Assign the parsed ID to the variable `id`
                    } else {
                        foundError = true
                        return
                    }
                    let host = UserDefaults.standard.string(forKey: "host") ?? "default.host"
                    let port = UserDefaults.standard.string(forKey: "port") ?? "8080"
                    let responsibility = UserDefaults.standard.string(forKey: "responsibility") ?? "unknown"

                    let requestBody: [String: String] = ["role": responsibility, "id": id != nil ? String(id!) : "unknown"]
                    guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: []) else {
                        session.alertMessage = "Failed to serialize request body."
                        foundError = true
                        return
                    }

                    guard let url = URL(string: "http://\(host):\(port)") else {
                        foundError = true
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = httpBody

                    let urlSession = URLSession.shared
                    let task = urlSession.dataTask(with: request) { data, response, error in
                        if error != nil {
                            foundError = true
                            return
                        }

                        // Handle the response
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            // session.alertMessage = "Request succeeded."
                        } else {
                            foundError = true
                            return
                        }
                    }
                    task.resume()
                })
                return
            })
        })
        if foundError {
            // NOTE (stevenchu): This might be a thing... it wasn't working as well on my iPhone 7 as my iPhone 13 so...
            // the internet says anything to do with an NFC session needs to happen inside the main thread who knows
            // DispatchQueue.main.async { session.invalidate() }
            session.invalidate()
            return // Idk ...
        }
        let retryInterval = DispatchTimeInterval.milliseconds(500)
        DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval, execute: {
            session.restartPolling()
        })
    }
    
    /// - Tag: sessionBecomeActive
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        
    }
    
    /// - Tag: endScanning
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code == .readerSessionInvalidationErrorSessionTimeout {
                print("Session timeout, restarting after 0.5 second...")
                let retryInterval = DispatchTimeInterval.milliseconds(500)
                DispatchQueue.main.asyncAfter(deadline: .now() + retryInterval) {
                    self.startNFCSession()
                }
                return
            }

            if (readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead)
                && (readerError.code != .readerSessionInvalidationErrorUserCanceled) {
                let alertController = UIAlertController(
                    title: "Session Invalidated",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                DispatchQueue.main.async {
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }

        // To read new tags, a new session instance is required
        self.session = nil
    }

    // MARK: - addMessage(fromUserActivity:)

    func addMessage(fromUserActivity message: NFCNDEFMessage) {
        DispatchQueue.main.async {
            self.detectedMessages.append(message)
        }
    }

    func writeBlankNDEFTag(tag: NFCNDEFTag, completion: @escaping (Bool) -> Void) {
            let emptyRecord = NFCNDEFPayload(format: .empty, type: Data(), identifier: Data(), payload: Data())
            let emptyMessage = NFCNDEFMessage(records: [emptyRecord])

            tag.writeNDEF(emptyMessage) { (error) in
                if let error = error {
                    print("Failed to write to the tag: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                print("Successfully wrote blank data to the NFC tag.")
                completion(true)
            }
        }

}
