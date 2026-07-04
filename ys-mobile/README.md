# YS Mobile

Flutter client rieng cho YS Chat. App nay dung lai backend `ys-web-api`; khong co Capacitor va khong viet lai backend.

## Chuan bi

Sau khi cai Flutter SDK, chay:

```bash
cd ys-mobile
flutter create --platforms android,ios --org com.tythac .
flutter pub get
```

Lenh `flutter create ... .` se sinh wrapper Android/iOS xung quanh source `lib/` hien co.

## Chay app

Neu gap `No supported devices connected`, Flutter dang thay Windows/Chrome nhung project nay moi sinh Android/iOS. Hay mo Android emulator hoac cam dien thoai Android:

```bash
flutter emulators
flutter emulators --launch <emulator_id>
flutter devices
flutter run -d <android_device_id> --dart-define=YS_API_URL=http://10.0.2.2:3666/api/v1
```

Android emulator goi backend local cua may host qua `10.0.2.2`:

```bash
flutter run --dart-define=YS_API_URL=http://10.0.2.2:3666/api/v1
```

Thiet bi that trong LAN hien tai dung IP may chay backend:

```bash
flutter run --dart-define=YS_API_URL=http://192.168.71.87:3666/api/v1
```

Voi dien thoai Android that trong LAN, dung IP may chay backend thay vi `10.0.2.2`, vi `10.0.2.2` chi danh cho Android emulator:

```bash
flutter run -d <android_device_id> --dart-define=YS_API_URL=http://192.168.x.x:3666/api/v1
```

Windows/Chrome trong log la platform desktop/web, khong phai mobile target cua app nay. App hien tai tap trung Android/iOS va dung `dart:io` cho file/voice upload, nen hay dung emulator hoac thiet bi Android/iOS de chay.

## Build APK cho nut tai tren web

Trang dang nhap `ys-web` da tro nut tai Android toi:

```text
/downloads/YSChat.apk
```

Build APK Flutter va copy sang dung thu muc public cua web:

```powershell
cd "D:\Ty Thac Project\YS chat\ys-mobile"
.\scripts\build-apk-for-web.cmd -ApiUrl "http://192.168.71.87:3666/api/v1"
```

File se duoc copy thanh:

```text
..\ys-web\public\downloads\YSChat.apk
```

Sau do build/deploy web nhu binh thuong:

```powershell
cd "D:\Ty Thac Project\YS chat\ys-web"
npm.cmd run build
```

APK hien dang cho phep HTTP cleartext de dung backend noi bo `192.168.71.87`. Khi dua ra ngoai LAN, nen chuyen `-ApiUrl` sang HTTPS/domain that va tat cleartext neu co the.

## Push notification

Backend da co endpoint `POST /api/v1/chat/devices` va Firebase sender. Flutter app se tu dang ky FCM token neu Firebase duoc cau hinh.

Can lam sau khi sinh wrapper:

- Android: them `android/app/google-services.json`, cau hinh Gradle theo Firebase Flutter docs.
- iOS: them `ios/Runner/GoogleService-Info.plist`, bat Push Notifications va Background Modes trong Xcode.

Neu chua co Firebase config, app van chay chat realtime/upload binh thuong; push token registration se duoc bo qua an toan.
