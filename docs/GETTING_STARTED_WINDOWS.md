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

## 5. BLE / USB

```powershell
automind ble-scan
automind connect --ble AA:BB:CC:DD:EE:FF
automind connect --serial COM3
```
