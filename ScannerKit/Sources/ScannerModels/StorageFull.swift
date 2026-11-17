import Foundation

extension Error {
    /// Whether a write failed because there is no space left, as the system says either way.
    var isStorageFull: Bool {
        let error = self as NSError
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), (NSPOSIXErrorDomain, Int(ENOSPC)): return true
        default: return (error.userInfo[NSUnderlyingErrorKey] as? any Error)?.isStorageFull ?? false
        }
    }
}
