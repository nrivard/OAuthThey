# OAuthThey

![alt text](OAuthTheyHeader.png "Max Fischer image pun")

OAuthThey is a single purpose OAuth 1.0a implementation, specifically for use with Discogs.
It features modern Swift conventions and types, like the new concurrency model, and utilizes the latest Apple APIs, like the more modern `ASWebAuthenticationSession`, for presenting web UI.

## Getting Started

OAuthThey uses the Swift Package Manager.
To include it in your project, just add it as a swift package dependency in XCode and `import OAuthThey` in any files that need to use it.

```swift
dependencies: [
    .package(url: "git@bitbucket.org:nrivard/oauththey.git", .upToNextMajor(from: "1.0.0")),
],
```

## Using OAuthThey

### The Client

All of your interactions with OAuth center around `Client`.
This type is responsible for starting the authorization flow, authenticating requests, and discarding authorization tokens when a user wants to sign out.
Because `Client` is an `actor`, all of your interactions with it are `async`.
 
To start the authentication flow using OAuth 1.0a, first create your `Client.Configuration` and provide it to `Client(configuration:)`:

```swift
let config = Client.Configuration(
    consumerKey: consumerKey,
    consumerSecret: consumerSecret,
    userAgent: "OAuthTheyTester/1.0",
    keychainServiceKey: "OAuthTheyTester"
)

let client = Client(configuration: config)
```

### Requesting Authorization

Next, create your `AuthRequest` and provide an `ASPresentationAnchor` to present web UI from.
OAuthThey provides `Platform.currentWindow` which is a convenience for getting the current window on iOS and macOS.  

```swift
let authRequest = Client.AuthRequest(
    requestURL: URL(string: DiscogsOAuthEndpoints.requestURL)!,
    authorizeURL: URL(string: DiscogsOAuthEndpoints.authURL)!,
    accessTokenURL: URL(string: DiscogsOAuthEndpoints.accessToken)!,
    window: PlatformApplication.currentWindow // if you haven't specified this on the `MainActor`, you may need to `await`
)
```

Now call `startAuthorization` with your request on `Client`. 
This call is `async` and returns a `Token` (which you can safely discard) so you can call this on any `Task`.
If authorization is successful, the valid `Token` will automatically be persisted to the Keychain using the given `keychainServiceKey` provided in the `Configuration`.

```swift
Task {
    do {
        // you will never need to directly hold onto or interact with the returned `Token` but it's provided
        // in case you want to display the key or secret for some specialized reason
        let _ = try await client.startAuthorization(with: authRequest)
    } catch {
        print(error)
    }
}
```

### Restoring Authorization

When creating a `Client`, if a valid `Token` is found in the Keychain, it will automatically start in an authenticated state.
You can query this state to avoid going through the authorization flow again:

```swift
if await client.isAuthenticated {
    // already a valid client
} else {
    // start auth flow
}
```

### Signing Requests

Now that you're authenticated, you simply need to sign each request:

```swift
let request = URLRequest(url: Discogs.searchEndpoint)
await client.authorizeRequest(&request)
```

OAuthThey will automatically include the proper OAuth headers on your request as well as `User-Agent`.
You are responsible for `Content-Type`,  `Accepts`, and any other headers your service may require.

### Logging Out

Cleaning up when a user wants to log out is easy as well, including removing the persisted `Token` from the `Keychain`:

```swift
await client.logout()
```

### Test Application

Included is a barebones test application, OAuthTheyTester, that you can use as a springboard for your own OAuth authentication.
You will need to fill out your own Discogs `consumerKey` and `consumerSecret` in `ContentView` if you want to test it.

## Notes

OAuthThey currently only supports `PLAINTEXT` signature methods and does not support expired tokens or other advanced OAuth features.
This is a very barebones approach to OAuth for use with Discogs.
