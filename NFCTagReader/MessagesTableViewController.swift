/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The view controller that scans and displays NDEF messages.
*/

import UIKit
import CoreNFC
import Foundation

/// - Tag: MessagesTableViewController
class MessagesTableViewController: UITableViewController, NFCNDEFReaderSessionDelegate {

    // MARK: - Properties

    let reuseIdentifier = "reuseIdentifier"
    var detectedMessages = [NFCNDEFMessage]()
    var session: NFCNDEFReaderSession?

    // MARK: - Actions

    /// - Tag: beginScanning
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

    // MARK: - NFCNDEFReaderSessionDelegate

    /// - Tag: processingTagData
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        DispatchQueue.main.async {
            // Process detected NFCNDEFMessage objects.
            self.detectedMessages.append(contentsOf: messages)
            self.tableView.reloadData()
        }
    }

    /// - Tag: processingNDEFTag
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        var foundError = false
        for tag in tags { // TODO (stevenchu): Consider... concurrency gasp
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
                        if let nfcError = error as NSError? {
                            if nfcError.domain == "NFCErrorDomain" && nfcError.code == 403 {
                                if .readWrite == ndefStatus {
                                    self.writeBlankNDEFTag(tag: tag) {
                                        success in
                                        if !success {
                                            foundError = true
                                            return
                                        }
                                    }
                                }
                            }
                        }
                    })

                    guard let url = URL(string: "http://10.0.0.25:8000") else {
                        foundError = true
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"

                    let urlSession = URLSession.shared
                    let task = urlSession.dataTask(with: request) { data, response, error in
                        if let error = error {
                            session.alertMessage = "Error when constructing request: \(error.localizedDescription)"
                            foundError = true
                            return
                        }
                    }
                    task.resume()
                    return
                })
            })
        }
        if foundError {
            session.invalidate()
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
            self.tableView.reloadData()
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
