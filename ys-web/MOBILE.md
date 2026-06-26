# YS Chat Mobile

## Android build

1. Copy `.env.mobile.example` to `.env.mobile`.
2. Change `VITE_API_URL` to the HTTPS domain that phones can reach, for example:

```env
VITE_API_URL=https://chat.example.com/api/v1
```

3. Build and sync Android:

```bash
npm run mobile:sync
```

4. Open Android Studio:

```bash
npm run mobile:android
```

The Android project is in `android/`.

## Push notifications

Android push requires Firebase Cloud Messaging.

Frontend:
- Put Firebase `google-services.json` at `android/app/google-services.json`.
- Re-run `npm run mobile:sync`.

Backend:
- Set one of these before starting `ys-web-api`:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/path/to/firebase-service-account.json
```

or:

```bash
FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
FIREBASE_PROJECT_ID=your-firebase-project-id
```

Without Firebase credentials, backend still runs but skips sending push notifications.

## HTTPS/domain

Mobile apps should call the API through HTTPS. Use nginx as TLS terminator and proxy to Go backend port `9999`.

Example config:

```text
deploy/nginx-https.example.conf
```

Update:
- `server_name`
- certificate paths
- backend upstream name/IP if not using `webmanager-web-api`

## iOS

iOS requires macOS and Xcode. After installing `@capacitor/ios`, run:

```bash
npx cap add ios
npx cap sync ios
npx cap open ios
```
