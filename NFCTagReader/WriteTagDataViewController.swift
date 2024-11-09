import UIKit
import CoreNFC

class WriteTagDataViewController: UIViewController, NFCNDEFReaderSessionDelegate {

    // MARK: - Properties
    @IBOutlet weak var idTextField: UITextField!
    var session: NFCNDEFReaderSession?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    // MARK: - Actions
    @IBAction func saveDataTapped(_ sender: UIButton) {
        guard let idText = idTextField.text, let id = Int(idText), id > 0 else {
            showErrorAlert("Please enter a valid integer ID.")
            return
        }

        // Start an NFC session to write the data
        startNFCSession(with: id)
    }

    func startNFCSession(with id: Int) {
        guard NFCNDEFReaderSession.readingAvailable else {
            showErrorAlert("NFC scanning is not supported on this device.")
            return
        }

        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Ready to write data to the NFC tag. Hold your device near a tag."
        session?.begin()
    }

    // MARK: - NFCNDEFReaderSessionDelegate
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No NFC tag detected.")
            return
        }

        guard let idText = idTextField.text, let id = Int(idText) else {
            session.invalidate(errorMessage: "Invalid ID entered.")
            return
        }

        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "Failed to connect to tag: \(error.localizedDescription)")
                return
            }

            tag.queryNDEFStatus { ndefStatus, capacity, error in
                if ndefStatus == .notSupported || error != nil {
                    session.invalidate(errorMessage: "This tag does not support NDEF.")
                    return
                }

                let payloadDict = ["id": id]
                guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict, options: []) else {
                    session.invalidate(errorMessage: "Failed to create payload.")
                    return
                }

                let payload = NFCNDEFPayload(format: .nfcWellKnown, type: Data(), identifier: Data(), payload: payloadData)

                let message = NFCNDEFMessage(records: [payload])

                tag.writeNDEF(message) { error in
                    if let error = error {
                        session.invalidate(errorMessage: "Failed to write to the tag: \(error.localizedDescription)")
                        return
                    }
                    session.alertMessage = "Successfully wrote ID data to the NFC tag."
                    session.invalidate()
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let nfcError = error as? NFCReaderError {
            print("NFC Reader Error: \(nfcError.localizedDescription)")
        }
        self.session = nil
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Optional: handle detected NDEFs
        print("Detected NDEF messages: \(messages)")
    }

    // MARK: - Alerts
    func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
