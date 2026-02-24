# Release Guide

Screenshot uygulamasını GitHub ve Homebrew'e yayınlama rehberi.

## Gereksinimler

- **Developer ID Application** sertifikası (Keychain'de yüklü)
- **App-Specific Password** (`xcrun notarytool store-credentials` ile kaydedilmiş)
- **gh** CLI (`brew install gh`)
- **Xcode** 15.0+

## Notarization Credentials (İlk Kurulum)

Eğer daha önce yapılmadıysa, credentials'ı Keychain'e kaydet:

```bash
xcrun notarytool store-credentials "Screenshot-Notary" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

> App-Specific Password: [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords

## Release Adımları

### 1. Kodu Commit ve Push Et

```bash
git add -A
git commit -m "Değişiklik açıklaması"
git push
```

### 2. Release Build Al (Signed + Hardened Runtime)

```bash
IDENTITY="Developer ID Application: AD SOYAD (TEAM_ID)"

xcodebuild -scheme Screenshot -configuration Release \
  -derivedDataPath /tmp/ScreenshotRelease \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=TEAM_ID \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--options runtime --timestamp" \
  clean build
```

> Sertifika adını bulmak için: `security find-identity -v -p codesigning | grep "Developer ID"`

### 3. Zip'le

```bash
VERSION="1.0.2"  # <-- Versiyon numarasını güncelle

cd /tmp/ScreenshotRelease/Build/Products/Release
ditto -c -k --keepParent Screenshot.app /tmp/Screenshot-v${VERSION}-mac.zip
```

### 4. Apple Notarization

```bash
xcrun notarytool submit /tmp/Screenshot-v${VERSION}-mac.zip \
  --keychain-profile "Screenshot-Notary" \
  --wait
```

Beklenen çıktı: `status: Accepted`

Eğer `Invalid` dönerse log'a bak:

```bash
xcrun notarytool log <SUBMISSION_ID> --keychain-profile "Screenshot-Notary"
```

### 5. Staple (Ticket'ı App'e Yapıştır)

```bash
xcrun stapler staple /tmp/ScreenshotRelease/Build/Products/Release/Screenshot.app
```

### 6. Staple Edilmiş App'i Tekrar Zip'le

```bash
rm /tmp/Screenshot-v${VERSION}-mac.zip
cd /tmp/ScreenshotRelease/Build/Products/Release
ditto -c -k --keepParent Screenshot.app /tmp/Screenshot-v${VERSION}-mac.zip
```

### 7. SHA256 Hash Al

```bash
shasum -a 256 /tmp/Screenshot-v${VERSION}-mac.zip
```

Hash'i not al — Homebrew cask'ı güncellemek için lazım.

### 8. GitHub Release Oluştur

```bash
gh release create v${VERSION} /tmp/Screenshot-v${VERSION}-mac.zip \
  --title "Screenshot v${VERSION}" \
  --notes "Release notes buraya..."
```

### 9. Homebrew Cask Güncelle

Tap repo'yu clone et (veya mevcut kopyayı kullan):

```bash
git clone git@github.com:KULLANICI/homebrew-tap.git /tmp/homebrew-tap
```

`Casks/screenshot.rb` içinde `version` ve `sha256` güncelle:

```ruby
cask "screenshot" do
  version "1.0.2"
  sha256 "YENI_SHA256_HASH"
  # ...
end
```

Commit ve push:

```bash
cd /tmp/homebrew-tap
git add -A
git commit -m "Bump screenshot to v${VERSION}"
git push
```

### 10. Doğrulama

```bash
# GitHub release kontrol
gh release view v${VERSION}

# Homebrew güncelleme testi
brew upgrade --cask screenshot

# Gatekeeper doğrulama
spctl -a -vv /Applications/Screenshot.app
# Beklenen: "source=Notarized Developer ID"
```

## Hızlı Referans

| Adım | Komut |
|------|-------|
| Build | `xcodebuild -scheme Screenshot -configuration Release ...` |
| Notarize | `xcrun notarytool submit ... --wait` |
| Staple | `xcrun stapler staple Screenshot.app` |
| SHA256 | `shasum -a 256 Screenshot-v*.zip` |
| GitHub Release | `gh release create v1.x.x file.zip --title "..."` |
| Brew Push | `Casks/screenshot.rb` → version + sha256 güncelle → push |

## Sık Karşılaşılan Hatalar

### "The signature does not include a secure timestamp"
Build komutunda `--timestamp` flag'i eksik. `OTHER_CODE_SIGN_FLAGS` kontrol et.

### "The executable requests the com.apple.security.get-task-allow entitlement"
Debug entitlement kalmış. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ekle.

### "status: Invalid" (Notarization)
Log'u kontrol et:
```bash
xcrun notarytool log <ID> --keychain-profile "Screenshot-Notary"
```

### Homebrew "sha256 mismatch"
Staple sonrası zip'i yeniden oluşturmayı unutmuş olabilirsin. Adım 6'yı tekrar yap.
