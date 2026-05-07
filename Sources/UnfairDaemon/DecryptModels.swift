import Vapor

struct DecryptUpload: Content {
    var ipa: File?
    var url: String?
    var ipaURL: String?

    enum CodingKeys: String, CodingKey {
        case ipa
        case url
        case ipaURL = "ipa_url"
    }

    var sourceURLString: String? {
        ipaURL ?? url
    }
}

struct DecryptResponse: Content {
    let exit: DecryptExit
}

struct DecryptExit: Content {
    let code: Int32
    let stdout: String
    let stderr: String
    let downloadURL: String
    let validateUntil: Int

    enum CodingKeys: String, CodingKey {
        case code
        case stdout
        case stderr
        case downloadURL = "download_url"
        case validateUntil = "validate_until"
    }
}

struct DecryptJobMetadata: Codable {
    let validateUntil: Int

    enum CodingKeys: String, CodingKey {
        case validateUntil = "validate_until"
    }
}
