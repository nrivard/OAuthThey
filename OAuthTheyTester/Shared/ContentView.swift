//
//  ContentView.swift
//  Shared
//
//  Created by Nate Rivard on 05/07/2021.
//

import OAuthThey
import SwiftUI
import AuthenticationServices

struct ContentView: View {
    static let consumerKey = ""
    static let consumerSecret = ""

    private let client: Client
    @State private var token: Token?

    init() {
        let config = Client.Configuration(
            consumerKey: ContentView.consumerKey,
            consumerSecret: ContentView.consumerSecret,
            userAgent: "OAuthTheyTester/1.0",
            keychainServiceKey: "OAuthTheyTester"
        )

        client = Client(configuration: config)
    }

    var body: some View {
        Text(verbatim: "Secret: " + (token?.secret ?? ""))
            .padding()
            .onReceive(client.authenticationPublisher.receive(on: DispatchQueue.main)) {
                token = $0
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(token != nil ? "Logout" : "Login") {
                        if token != nil {
                            client.logout()
                        } else {
                            startAuthorization()
                        }
                    }
                }
            }
    }

    private func startAuthorization() {
        let authRequest = Client.AuthRequest(
            requestURL: URL(string: "https://api.discogs.com/oauth/request_token")!,
            authorizeURL: URL(string: "https://www.discogs.com/oauth/authorize")!,
            accessTokenURL: URL(string: "https://api.discogs.com/oauth/access_token")!,
            window: PlatformApplication.currentWindow
        )

        async {
            do {
                try await client.startAuthorization(with: authRequest)
            } catch {
                print(error)
            }
        }
    }
}
