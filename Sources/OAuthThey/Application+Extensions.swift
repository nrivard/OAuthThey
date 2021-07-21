//
//  Application+Extension.swift
//  
//
//  Created by Nate Rivard on 05/07/2021.
//

#if canImport(UIKit)

import UIKit

public typealias PlatformApplication = UIApplication

extension UIApplication {

    @available(iOSApplicationExtension, unavailable)
    public static var currentWindow: UIWindow {
        shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })!
    }
}

#elseif canImport(Cocoa)

import Cocoa

public typealias PlatformApplication = NSApplication

extension NSApplication {

    public static var currentWindow: NSWindow {
        return shared.keyWindow!
    }
}

#endif
