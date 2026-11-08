import Foundation
import ObjectiveC
import Darwin
import UIKit

/// Best-effort SpringBoard respring, following the same private-framework path
/// that TrollStore uses. Works when the app has enough privileges (TrollStore,
/// platform-application entitlement). On a plain certificate-signed build the
/// system may deny the request; the caller shows a clear message in that case.
enum Respring {
    @discardableResult
    static func perform() -> Bool {
        if respringViaSpringBoardServices() { return true }
        if killSpringBoard() { return true }
        return false
    }

    // MARK: SBSRelaunchAction + FBSSystemService

    private static func respringViaSpringBoardServices() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW),
              let symbol = dlsym(handle, "SBSRelaunchAction") else {
            return false
        }

        typealias MakeAction = @convention(c) (CFString, CFString, UInt32) -> Unmanaged<AnyObject>?
        let makeAction = unsafeBitCast(symbol, to: MakeAction.self)
        guard let action = makeAction("restartRenderServer" as CFString,
                                      "TrollSign" as CFString,
                                      0)?.takeUnretainedValue() else {
            return false
        }

        guard let cls = NSClassFromString("FBSSystemService") else { return false }

        let sharedSelector = NSSelectorFromString("sharedService")
        guard let sharedMethod = class_getClassMethod(cls, sharedSelector) else { return false }
        typealias SharedService = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
        let shared = unsafeBitCast(method_getImplementation(sharedMethod), to: SharedService.self)
        guard let service = shared(cls, sharedSelector)?.takeUnretainedValue() else { return false }

        let sendSelector = NSSelectorFromString("sendActions:withResult:withError:")
        guard let sendMethod = class_getInstanceMethod(cls, sendSelector) else { return false }
        typealias SendActions = @convention(c) (AnyObject, Selector, NSSet, AnyObject?, AnyObject?) -> Void
        let send = unsafeBitCast(method_getImplementation(sendMethod), to: SendActions.self)
        send(service, sendSelector, NSSet(object: action), nil, nil)
        return true
    }

    // MARK: killall SpringBoard

    private static func killSpringBoard() -> Bool {
        var pid: pid_t = 0
        var arguments: [UnsafeMutablePointer<CChar>?] = ["killall", "-9", "SpringBoard"].map { argument in
            argument.withCString { strdup($0) }
        }
        arguments.append(nil)
        defer {
            for pointer in arguments {
                if let pointer { free(pointer) }
            }
        }

        let result = arguments.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(&pid, "/usr/bin/killall", nil, nil, buffer.baseAddress, environ)
        }
        return result == 0
    }
}
