<p align="center">
  <img src="art/icon_512.png" width="120" alt="安裝大師" />
</p>

<h1 align="center">安裝大師</h1>

<p align="center">一款簡單好用的 Android 安裝包安裝器，支援分割 APK 與多種常見格式。</p>

<p align="center">繁體中文介面・支援 Android 7.0 ～ Android 16</p>

---

## 功能特色

- 📦 **多格式支援**：`APK`、`APKM`、`XAPK`、`APKS`，以及含分割包的 `ZIP`
- 🧩 **分割包自動選擇**：依裝置的 CPU 架構、螢幕密度與語言自動勾選合適的分割包，也可以手動調整
- 🎮 **XAPK 資源檔**：自動複製 OBB 資源檔，含進度顯示
- 📚 **批次安裝**：一次選取多個安裝包，依序自動安裝
- 🔍 **安裝前檢查**：自動比對版本（全新安裝／更新／降級）、偵測簽章衝突與系統版本需求，問題會在安裝前提醒
- 💬 **清楚的錯誤說明**：安裝失敗時以中文說明原因，並提供處理建議
- 🗂️ **應用管理**：檢視已安裝的應用，可搜尋、開啟、解除安裝
- 📤 **APK 匯出**：將已安裝的應用匯出為 `.apk`（含分割包的應用匯出為 `.apks`，可再次安裝）
- 🕘 **安裝歷史**：保留安裝與解除安裝紀錄
- 🔔 **完成通知**：安裝結果以系統通知提醒
- 📁 **與檔案管理器整合**：在檔案管理器直接點擊安裝包、或「分享」給安裝大師即可安裝

## 系統需求

Android 7.0（API 24）及以上版本。

## 使用方式

三種方式任選：

1. 開啟安裝大師，點「**選擇安裝包**」挑選檔案（可多選）；
2. 在任何檔案管理器中**直接點擊**安裝包檔案，選擇以安裝大師開啟；
3. 從其他應用把安裝包「**分享**」給安裝大師。

首次使用時，依畫面指引完成「安裝未知應用程式」授權即可。安裝含 OBB 資源檔的 XAPK 時，會另外請求儲存空間權限。

## 權限說明

| 權限 | 用途 |
| --- | --- |
| 安裝／解除安裝應用 | 安裝器的核心功能 |
| 儲存空間 | 讀取安裝包、寫入 OBB 資源檔 |
| 通知 | 顯示安裝結果 |
| 查詢已安裝應用 | 版本比對、應用管理與匯出 |

所有權限僅用於上述功能，本應用**不連網、不收集任何資料**。

## 常見問題

**Q：安裝 XAPK 時提示 OBB 複製失敗？**
較新版本的 Android（13+）系統限制第三方應用寫入 `Android/obb` 目錄，這是系統層限制；APK 本體仍會正常安裝。

**Q：提示「無法降級安裝」？**
Android 系統不允許安裝比現有版本更舊的版本。可依畫面提示先解除安裝舊版，再進行安裝。

**Q：提示「簽章衝突」？**
安裝包與已安裝版本由不同的金鑰簽署。需先解除安裝原版本才能繼續（原應用資料會遺失，請留意備份）。

## 自行構建

本專案以 [Flutter](https://flutter.dev) 開發。

### 本機構建

需求：Flutter SDK（stable）、Android SDK（含 API 36）、JDK 17 以上。

```bash
flutter pub get
flutter build apk --release
```

產物為未簽名的 APK：`build/app/outputs/flutter-apk/app-release.apk`。

### GitHub Actions 構建

本倉庫提供**手動觸發**的構建流程（不會自動執行）：到 **Actions → 構建未簽名正式版 APK → Run workflow** 觸發，完成後於該次執行的 **Artifacts** 下載 `app-release-unsigned`。

### 簽名

構建產物未簽名，發佈前請自行簽名：

```bash
keytool -genkeypair -v -keystore release.jks -alias release \
  -keyalg RSA -keysize 4096 -validity 10000

zipalign -p 4 app-release.apk app-release-aligned.apk
apksigner sign --ks release.jks --out app-release-signed.apk app-release-aligned.apk
```

## 聲明

本應用僅供安裝您擁有合法使用權的應用程式。安裝來源不明的應用程式可能危害裝置安全，請務必確認來源可信。
