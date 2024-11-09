import UIKit

class ConfigurationViewController: UIViewController {
    @IBOutlet weak var hostTextField: UITextField!
    @IBOutlet weak var portTextField: UITextField!
    @IBOutlet weak var responsibilityTextField: UITextField!
    @IBOutlet weak var currentHostLabel: UILabel!
    @IBOutlet weak var currentPortLabel: UILabel!
    @IBOutlet weak var currentResponsibilityLabel: UILabel!


    override func viewDidLoad() {
        super.viewDidLoad()
        loadSavedValues()
    }

    func loadSavedValues() {
            let host = UserDefaults.standard.string(forKey: "host") ?? "Not set"
            let port = UserDefaults.standard.string(forKey: "port") ?? "Not set"
            let responsibility = UserDefaults.standard.string(forKey: "responsibility") ?? "Not set"

            currentHostLabel.text = "Current Host: \(host)"
            currentPortLabel.text = "Current Port: \(port)"
            currentResponsibilityLabel.text = "Current Responsibility: \(responsibility)"
        }

    @IBAction func saveButtonTapped(_ sender: UIButton) {
        guard let host = hostTextField.text, !host.isEmpty,
              let port = portTextField.text, !port.isEmpty,
              let responsibility = responsibilityTextField.text, !responsibility.isEmpty else {
            showErrorAlert("All fields are required.")
            return
        }

        // Save to UserDefaults
        UserDefaults.standard.set(host, forKey: "host")
        UserDefaults.standard.set(port, forKey: "port")
        UserDefaults.standard.set(responsibility, forKey: "responsibility")

        // Update labels
        currentHostLabel.text = "Current Host: \(host)"
        currentPortLabel.text = "Current Port: \(port)"
        currentResponsibilityLabel.text = "Current Responsibility: \(responsibility)"

        showSuccessAlert("Server configuration saved!")
    }

    func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func showSuccessAlert(_ message: String) {
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
