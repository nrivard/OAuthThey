//
//  ClientContextProvider.swift
//  OAuthThey
//
//  Created by Nate Rivard on 10/14/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import AuthenticationServices

extension Client {

    @objc class ClientContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        let window: UIWindow

        init(window: UIWindow) {
            self.window = window
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            return window
        }
    }
}
