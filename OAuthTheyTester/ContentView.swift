//
//  ContentView.swift
//  OAuthTheyTester
//
//  Created by Nate Rivard on 10/14/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import OAuthThey
import SwiftUI

struct ContentView: View {

    let client = Client(consumerKey: "HHGwPKlApSinjJeCUtPx", consumerSecret: "CqAXZitUyfQbqcppOffnQOawzLOpFkqs", userAgent: "Record Holder/1.2.1.1")

    var body: some View {
        Text("Hello World")
            .onAppear {
                if !self.client.isAuthenticated {
                    let authRequest: Client.AuthRequest = .init(
                        requestURL: URL(string: "https://api.discogs.com/oauth/request_token")!,
                        authorizeURL: URL(string: "https://www.discogs.com/oauth/authorize")!,
                        accessTokenURL: URL(string: "https://api.discogs.com/oauth/access_token")!,
                        window: UIApplication.shared.keyWindow!
                    )

                    self.client.startAuthorization(with: authRequest) { result in
                        do {
                            let token = try result.get()
                            print(token)
                        } catch {
                            print(error)
                        }
                    }
                }

            }
            .onTapGesture {
                self.client.logout()
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
