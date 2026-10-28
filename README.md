# ClaudeRemote iOS App

Ứng dụng iPhone viết bằng SwiftUI (iOS 16+) dùng để xem màn hình và gõ lệnh trực tiếp vào các phiên làm việc terminal Claude CLI / agy đang chạy trên PC thông qua máy chủ backend ClaudeRemote.

---

## 📁 Cấu trúc thư mục chính

```text
ClaudeRemoteApp/
├── project.yml                     # Cấu hình dự án cho XcodeGen (ghim SwiftTerm 1.20.0)
├── .github/workflows/build.yml     # GitHub Actions workflow build IPA trên macOS-15
├── App/
│   ├── App.swift                   # Điểm khởi chạy ứng dụng SwiftUI
│   ├── Assets.xcassets/            # AppIcon và tài nguyên hình ảnh
│   ├── Networking/
│   │   ├── ServerAPI.swift         # REST API client, URL WebSocket, định dạng resize JSON
│   │   └── TerminalConnection.swift# Quản lý kết nối WebSocket, tự động nối lại
│   ├── State/
│   │   ├── AppSettings.swift       # Lưu trữ URL server, Keychain token, AppStorage
│   │   ├── Keychain.swift          # Tiện ích đọc/ghi/xoá token an toàn trong Keychain
│   │   └── SessionStore.swift      # Quản lý danh sách phiên, làm mới và xoá phiên
│   └── Views/
│       ├── RootView.swift          # Điều hướng phân nhánh (chưa cấu hình -> Settings)
│       ├── SessionListView.swift   # Danh sách phiên, trạng thái chạy, tạo/xoá phiên
│       ├── NewSessionView.swift    # Sheet tạo phiên mới (tên, lệnh, thư mục)
│       ├── SettingsView.swift      # Màn hình cấu hình URL + Token và test kết nối
│       ├── TerminalScreen.swift    # Màn hình xem terminal và trạng thái kết nối
│       ├── TerminalHost.swift      # UIViewRepresentable bọc TerminalView của SwiftTerm
│       └── KeyBar.swift            # Thanh phím phụ ảo (inputAccessoryView)
└── README.md
```

---

## 🔨 Hướng dẫn BUILD

Do Windows không hỗ trợ biên dịch trực tiếp mã nguồn Swift cho nền tảng iOS, dự án được thiết lập sẵn quy trình build tự động qua GitHub Actions:

1. Đẩy toàn bộ mã nguồn lên kho chứa GitHub cá nhân.
2. Workflow tại `.github/workflows/build.yml` sẽ kích hoạt trên môi trường `macos-15`:
   - Cài đặt `xcodegen`.
   - Sinh file `.xcodeproj` từ `project.yml`.
   - Chạy `xcodebuild` không ký (`CODE_SIGNING_ALLOWED=NO`).
   - Đóng gói file `.app` thành `ClaudeRemote.ipa`.
3. Tải file IPA đã đóng gói tại mục **Artifacts** của workflow run (`ClaudeRemote-ipa`).
4. Nếu có lỗi biên dịch ở lần build đầu tiên, kiểm tra log của GitHub Actions để điều chỉnh tương thích.

---

## 📲 Hướng dẫn CÀI ĐẶT

1. Sử dụng công cụ ký ứng dụng trực tiếp trên iPhone như **ESign**, **TrollStore**, **Scarlet** hoặc **AltStore/Sideloadly**.
2. Ký file `ClaudeRemote.ipa` bằng chứng chỉ (chứng chỉ doanh nghiệp hoặc tài khoản Apple Developer cá nhân).
3. Cài đặt và mở ứng dụng trên iPhone.

---

## ⚙️ Cấu hình kết nối

1. Mở ứng dụng `ClaudeRemote` trên iPhone.
2. Nếu chưa thiết lập, ứng dụng sẽ tự động chuyển vào màn hình **Cài đặt**:
   - **URL máy chủ**: Điền địa chỉ máy chủ PC (ví dụ: `https://claude.nhaduc.name.vn` (qua Cloudflare Access, đăng nhập OTP email) hoặc IP mạng nội bộ LAN / Tailscale).
   - **Mã truy cập (Token)**: Nhập token xác thực đã thiết lập trên server PC.
3. Bấm nút **Kiểm tra kết nối** để kiểm tra máy chủ có phản hồi HTTP 200 hay không.
4. Nhấn **Lưu cài đặt** để bắt đầu sử dụng.

---

## 🌐 Giao thức kết nối & Lưu ý kỹ thuật

- **Mạng & API**:
  - `ServerAPI.swift`: Quản lý các endpoint REST (`GET /health`, `GET /sessions`, `POST /sessions`, `DELETE /sessions/:id`), gắn kèm header xác thực `Authorization: Bearer <token>`, tạo URL WebSocket (`/ws/:id?token=...`) và bản tin JSON resize terminal.
  - `TerminalConnection.swift`: Sử dụng `URLSessionWebSocketTask` để truyền nhận dữ liệu terminal hai chiều, tích hợp cơ chế exponential backoff tự động kết nối lại khi rớt mạng hoặc khi ứng dụng trở lại foreground (`willEnterForegroundNotification`).
- **Thư viện đầu cuối**: SwiftTerm được ghim cố định ở phiên bản `1.20.0` trong `project.yml`.
- **Bảo mật mạng (ATS)**: `Info.plist` đã cấu hình `NSAppTransportSecurity` với `NSAllowsArbitraryLoads = true` để cho phép kết nối HTTP/WS tới IP nội bộ và mạng riêng ảo Tailscale mà không bắt buộc chứng chỉ TLS.

---

## 🔍 Điểm cần khớp lại với server thật

Trước khi triển khai thực tế với server ClaudeRemote trên PC, cần lưu ý kiểm tra và đối chiếu các điểm sau:

1. **Định dạng `createdAt`**: Kiểm tra server trả về ngày giờ dưới dạng chuẩn chuỗi ISO 8601 (ví dụ `"2026-10-22T15:30:00Z"`) hay số timestamp unix (seconds/milliseconds) để đảm bảo decoder parse đúng.
2. **Mã lỗi HTTP**: Khớp lại mã phản hồi khi sai token (`401 Unauthorized` hay `403 Forbidden`), khi phiên không còn tồn tại (`404 Not Found`), hoặc server bận (`500/503`).
3. **Phản hồi khi tạo phiên (`POST /sessions`)**: Xác định endpoint trả về object `Session` hoàn chỉnh hay chỉ trả về ID dạng `{"id": "..."}` để `SessionStore` cập nhật danh sách mượt mà.
4. **Xử lý tín hiệu resize terminal**: Khớp cú pháp bản tin đổi kích thước giữa iOS và server (hiện iOS gửi dạng text JSON: `{"type":"resize","cols":80,"rows":24}`).
5. **WebSocket Text vs Binary**: Khớp định dạng frame dữ liệu I/O terminal. App iOS hiện gửi và nhận dữ liệu gõ phím/hiển thị màn hình qua binary frame (`Data`), còn lệnh điều khiển resize gửi qua text frame.
