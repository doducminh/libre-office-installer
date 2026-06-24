# LibreOffice Installer — Word → PDF cho .NET 9 API

Bộ script tự động cài đặt và cấu hình **LibreOffice** ở chế độ headless để
convert Word (`.docx`/`.doc`/`.rtf`) sang **PDF**, dùng cho .NET 9 API.

Hỗ trợ hai môi trường:

| OS | Script | Ghi chú |
|----|--------|---------|
| Windows Server + IIS | `Setup-LibreOffice.ps1` | Cài từ file `.msi`/`.exe` cùng thư mục, cấu hình IIS App Pool |
| Linux / macOS | `setup-libreoffice.sh` | Cài qua package manager (apt/dnf/yum/zypper/pacman/apk) hoặc Homebrew |

## Nội dung thư mục

```
.
├── Setup-LibreOffice.ps1               # Script cài đặt cho Windows + IIS
├── setup-libreoffice.sh                # Script cài đặt cho Linux / macOS
├── LibreOffice_26.2.3_Win_x86-64.msi   # Bộ cài LibreOffice cho Windows (offline)
└── README.md
```

> Script Windows tự dò file `LibreOffice*.msi` hoặc `LibreOffice*.exe` **cùng thư mục**.
> Muốn nâng cấp phiên bản chỉ cần thay file `.msi`/`.exe` trong thư mục này.

---

## 1. Windows Server + IIS

### Yêu cầu
- Chạy PowerShell **với quyền Administrator**.
- File cài đặt `LibreOffice*.msi` (hoặc `.exe`) nằm cùng thư mục với script.

### Cách chạy

```powershell
# Mặc định (Default Web Site / DefaultAppPool)
.\Setup-LibreOffice.ps1

# Chỉ định site và app pool cụ thể
.\Setup-LibreOffice.ps1 -SiteName "localhost:44312" -AppPoolName "localhost:44312"
```

### Tham số

| Tham số | Mặc định | Ý nghĩa |
|---------|----------|---------|
| `-SiteName` | `Default Web Site` | Tên IIS site |
| `-AppPoolName` | `DefaultAppPool` | App Pool cần bật `loadUserProfile` và cấp quyền |
| `-ProfileDir` | `C:\LibreOfficeProfiles` | Thư mục profile LibreOffice (cần ghi được) |
| `-InstallDir` | `C:\Program Files\LibreOffice` | Thư mục cài đặt LibreOffice |

### Script làm gì (6 bước)
1. Tìm file cài đặt LibreOffice (`.msi`/`.exe`) cùng thư mục.
2. Cài đặt silent (bỏ qua nếu đã cài).
3. Tạo thư mục profile + temp và cấp `FullControl` cho `IIS AppPool\<pool>`, `NETWORK SERVICE`, `LOCAL SERVICE`.
4. Thêm LibreOffice vào **System PATH**.
5. Bật `processModel.loadUserProfile = True` cho App Pool (bắt buộc để LibreOffice chạy được dưới IIS).
6. Test convert thử một file để xác nhận hoạt động.

---

## 2. Linux / macOS

### Yêu cầu
- Linux: cần quyền `root`/`sudo` để cài (trừ khi đã cài sẵn).
- macOS: nên dùng **Homebrew**, thường **không cần** `sudo`.

### Cách chạy

```bash
chmod +x setup-libreoffice.sh

# Linux — chỉ định user mà .NET app chạy dưới (để chown profile dir)
sudo ./setup-libreoffice.sh --service-user www-data

# macOS (Homebrew) — không cần sudo
./setup-libreoffice.sh
```

### Tham số / flag

| Flag | Ý nghĩa |
|------|---------|
| `--service-user <user>` | User mà .NET app chạy dưới quyền, dùng để `chown` profile dir |
| `--profile-dir <path>` | Đổi thư mục profile (mặc định theo OS) |
| `--skip-install` | Bỏ qua bước cài, chỉ cấu hình + test (LibreOffice đã cài sẵn) |
| `--skip-test` | Bỏ qua bước test convert |
| `-h`, `--help` | Hiển thị trợ giúp |

Profile dir mặc định:
- Linux: `/var/lib/libreoffice-profiles`
- macOS: `/Users/Shared/LibreOfficeProfiles`

---

## 3. Cấu hình .NET API

Sau khi chạy xong, script in ra đoạn `appsettings.json` với đường dẫn thực tế.
Copy vào `appsettings.json` của API:

```json
{
  "LibreOffice": {
    "ExecutablePath": "C:\\Program Files\\LibreOffice\\program\\soffice.exe",
    "ProfileBaseDir": "C:\\LibreOfficeProfiles",
    "TimeoutSeconds": 60,
    "MaxConcurrent": 4,
    "IsOn": true
  }
}
```

Trên Linux/macOS, `ExecutablePath` thường là `/usr/bin/soffice` (hoặc đường dẫn
mà script in ra), `ProfileBaseDir` là profile dir ở trên.

---

## 4. Xử lý sự cố

| Triệu chứng | Nguyên nhân / cách xử lý |
|-------------|--------------------------|
| Convert được khi test thủ công nhưng **lỗi khi chạy dưới IIS** | Chưa bật `loadUserProfile` hoặc App Pool không có quyền ghi `ProfileDir` → chạy lại script đúng `-AppPoolName` |
| `Khong tim thay file LibreOffice*.msi/.exe` | Đặt file cài đặt **cùng thư mục** với script |
| App Pool không tồn tại | Script sẽ liệt kê các pool hiện có — chạy lại với `-AppPoolName` đúng |
| Linux: convert lỗi quyền | Chạy lại với `--service-user <user>` đúng với user của .NET service |
| Thiếu font / ký tự lỗi | Cài thêm font (`fonts-dejavu`, `fonts-liberation`…) — bản Linux đã cài sẵn |

> Mỗi request convert nên dùng một thư mục `UserInstallation` riêng (con của
> `ProfileBaseDir`) để tránh xung đột khi chạy song song nhiều tiến trình LibreOffice.
