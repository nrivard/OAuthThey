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
    /// fill these out with your key and secret to test
    static let consumerKey = ""
    static let consumerSecret = ""

    @StateObject private var viewModel = ViewModel()

    var body: some View {
        Text(verbatim: viewModel.authStateDescription)
            .padding()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(viewModel.loginButtonText) {
                        viewModel.toggleLoginStatus()
                    }
                }
            }
    }
}

extension ContentView {
    enum AuthState: CustomStringConvertible {
        case notAuthenticated
        case authenticated(String)
        case error(Error)

        var description: String {
            switch self {
                case .notAuthenticated: return "You are not authenticated. Tap \"Login\" to get started"
                case .authenticated(let secret): return "You are authenticated and can now authorize requests using secret \(secret)"
                case .error(let error): return "An error was received:\n\(error)"
            }
        }
    }
}

extension ContentView {

    @MainActor
    class ViewModel: ObservableObject {
        @Published private(set) var authState: AuthState = .notAuthenticated

        private let client: Client

        var authStateDescription: String {
            return authState.description
        }

        var loginButtonText: String {
            if case .authenticated = authState {
                return "Logout"
            } else {
                return "Login"
            }
        }

        init() {
            let config = Client.Configuration(
                consumerKey: ContentView.consumerKey,
                consumerSecret: ContentView.consumerSecret,
                userAgent: "OAuthTheyTester/1.0",
                keychainServiceKey: "OAuthTheyTester"
            )

            client = Client(configuration: config)

            Task {
                if await client.isAuthenticated, let secret = await client.token?.secret {
                    authState = .authenticated(secret)
                }
            }
        }

        func toggleLoginStatus() {
            Task {
                if case .authenticated = authState {
                    await client.logout()
                    authState = .notAuthenticated
                    return
                }

                let request = Client.AuthRequest(
                    requestURL: URL(string: "https://api.discogs.com/oauth/request_token")!,
                    authorizeURL: URL(string: "https://www.discogs.com/oauth/authorize")!,
                    accessTokenURL: URL(string: "https://api.discogs.com/oauth/access_token")!,
                    window: PlatformApplication.currentWindow
                )

                do {
                    let token = try await client.startAuthorization(with: request)
                    authState = .authenticated(token.secret)
                } catch {
                    authState = .error(error)
                }
            }
        }
    }
}
