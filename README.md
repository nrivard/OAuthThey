# OAuthThey

![alt text](OAuthTheyHeader.png "Max Fischer pun image")

OAuthThey is a singular purpose OAuth 1.0a implementation, specifically for use with Discogs. It features modern Swift conventions and types and utilizes the latest Apple APIs, like the more modern `ASWebAuthenticationSession` for presenting web UI.

## Getting Started

OAuthThey uses the Swift Package Manager. To include it in your project, just add it as a swift package dependency in XCode and `import OAuthThey` in any files that need to use it.

## Using OAuthThey

First, create your `Client` and provide your consumer key and secret:

```
public let client: Client = .init(consumerKey: consumerKey, consumerSecret: consumerSecret, userAgent: userAgent)
```

Next, create your `AuthRequest` , provide a `UIWindow` to present web UI from, and start the authorization process:

```
let authRequest: Client.AuthRequest = .init(
    requestURL: URL(string: DiscogsOAuthEndpoints.requestURL)!,
    authorizeURL: URL(string: DiscogsOAuthEndpoints.authURL)!,
    accessTokenURL: URL(string: DiscogsOAuthEndpoints.accessToken)!,
    window: anchor
)

client.startAuthorization(with: authRequest) { authResult in
    do {
        let token: Token = try authResult.get()
    } else {
        print(error)
    }
}
```

Now that you're authenticated (the `Token` is automatically persisted to the `Keychain`), you simply need to sign each request:

```
let request = URLRequest(url: Discogs.searchEndpoint)
client.authorizeRequest(&request)
```

OAuthThey will automatically include the proper OAuth headers on your request as well as `User-Agent`. You are responsible for `Content-Type`,  `Accepts`, and any other headers your service may require.

Cleaning up when a user wants to log out is easy as well, including removing credentials from the `Keychain`:

```
client.logout()
```

That's it! You now have a fully functioning OAuth 1.0a implementation that works on any Apple platforms that support `ASWebAuthenticationSession`, like iOS (including Catalyst) and macOS.

## Notes

OAuthThey currently only supports `PLAINTEXT` signature methods and does not support expired tokens or other advanced OAuth features. This is a very barebones approach to OAuth for use with Discogs.
