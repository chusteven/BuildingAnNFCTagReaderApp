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
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No NFC tag detected.")
            return
        }

        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "Failed to connect to tag: \(error.localizedDescription)")
                return
            }

            tag.queryNDEFStatus { ndefStatus, capacity, error in
                if ndefStatus == .notSupported {
                    session.invalidate(errorMessage: "This tag does not support NDEF.")
                    return
                }
                if let error = error {
                    session.invalidate(errorMessage: "Error querying NDEF status: \(error.localizedDescription)")
                    return
                }

                tag.readNDEF { message, error in
                    if let error = error {
                        session.invalidate(errorMessage: "Failed to read NFC tag: \(error.localizedDescription)")
                        return
                    }

                    guard let message = message, let record = message.records.first else {
                        session.invalidate(errorMessage: "No valid data found on the NFC tag.")
                        return
                    }

                    // Parse the payload to extract the `id`
                    guard let payloadString = String(data: record.payload, encoding: .utf8),
                          let jsonData = payloadString.data(using: .utf8),
                          let payloadDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                          let id = payloadDict["id"] as? Int else {
                        session.invalidate(errorMessage: "Failed to parse payload.")
                        return
                    }

                    print("Extracted ID: \(id)")

                    // Get `role` from UserDefaults
                    let responsibility = UserDefaults.standard.string(forKey: "responsibility") ?? "unknown"

                    // Create the request body
                    let requestBody: [String: Any] = ["id": id, "role": responsibility]
                    guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: []) else {
                        session.invalidate(errorMessage: "Failed to create request body.")
                        return
                    }

                    // Get the host and port from UserDefaults
                    let host = UserDefaults.standard.string(forKey: "host") ?? "default.host"
                    let port = UserDefaults.standard.string(forKey: "port") ?? "8080"

                    // Construct the URL
                    guard let url = URL(string: "http://\(host):\(port)") else {
                        session.invalidate(errorMessage: "Invalid host or port.")
                        return
                    }

                    // Create the HTTP request
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = httpBody

                    // Perform the HTTP request
                    let urlSession = URLSession.shared
                    let task = urlSession.dataTask(with: request) { data, response, error in
                        if let error = error {
                            session.invalidate(errorMessage: "Request failed: \(error.localizedDescription)")
                            return
                        }

                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            session.alertMessage = "Request succeeded."
                        } else {
                            session.invalidate(errorMessage: "Request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                        }
                    }
                    task.resume()
                }
            }
        }
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
