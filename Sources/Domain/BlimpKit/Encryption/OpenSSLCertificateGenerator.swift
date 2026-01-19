import Foundation
import Corredor
import ProvisioningAPI

public struct OpenSSLCertificateGenerator: CertificateGenerating {
    public init() {}
    
    public func generateCSR() throws -> (String, Data) {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        let csrPath = tempDir.appendingPathComponent("\(uuid).csr")
        let keyPath = tempDir.appendingPathComponent("\(uuid).key")
        
        // Use Shell.command
        let cmd = "openssl req -new -newkey rsa:2048 -nodes -out \(csrPath.path) -keyout \(keyPath.path) -subj \"/CN=Blimp\""
        _ = try Shell.command(cmd).run()
        
        let csrData = try Data(contentsOf: csrPath)
        let keyData = try Data(contentsOf: keyPath)
        
        let csrString = String(data: csrData, encoding: .utf8) ?? ""
        
        // Cleanup
        try? FileManager.default.removeItem(at: csrPath)
        try? FileManager.default.removeItem(at: keyPath)
        
        return (csrString, keyData)
    }
    
    public func generateP12(certContent: Data, privateKey: Data, passphrase: String) throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        let certPath = tempDir.appendingPathComponent("\(uuid).cer")
        let keyPath = tempDir.appendingPathComponent("\(uuid).key")
        let p12Path = tempDir.appendingPathComponent("\(uuid).p12")

        try certContent.write(to: certPath)
        try privateKey.write(to: keyPath)

        let cmd = "openssl pkcs12 -export -inkey \(keyPath.path) -in \(certPath.path) -out \(p12Path.path) -passout pass:\(passphrase)"
        _ = try Shell.command(cmd).run()

        let p12Data = try Data(contentsOf: p12Path)

        // Cleanup
        try? FileManager.default.removeItem(at: certPath)
        try? FileManager.default.removeItem(at: keyPath)
        try? FileManager.default.removeItem(at: p12Path)

        return p12Data
    }
}
