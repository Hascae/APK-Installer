# 安裝大師（APK Installer）

<p align="center">
  <img src="art/icon_512.png" width="128" alt="安裝大師圖示" />
</p>

功能完整的 Android 安裝包安裝器，對標並超越 APKMirror Installer。
以 **Flutter** 開發，介面語言為**繁體中文**，完整支援 **Android 7.0（API 24）～ Android 16（API 36）**。

## 功能特色

- **全格式支援**：`APK`、`APKM`（APKMirror）、`XAPK`（含 OBB）、`APKS`（SAI / bundletool）、含分割包的 `ZIP`
- **分割包（Split APK）智慧選擇**：依裝置 CPU 架構（ABI）、螢幕密度（DPI）與語言自動勾選，並可手動逐一調整
- **XAPK OBB 資源檔**：自動複製到 `Android/obb/<套件名稱>/`，含進度顯示
- **多檔批次安裝**：一次選多個安裝包，佇列依序安裝，可設定成功後自動繼續
- **安裝前完整檢查**：版本比對（全新 / 更新 / 降級）、簽章一致性偵測、minSdk 相容性檢查 —— 問題在安裝前就告訴你，而不是丟一個神祕的失敗碼
- **失敗原因中文化**：常見安裝錯誤（降級、簽章衝突、ABI 不符、空間不足、缺少分割包…）均轉譯為可理解的繁體中文說明與建議
- **應用管理**：檢視所有已安裝應用（含系統應用）、搜尋、開啟、解除安裝
- **APK 匯出**：任何已安裝應用可匯出為單一 `.apk`，含分割包者打包為 `.apks`（可用本應用直接重新安裝）
- **安裝歷史**：成功 / 失敗紀錄與原因，本機保存
- **安裝結果通知**：背景完成時發出系統通知；需要確認而無法自動喚起時提供通知備援
- **與檔案管理器整合**：在任何檔案管理器點擊安裝包、或「分享」到本應用即可直接安裝
- **自製美術資源**：應用圖示（含自適應圖示與 Android 13+ 單色主題圖示）、標誌、插畫全部自繪，不依賴系統預設

## 各 Android 版本的真實適配

| 版本 | 適配內容 |
| --- | --- |
| Android 7.0 / 7.1（API 24–25） | 「未知來源」以 `Settings.Global.INSTALL_NON_MARKET_APPS` 檢查並導向安全性設定；核心函式庫脫糖（desugaring）保證新 API 可用 |
| Android 8.0+（API 26） | `REQUEST_INSTALL_PACKAGES` + `canRequestPackageInstalls()`，逐應用「安裝未知應用程式」授權流程 |
| Android 9（API 28） | 簽章比對改用 `GET_SIGNING_CERTIFICATES` / `SigningInfo` |
| Android 10（API 29） | `requestLegacyExternalStorage` 確保 OBB 可寫入 |
| Android 11+（API 30） | 「所有檔案存取」（`MANAGE_EXTERNAL_STORAGE`）授權流程，OBB 寫入 |
| Android 12+（API 31） | `PendingIntent` 明確 `FLAG_MUTABLE`；更新可嘗試 `USER_ACTION_NOT_REQUIRED` 免確認 |
| Android 13+（API 33） | `POST_NOTIFICATIONS` 執行期申請；主題式單色圖示；`getParcelableExtra` 新 API |
| Android 14+（API 34） | 可選的 `setRequestUpdateOwnership()` 更新擁有權；廣播接收器均為非匯出 + 明確 Intent |
| Android 15 / 16（API 35–36） | `compileSdk = 36` / `targetSdk = 36`，edge-to-edge 相容 |

安裝一律走 `PackageInstaller` **session** 流程（串流寫入 + `commit`），這是分割 APK 唯一正確的安裝方式，也與系統內建安裝器走同一條路，因此穩定性與相容性等同系統級。

## 構建（純手動觸發）

本專案**不含任何 CI / 自動構建流程**，構建一律由使用者手動執行。

需求：Flutter SDK（stable，3.24 以上）、Android SDK（含 API 36 平台）、JDK 17+。

```bash
flutter pub get
flutter build apk --release
```

產物為**未簽名**的正式版 APK：

```
build/app/outputs/flutter-apk/app-release.apk
```

（`android/app/build.gradle` 的 release 組建刻意不設定 `signingConfig`，因此輸出即為未簽名 APK。）

### 之後如何簽名（自行決定）

```bash
# 產生金鑰（僅首次）
keytool -genkeypair -v -keystore release.jks -alias release \
  -keyalg RSA -keysize 4096 -validity 10000

# 對齊 + 簽名（build-tools 內附 zipalign / apksigner）
zipalign -p 4 app-release.apk app-release-aligned.apk
apksigner sign --ks release.jks --out app-release-signed.apk app-release-aligned.apk
```

## 權限說明（全部皆有對應的程式碼實作，非僅宣告）

| 權限 | 用途 |
| --- | --- |
| `REQUEST_INSTALL_PACKAGES` | 安裝應用（API 26+ 逐應用授權流程） |
| `REQUEST_DELETE_PACKAGES` | 解除安裝應用（`PackageInstaller.uninstall`） |
| `READ_EXTERNAL_STORAGE`（≤API 32） | 讀取舊制儲存空間中的安裝包 |
| `WRITE_EXTERNAL_STORAGE`（≤API 29） | 寫入 OBB 資源檔 |
| `MANAGE_EXTERNAL_STORAGE`（API 30+） | 寫入 `Android/obb`（新版系統可能仍限制，應用會如實回報） |
| `POST_NOTIFICATIONS`（API 33+） | 安裝結果通知 |
| `QUERY_ALL_PACKAGES` | 應用管理清單、版本比對、匯出功能 |

## 專案結構

```
android/                     原生層（Kotlin）
  app/src/main/kotlin/com/hascae/apkinstaller/
    MainActivity.kt          MethodChannel / EventChannel、權限、外部開檔
    InstallerEngine.kt       PackageInstaller session、OBB、匯出、快取
    ArchiveAnalyzer.kt       安裝包解析（套件資訊 / 分割分類 / 簽章）
    InstallStatusReceiver.kt 安裝狀態回呼（確認頁喚起、結果轉發）
    AppRepository.kt         已安裝應用清單
    Notifications.kt         結果通知
    EventBridge.kt           原生 → Flutter 事件橋
lib/                         Flutter 層（繁體中文 UI）
  pages/                     首頁 / 安裝流程 / 應用管理 / 歷史 / 設定 / 關於
  services/                  通道封裝 / 分割包挑選 / 設定 / 歷史
  widgets/brand.dart         自製標誌與插畫（CustomPainter）
art/                         圖示原始檔
```

## 常見問題

- **Android 13+ 無法寫入 OBB？** 系統層限制第三方寫入 `Android/obb`，本應用會嘗試並如實回報；APK 部分不受影響。
- **降級安裝失敗？** 一般 Android 系統不允許降級。應用會在安裝前偵測並提供「先解除安裝舊版」選項。
- **簽章衝突？** 安裝包與已安裝版本簽署金鑰不同時，安裝前即警告，可一鍵先移除舊版。

## 授權

僅供安裝您擁有合法使用權的應用程式。
