# البدء على ويندوز — اختبار جهاز ELM327 الحقيقي
# Getting started on Windows — testing your real ELM327

## 1. التثبيت / Install (once)

1. ثبّت Python 3.12 أو أحدث من python.org (فعّل خيار *Add python.exe to PATH*).
   Install Python ≥ 3.12 from python.org (tick *Add python.exe to PATH*).
2. ثبّت Git ثم انسخ المستودع / Install Git and clone:
   ```powershell
   git clone https://github.com/bandar197/ai-auto.git
   cd ai-auto\backend
   python -m venv .venv
   .venv\Scripts\activate
   pip install -e ".[dev,ble,serial]"
   ```

## 2. جرّب المحاكي أولا / Try the simulator first (no car needed)

```powershell
# نافذة 1 / terminal 1
automind simulate --scenario p0106_map_sensor --port 35000
# نافذة 2 / terminal 2
automind connect --host 127.0.0.1 --port 35000
automind scan --host 127.0.0.1 --port 35000 --duration 60 --out demo.json --report demo.html --lang ar
start demo.html
```
سيظهر أن البيانات **تجريبية** لأن المحاكي يعرّف نفسه بذلك.
The output is labelled **DEMO** because the simulator identifies itself.

## 3. الاختبار على السيارة / Real car test (Dodge Challenger 2019 or any OBD-II car)

1. ركّب جهاز ELM327 Wi-Fi في منفذ OBD (تحت المقود).
2. شغّل الإشعال (أو المحرك للبيانات الحية).
3. اربط اللابتوب بشبكة Wi-Fi الخاصة بالجهاز (غالبا اسمها `WiFi_OBDII` أو `V-LINK`). **ستنقطع الإنترنت مؤقتا وهذا طبيعي.**
4. نفّذ / run:
   ```powershell
   automind connect --host 192.168.0.10 --port 35000
   ```
   ستظهر حالتان منفصلتان / you will see two separate statuses:
   * `phone/PC ↔ adapter` — اتصال اللابتوب بالجهاز
   * `adapter ↔ vehicle` — اتصال الجهاز بكمبيوتر السيارة
5. فحص كامل مع تسجيل 90 ثانية (اترك المحرك في الخمول 30 ثانية ثم ثبّت 2500 دورة 30 ثانية):
   ```powershell
   automind scan --host 192.168.0.10 --port 35000 --duration 90 --out challenger.json --report challenger.html --lang ar
   ```
6. الاختبار الآلي الحقيقي / automated hardware test:
   ```powershell
   $env:AUTOMIND_HW_HOST="192.168.0.10"; $env:AUTOMIND_HW_PORT="35000"; $env:AUTOMIND_HW_SECONDS="30"
   pytest -m hardware -s
   ```
7. أعد تحليل التسجيل لاحقا دون السيارة / re-analyse later without the car:
   ```powershell
   automind replay challenger.json --speed 4 --report replay.html
   ```

### إذا فشل الاتصال / Troubleshooting

| الرسالة | السبب المحتمل |
|---|---|
| `adapter: unreachable` | اللابتوب غير متصل بشبكة الجهاز، أو IP/المنفذ مختلف (جرّب 192.168.0.10:35000 أو 192.168.0.123:35000)، أو جدار الحماية |
| `adapter: timeout` | الجهاز لا يرد بعلامة `>` — افصله وأعد توصيله |
| `vehicle ECU: no_response` | الجهاز يعمل لكن السيارة لا ترد — شغّل الإشعال، أو جرّب `--protocol 6` |
| `bus_error` / `CAN ERROR` | مشكلة في التوصيل بالمنفذ أو بروتوكول غير مدعوم من الجهاز |
| أجهزة رخيصة (clones) | بعض أوامر AT غير مدعومة — الأداة تتجاهلها وتكمل |

أرسل لي ملف `challenger.json` (يمكنك حذف رقم الهيكل بخيار `--no-vin`) لأحسّن التوافق بناء على بيانات سيارتك الحقيقية.
Send the `challenger.json` (use `--no-vin` to omit the VIN) so compatibility can be tuned on real data.

## 4. المسح ثم التحقق هل رجع العطل / Clear, then verify whether the fault comes back

```powershell
# المحرك مطفأ والإشعال شغال / engine OFF, ignition ON
automind clear --host 192.168.0.10 --port 35000 --out clear_record.json
# يحفظ الأكواد والإطار المجمد أولا، يطلب موافقتك، يمسح، ثم يعيد الفحص فورا

# بعد القيادة (يوم أو يومين) / after driving
automind verify clear_record.json --host 192.168.0.10 --port 35000
```

النتيجة لكل كود / verdict per code:

| النتيجة | المعنى |
|---|---|
| رجع فورا | العطل موجود الآن — المسح لا يصلحه |
| رجع / اكتُشف مرة أخرى | عطل حقيقي متقطع أو مع الحمل |
| لم يرجع — غالبا عطل قديم | السيارة أعادت اختبارها الذاتي ولم يظهر (مثلا بعد تغيير قطعة) |
| لم يرجع حتى الآن | الاختبار الذاتي لم يكتمل بعد — قُد السيارة وأعد التحقق |

> مسح أكواد الوسائد الهوائية (الإيرباق) يحتاج بروتوكول الشركة المصنعة وجهازا يدعمه، وهو مسجل في النظام كإجراء مقيد يُفعّل لكل شركة وطراز بعد اختباره. منطق "هل رجع؟" نفسه جاهز لأكواد الإيرباق (B) ويعتمد على الفحص الذاتي عند كل تشغيل للإشعال.

## 5. تطبيق ويندوز والنظام الكامل على اللابتوب / Windows app and the full system on the laptop

### تطبيق ويندوز (نفس تطبيق الجوال) / Windows app (same app as the phone)

1. من GitHub: **Actions** ← آخر تشغيل لـ **CI** ← قسم **Artifacts** ← نزّل **automind-windows**.
2. فك الضغط في مجلد، وشغّل `automind_app.exe`. إذا ظهر تحذير Windows SmartScreen اختر **More info ← Run anyway** (النسخة غير موقّعة بعد).
3. **الوضع التجريبي** يعمل فورا. **الوضع الحي**: اربط اللابتوب بشبكة واي فاي جهاز ELM327 ثم اتصل على `192.168.0.10:35000`.
4. **البلوتوث / Bluetooth** — في شاشة الاتصال اختر نوع القارئ / pick the adapter type on the Connect screen:
   - **Bluetooth LE** (أغلب القارئات التي تعمل مع الآيفون / most adapters that work with an iPhone): اضغط «ابحث عن القارئات» واختره من القائمة — لا حاجة للإقران من ويندوز. / Tap *Scan for adapters* and pick it — no pairing in Windows needed. يحتاج اللابتوب بلوتوث 4.0 أو أحدث / needs Bluetooth 4.0+.
   - **Bluetooth Classic** (قارئات SPP القديمة / older SPP adapters): اقرن القارئ أولا من **الإعدادات ← Bluetooth والأجهزة ← إضافة جهاز** (الرمز غالبا `1234` أو `0000`). ينشئ ويندوز منفذ **COM** صادر (تجده في *More Bluetooth settings ← COM Ports*). في التطبيق اختر **Bluetooth Classic** ثم منفذ COM، والسرعة 38400 (جرّب 9600 أو 115200 إن لم يرد). / Pair it in **Settings → Bluetooth & devices → Add device** (PIN usually `1234` or `0000`); Windows creates an outgoing **COM** port (*More Bluetooth settings → COM Ports*). In the app choose **Bluetooth Classic**, then the COM port, baud 38400 (try 9600 or 115200 if it does not answer).
   - قارئات **USB** تظهر أيضا كمنفذ COM في نفس القائمة. / **USB** adapters appear as COM ports in the same list.

### النظام الكامل (الخادم + لوحة الإدارة + المحاكي) / Full stack

1. ثبّت **Docker Desktop** وشغّله: https://www.docker.com/products/docker-desktop/
2. من مجلد المشروع في PowerShell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\windows\start-local.ps1
   ```
3. أنشئ حساب المدير (يطبع رمز المصادقة الثنائية لتطبيق Google Authenticator):
   ```powershell
   docker compose exec -it api automind create-admin --email you@example.com
   ```
4. افتح لوحة الإدارة: http://localhost:3000 — ووثائق الـ API: http://localhost:8000/api/v1/docs
5. تطبيق ويندوز يتصل تلقائيا بالخادم على `localhost:8000` (التسجيل، التحليل الكامل، التقارير، المسح ثم التحقق).
6. يمكن تجربة الوضع الحي في التطبيق على المحاكي: العنوان `127.0.0.1` والمنفذ `35000` (سيظهر كبيانات تجريبية).

> كرت الشاشة غير مطلوب حاليا؛ النظام يعمل على المعالج. ‎32 جيجا رام أكثر من كافية.

## 6. BLE / USB

```powershell
automind ble-scan
automind connect --ble AA:BB:CC:DD:EE:FF
automind connect --serial COM3
```
