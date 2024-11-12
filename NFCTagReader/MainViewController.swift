import UIKit
import CoreNFC
import Foundation

class MainViewController: UIViewController, NFCNDEFReaderSessionDelegate {

    // MARK: - Properties

    let reuseIdentifier = "reuseIdentifier"
    var detectedMessages = [NFCNDEFMessage]()
    var session: NFCNDEFReaderSession?

    /// - Tag: beginScanning
    @IBAction func beginScanning(_ sender: Any) {
        self.startNFCSession()
    }

    func startNFCSession() {
        guard NFCNDEFReaderSession.readingAvailable else {
            // TODO: Perhaps this needs to be in the main thread as well?
            self.presentAlert(title: "Scanning Not Supported", message: "This device doesn't support tag scanning.")
            return
        }

        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Start looking for treasure!"
        session?.begin()
    }

    /// - Tag: processingTagData
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        DispatchQueue.main.async {
            self.detectedMessages.append(contentsOf: messages)
        }
    }

    /// - Tag: processingNDEFTag
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            print("Could not get first tag")
            // self.restartPolling(session) // TODO: Maybe need this??
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("Error found when connecting to tag \(error)")
                return
            }

            tag.queryNDEFStatus { ndefStatus, _, error in
                if ndefStatus == .notSupported || error != nil {
                    print("NFC tags not supported")
                    return
                }

                self.parseTag(for: tag) { [weak self] extractedId, error in
                    guard let self = self else { return }
                    if let error = error {
                        print("Error found when trying to parse tag \(error)")
                        return
                    }

                    guard let extractedId = extractedId else {
                        print("Could not get ID from tag")
                        return
                    }

                    let host = UserDefaults.standard.string(forKey: "host") ?? "default.host"
                    let port = UserDefaults.standard.string(forKey: "port") ?? "8080"
                    let responsibility = UserDefaults.standard.string(forKey: "responsibility") ?? "unknown"
                    let requestBody: [String: String] = ["role": responsibility, "id": String(extractedId)]

                    guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: []) else {
                        print("Error JSON serializing body")
                        return
                    }

                    guard let url = URL(string: "http://\(host):\(port)") else {
                        print("Error constructing URL")
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = httpBody

                    URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                        guard self != nil else { return }
                        // Always switch back to the main thread for UI updates or NFC session calls
                        DispatchQueue.main.async {
                            if error != nil {
                                print("Error sending HTTP request: \(error!.localizedDescription)")
                                return
                            }

                            if let httpResponse = response as? HTTPURLResponse {
                                if httpResponse.statusCode != 200 {
                                    print("HTTP request did not return 200: \(httpResponse.statusCode)")
                                }
                            }
                        }
                    }.resume()
                }
            }
        }
        self.restartPolling(session)
    }
    
    private func restartPolling(_ session: NFCNDEFReaderSession) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            guard session == self.session else {
                print("Session is invalidated, skipping restartPolling")
                return
            }
            session.restartPolling()
        }
    }

    private func presentAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    func parseTag(for tag: NFCNDEFTag, completion: @escaping (Int?, Error?) -> Void) {
        tag.readNDEF { message, error in
            if let error = error {
                completion(nil, error)
                return
            }

            guard let message = message, let record = message.records.first else {
                completion(nil, NSError(domain: "NFCError", code: 1001, userInfo: [NSLocalizedDescriptionKey: "No valid data found on NFC tag."]))
                return
            }

            if let payloadString = String(data: record.payload, encoding: .utf8),
               let jsonData = payloadString.data(using: .utf8),
               let payloadDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let extractedId = payloadDict["id"] as? Int {
                completion(extractedId, nil)
            } else {
                completion(nil, NSError(domain: "NFCError", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to parse payload or extract ID."]))
            }
        }
    }
    
    /// - Tag: sessionBecomeActive
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        
    }
    
    /// - Tag: endScanning
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError, readerError.code == .readerSessionInvalidationErrorSessionTimeout {
            print("Session timeout, restarting after 0.5 seconds..")
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                self.startNFCSession()
            }
            return
        }
        
        if let readerError = error as? NFCReaderError, readerError.code != .readerSessionInvalidationErrorUserCanceled {
            print("Some other session error \"\(error.localizedDescription)\", restarting after 0.5 seconds..")
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                self.startNFCSession()
            }
            return
        }
    }

    // MARK: - addMessage(fromUserActivity:)
    func addMessage(fromUserActivity message: NFCNDEFMessage) {
        DispatchQueue.main.async {
            self.detectedMessages.append(message)
        }
    }
}
