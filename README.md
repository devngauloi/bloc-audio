# bloc-audio — catalog nhạc cho app BLOC (host qua jsDelivr)

Repo này chứa **nhạc đã encode (.mp3)** + **`catalog.json`** mà app BLOC tải về.
Đẩy lên một repo GitHub **public**, jsDelivr sẽ phân phối miễn phí qua CDN. App
trỏ vào URL `catalog.json` (1 dòng trong `lib/data/tracks.dart`).

- **Format:** MP3 (CBR 128–192k) — Android *và* iOS đều phát native, một bộ file dùng cho cả hai.
- **Licensing (rủi ro T1):** CHỈ host nhạc bạn được quyền phân phối — CC0 / commissioned / Suno gói trả phí. **TUYỆT ĐỐI KHÔNG** Epidemic Sound / Artlist (sai license).

```
bloc-audio/
├─ lofi/            *.mp3
├─ ambient/         *.mp3
├─ rain/            *.mp3
├─ instrumental/    *.mp3
├─ catalog.json     <- danh sách mood -> [{title,url}]
├─ validate.ps1     <- KIỂM TRA mp3 + json (chạy trước khi push)
├─ hooks/pre-push   <- (tùy chọn) ép validate tự động mỗi lần push
├─ _src/            <- (tùy chọn) file gốc WAV/FLAC; bị .gitignore, không lên CDN
└─ .gitignore
```

---

## Yêu cầu môi trường
- **git**
- **ffmpeg + ffprobe** trên PATH (đã có: `C:\ffmpeg\bin`). `ffprobe -version` để kiểm.
- **PowerShell** (validate.ps1 chạy trên Windows PowerShell 5.1).

---

## Quy trình từng bước

### Bước 1 — Chuẩn bị file MP3 hợp lệ
Để file gốc (wav/flac/mp3 chất lượng cao) vào `_src/` rồi encode ra đúng chuẩn.
Encode CBR 160k, 44.1kHz (CBR ổn định cho streaming + seek chính xác):

```powershell
ffmpeg -i _src/twilight-city.wav -c:a libmp3lame -b:a 160k -ar 44100 lofi/twilight-city.mp3
```

Khuyến nghị chuẩn hóa độ to để đổi mood không giật âm lượng:
```powershell
ffmpeg -i _src/twilight-city.wav -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:a libmp3lame -b:a 160k -ar 44100 lofi/twilight-city.mp3
```

Quy ước tên file: **chữ thường, không dấu, không khoảng trắng** (vd `low-swamp.mp3`)
để khỏi phải %20-encode URL. Đặt vào đúng thư mục mood.

### Bước 2 — Cập nhật `catalog.json`
4 khóa mood (`lofi/ambient/rain/instrumental`) là **bắt buộc**, mỗi mood ≥ 1 track.
Sửa `title` (tên hiển thị trong app) và `url`. Đổi `devngauloi` thành GitHub user
của bạn nếu khác. Có thể thêm nhiều track / mood (station sẽ nối tiếp & lặp).

```json
{
  "lofi": [
    { "title": "Twilight City", "url": "https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/lofi/twilight-city.mp3" },
    { "title": "Low Swamp",     "url": "https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/lofi/low-swamp.mp3" }
  ],
  "ambient":      [ { "title": "Soft Pads I",     "url": "https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/ambient/soft-pads-01.mp3" } ],
  "rain":         [ { "title": "Inner Yard Rain", "url": "https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/rain/inner-yard.mp3" } ],
  "instrumental": [ { "title": "Distant Wonders", "url": "https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/instrumental/distant-wonders.mp3" } ]
}
```

### Bước 3 — VALIDATE (cổng chặn trước khi push)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\validate.ps1
```
Script kiểm:
- **JSON:** parse được; đủ 4 mood; mỗi mood ≥ 1 track; `title`/`url` không rỗng; URL đúng dạng jsDelivr `.mp3`.
- **File:** mọi url trỏ tới file **có thật** trong repo; tên file an toàn; dung lượng (cảnh báo > 20MB, lỗi > 50MB = quá hạn jsDelivr).
- **MP3 (ffprobe):** codec đúng là `mp3`, có audio stream, duration > 0, sample rate 44.1/48k, bitrate 128–192k.
- **Orphan:** file `.mp3` trong repo nhưng không nằm trong catalog (cảnh báo).

Kết quả:
- `PASS - OK to push` → exit 0, được push.
- `FAIL - fix the errors` → exit 1, **sửa hết lỗi đỏ rồi chạy lại**.

> Mẹo: ép validate tự động — cài hook (chạy 1 lần, sau Bước 4 `git init`):
> ```bash
> cp hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
> ```
> Từ đó mỗi `git push` tự chạy validate, fail thì chặn push.

### Bước 4 — Tạo repo GitHub & push
Tạo repo **public** tên `bloc-audio` trên GitHub (không thêm README để khỏi xung đột).
```bash
git init && git add . && git commit -m "BLOC audio catalog (mp3)"
git branch -M main
git remote add origin https://github.com/devngauloi/bloc-audio.git
git push -u origin main
```
(Nếu đã cài pre-push hook, push sẽ tự validate trước.)

### Bước 5 — Kiểm tra qua CDN (1 phút)
```bash
# 200 + content-type: audio/mpeg
curl -I "https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/lofi/twilight-city.mp3"
# range request (just_audio cần) -> phải 206
curl -s -o /dev/null -w "%{http_code}\n" -r 0-1 "https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/lofi/twilight-city.mp3"
# catalog hợp lệ
curl -s "https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/catalog.json"
```
Lần gọi đầu jsDelivr "kéo" file từ GitHub có thể chậm 1–2s, sau đó đã cache.

### Bước 6 — Trỏ app vào catalog
Trong dự án `sleeping-music`, sửa đúng 1 dòng `lib/data/tracks.dart`:
```dart
const String _catalogUrl =
    'https://cdn.jsdelivr.net/gh/devngauloi/bloc-audio@main/catalog.json';
```
Build lại app → app fetch catalog, stream MP3, cache xuống đĩa; offline-chưa-cache
thì tự rớt về bundled `assets/audio/<mood>.mp3`.

---

## Cập nhật catalog về sau (lưu ý cache jsDelivr)
jsDelivr cache nhánh `@main` rất lâu (tới ~7 ngày). Sau khi push thay đổi
`catalog.json`, **purge** để app thấy bản mới:
```bash
curl "https://purge.jsdelivr.net/gh/devngauloi/bloc-audio@main/catalog.json"
```
File `.mp3` thường không sửa (chỉ thêm bài tên mới) nên hiếm khi cần purge nhạc.
Sau MVP, chuyển sang **Cloudflare R2** (cập nhật tức thì, không cần purge) bằng
cách đổi đúng dòng `_catalogUrl` — không đụng code khác.
