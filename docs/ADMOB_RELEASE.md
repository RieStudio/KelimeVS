# AdMob Release Yapılandırması

Uygulama geliştirme (debug/profile) modunda otomatik olarak Google'ın test kimliklerini kullanır.
Release derlemelerinde gerçek AdMob kimlikleri verilene kadar **kill-switch** (`AdConfig.isAdsEnabled`) reklam SDK'sını ve UMP onay akışını otomatik olarak devre dışı bırakır.

## 1. Android App ID (`ADMOB_APP_ID`)

`flutter build` komutu Gradle'a `-P` bayrağı iletmeyi desteklemediği için Android `APPLICATION_ID` değeri git'e girmeyen şu iki yoldan biriyle okunur:

1. **`app/android/admob.properties`** (önerilen):
   `app/android/admob.properties.example` dosyasını `app/android/admob.properties` olarak kopyalayıp gerçek kimliği yazın (`.gitignore` içindedir, git'e eklenmez):
   ```properties
   ADMOB_APP_ID=ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY
   ```
2. **Ortam değişkeni:** `ADMOB_APP_ID=ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY`

> **Güvenlik Koruması:** Release (`assembleRelease` / `bundleRelease`) derlemesinde `--dart-define=ADMOB_ENABLED=true` (veya reklam birimi kimlikleri) verilmiş ancak geçerli bir gerçek `ADMOB_APP_ID` tanımlanmamışsa Gradle derlemeyi **hata ile durdurur**; sessizce test kimliğine düşmez. Reklamsız release derlemesi için `--dart-define=ADMOB_ENABLED=false` kullanın.

## 2. Gerçek Kimliklerle Release Derleme Komutu

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXXXXXXXXXXXXXXX/BBBBBBBBBB \
  --dart-define=ADMOB_REWARDED_ID=ca-app-pub-XXXXXXXXXXXXXXXX/RRRRRRRRRR \
  --dart-define=ADMOB_ENABLED=true
```

## 3. Kill-Switch Davranışı

Aşağıdaki durumlardan biri geçerliyse release derlemesinde reklamlar tamamen kapalı kalır:
- `ADMOB_ENABLED=false` verilmişse
- `ADMOB_BANNER_ID` veya `ADMOB_REWARDED_ID` boşsa
- Kimliklerden biri Google test kimliği (`ca-app-pub-3940256099942544...`) içeriyorsa
