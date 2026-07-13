# FRSH nearby: production authentication setup

This project should use one Firebase Authentication user identity for email,
Google, Facebook, and Apple. Store FRSH profile and business data in Cloud
Firestore, and profile photos in Cloud Storage.

## Architecture

- **Firebase Authentication:** passwords and social identity providers.
- **Cloud Firestore:** consumer, producer, and registered-business profiles.
- **Cloud Storage:** profile and business images.
- **Cloud Functions or another trusted server:** business verification, admin
  actions, custom claims, emails, and any operation requiring secrets.

Never store Facebook secrets, Apple private keys, Firebase service-account keys,
or admin credentials inside the Flutter app. `firebase_options.dart`,
`google-services.json`, and `GoogleService-Info.plist` identify Firebase apps but
do not grant Firebase Admin access.

## 1. Accounts required

Create or obtain access to:

1. A Google account and Firebase project.
2. A Meta for Developers account and Meta app for Facebook Login.
3. A paid Apple Developer Program account for Sign in with Apple.

The existing Android application ID and Apple bundle ID are both:

```text
com.frshnearby.app
```

Do not change this after production OAuth applications have been registered.

## 2. Install command-line tools

```bash
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
flutter pub get
```

From this repository, connect Android, iOS, and Web to the same Firebase project:

```bash
flutterfire configure --platforms=android,ios,web
```

This generates `lib/firebase_options.dart` and the platform configuration. Run
`flutterfire configure` again whenever a Firebase product or platform is added.

## 3. Initialize Firebase

After `firebase_options.dart` exists, change `main()` to initialize Firebase
before `runApp`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const FrshNearbyApp());
}
```

Do not add this before running `flutterfire configure`, otherwise the project will
not compile because `firebase_options.dart` will not exist.

## 4. Enable Firebase Authentication providers

In Firebase Console, open **Build > Authentication > Sign-in method** and enable:

- Email/Password
- Google
- Facebook
- Apple

Set a support email and configure the email templates. Add production and staging
web domains under **Authentication > Settings > Authorized domains**. Do not leave
temporary preview domains authorized after they are no longer used.

## 5. Google setup

### Android

Add both debug and release SHA-1 and SHA-256 fingerprints in Firebase Console:

```bash
cd android
./gradlew signingReport
```

Then download the refreshed `google-services.json` or run
`flutterfire configure` again. Release fingerprints must match the Play App
Signing certificate when Play manages the production signing key.

### iOS

Register `com.frshnearby.app` in the Firebase project. FlutterFire normally adds
the Firebase configuration, but verify the reversed Google client ID URL scheme
required by the generated iOS configuration.

### Web

Add every real deployment host to Firebase Authorized Domains. Use Firebase Auth
popup/redirect on web; native Android/iOS use `google_sign_in` to obtain the Google
ID token and exchange it for a Firebase credential.

## 6. Facebook setup

1. Create a Meta app at Meta for Developers and add **Facebook Login**.
2. Add Android package `com.frshnearby.app` and its key hashes.
3. Add iOS bundle ID `com.frshnearby.app`.
4. Copy the Meta App ID and App Secret into the Facebook provider in Firebase
   Authentication. The App Secret belongs only in Firebase/Meta consoles.
5. Copy Firebase's OAuth redirect URI, normally
   `https://YOUR_PROJECT.firebaseapp.com/__/auth/handler`, into Meta's valid OAuth
   redirect URIs.
6. Complete the Android manifest and iOS URL-scheme setup required by
   `flutter_facebook_auth` before launching the app. The plugin can prevent other
   Android plugins from registering when its native configuration is missing.
7. While the Meta app is in Development mode, only app admins/developers/testers
   can sign in. Complete App Review and switch it Live before public release.

Request only `email` and `public_profile` unless another permission is genuinely
needed and approved.

## 7. Apple setup

1. In Apple Developer **Certificates, Identifiers & Profiles**, open the App ID
   for `com.frshnearby.app` and enable **Sign in with Apple** as the primary App ID.
2. In Xcode, open `ios/Runner.xcworkspace`, select the Runner target, and add the
   **Sign in with Apple** capability under Signing & Capabilities.
3. For web/Android Apple login, create an Apple **Services ID**, associate it with
   the primary App ID, and configure the Firebase callback domain/return URL.
4. Create a Sign in with Apple private key. Enter the Services ID, Team ID, Key ID,
   and private key in Firebase's Apple provider configuration. Never commit the
   `.p8` key.
5. Register Firebase's Apple auth handler as the return URL.
6. Configure Apple's private-email relay if FRSH sends email to users who select
   **Hide My Email**.

Firebase Auth can use `AppleAuthProvider` directly, so this project does not need
the separate `sign_in_with_apple` package for the standard Firebase flow.

## 8. Email/password behavior

- Registration: `createUserWithEmailAndPassword`.
- Login: `signInWithEmailAndPassword`.
- Password reset: `sendPasswordResetEmail`.
- Send email verification after registration.
- Do not create a second Firebase user when the email already belongs to another
  provider. Ask the user to sign in with the existing provider, then link the new
  credential using Firebase account linking.
- Show generic login failure text instead of revealing whether an email exists.

## 9. FRSH Firestore data model

Use the Firebase UID as the document ID:

```text
users/{uid}
  email
  fullName
  phone
  photoUrl
  roles: [consumer, producer] | [consumer, business] | ...
  onboardingComplete
  createdAt
  updatedAt

publicProfiles/{uid}
  displayName
  introduction
  photoUrl
  sellerType: producer | business
  verificationStatus: draft | pending | approved | rejected

businessProfiles/{uid}
  businessName
  farmName
  businessId
  vatNumber
  businessType
  address
  city
  zipCode
```

`businessProfiles` contains private verification information and must not be used
as the public storefront document. Consumer can coexist with producer or business;
producer and business remain mutually exclusive in both client validation and
server-side rules.

## 10. Minimum Firestore security rules

Start deny-by-default. A user may manage their own private documents. Public
profiles should be readable only when publication rules allow it. Approval state
must be changed only by trusted server/admin code, not directly by the app.

```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() {
      return request.auth != null;
    }

    function owns(uid) {
      return signedIn() && request.auth.uid == uid;
    }

    match /users/{uid} {
      allow create, read, update, delete: if owns(uid);
    }

    match /businessProfiles/{uid} {
      allow create, read, update: if owns(uid);
      allow delete: if false;
    }

    match /publicProfiles/{uid} {
      allow read: if resource.data.verificationStatus == 'approved' || owns(uid);
      allow create: if owns(uid)
        && request.resource.data.verificationStatus == 'draft';
      allow update: if owns(uid)
        && request.resource.data.verificationStatus == resource.data.verificationStatus;
      allow delete: if false;
    }

    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

These are baseline rules, not the final marketplace rules. Add explicit field
allowlists and type validation before production.

## 11. Authentication flow in the app

1. Initialize Firebase.
2. Listen to `FirebaseAuth.instance.authStateChanges()` at the app root.
3. Signed out: display `AuthScreen`.
4. Signed in: read `users/{uid}`.
5. Missing document or `onboardingComplete == false`: show role/profile onboarding.
6. Completed profile: open the main app.
7. On first social sign-in, prefill name, email, and photo, but let the user review
   public display information.
8. Write profile documents in a Firestore batch and mark onboarding complete last.

Every social button needs loading, cancellation, provider error, offline, and
account-linking states. Never treat a cancelled provider dialog as an error toast.

## 12. Production checklist

- Separate Firebase projects for development/staging and production.
- Enable App Check after authentication works.
- Enable Firebase budget alerts and usage monitoring.
- Test account linking across email, Google, Facebook, and Apple.
- Test Apple Hide My Email and users who provide their name only once.
- Test Android release signing, iOS TestFlight, and deployed web domains—not only
  debug builds.
- Add account deletion in the app. Revoke Apple tokens during Apple account
  deletion and delete/private-anonymize related Firestore and Storage data.
- Publish Privacy Policy and Terms URLs before Meta/Apple production review.
- Store business verification decisions in trusted server-controlled fields.
