import os
import UIKit
import CoreNFC
import Foundation

class MainViewController: UIViewController, NFCNDEFReaderSessionDelegate {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.stevenchu.NFCTagReader", category: "MainViewController")
    let reuseIdentifier = "reuseIdentifier"
    var detectedMessages = [NFCNDEFMessage]()
    var session: NFCNDEFReaderSession?

    /// - Tag: beginScanning
    @IBAction func beginScanning(_ sender: Any) {
        logger.info("Scan button pressed")
        if session != nil {
            logger.error("Cannot start a new session: NFC session already exists.")
            return
        }
        self.startNFCSession()
    }

    func startNFCSession() {
        guard NFCNDEFReaderSession.readingAvailable else {
            logger.error("NFC scanning not available on this device")
            DispatchQueue.main.async {
                self.presentAlert(title: "Scanning Not Supported", message: "This device doesn't support tag scanning.")
            }
            return
        }
        guard session == nil else {
            logger.error("NFC session already exists")
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
            self.logger.error("Could not get first tag")
            self.restartPolling(session)
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("Error found when connecting to tag \(error.localizedDescription)")
                return
            }

            tag.queryNDEFStatus { ndefStatus, _, error in
                if ndefStatus == .notSupported || error != nil {
                    self.logger.error("NFC tags not supported")
                    return
                }

                self.parseTag(for: tag) { [weak self] extractedId, error in
                    guard let self = self else { return }
                    if let error = error {
                        self.logger.error("Error found when trying to parse tag \(error)")
                        return
                    }

                    guard let extractedId = extractedId else {
                        self.logger.error("Could not get ID from tag")
                        return
                    }

                    let host = UserDefaults.standard.string(forKey: "host") ?? "default.host"
                    let port = UserDefaults.standard.string(forKey: "port") ?? "8080"
                    let responsibility = UserDefaults.standard.string(forKey: "responsibility") ?? "unknown"
                    let requestBody: [String: String] = ["role": responsibility, "id": String(extractedId)]

                    guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: []) else {
                        self.logger.error("Error JSON serializing body")
                        return
                    }
                    guard let url = URL(string: "http://\(host):\(port)") else {
                        self.logger.error("Error constructing URL")
                        return
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = httpBody

                    URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                        guard self != nil else { return }
                        if error != nil {
                            self?.logger.error("Error sending HTTP request: \(error!.localizedDescription)")
                            return
                        }
                        if let httpResponse = response as? HTTPURLResponse {
                            if httpResponse.statusCode != 200 {
                                self?.logger.error("HTTP request did not return 200: \(httpResponse.statusCode)")
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
                self.logger.error("Session is invalidated, skipping restartPolling")
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
        DispatchQueue.main.async {
            self.session = nil // Ensure session is cleaned up

            if let readerError = error as? NFCReaderError {
                switch readerError.code {
                case .readerSessionInvalidationErrorSessionTimeout:
                    self.logger.error("Session timeout, restarting after 0.5 seconds..")
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                        self.startNFCSession()
                    }
                case .readerSessionInvalidationErrorUserCanceled:
                    self.logger.info("Session canceled by user.")
                default:
                    self.logger.error("Session invalidated: \(readerError.localizedDescription)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                        self.startNFCSession()
                    }
                }
            } else {
                self.logger.error("Unknown session invalidation error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - addMessage(fromUserActivity:)
    func addMessage(fromUserActivity message: NFCNDEFMessage) {
        DispatchQueue.main.async {
            self.detectedMessages.append(message)
        }
    }
}
