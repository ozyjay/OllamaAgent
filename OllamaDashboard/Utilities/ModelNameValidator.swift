import Foundation

enum ModelNameValidator {
    static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 180 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-/").inverted
        return name.rangeOfCharacter(from: allowed) == nil
    }
}
