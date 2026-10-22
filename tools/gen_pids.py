import json, sys
# Output spec: key, name_en, name_ar, unit, byte offset (A=0), length, scale, offset, signed, min, max
def o(key,en,ar,unit,start,length,scale,offset,mn,mx,signed=False):
    return dict(key=key,name_en=en,name_ar=ar,unit=unit,start=start,length=length,scale=scale,offset=offset,signed=signed,min=mn,max=mx)
P=[]
def pid(code,en,ar,nbytes,outputs=None,kind="linear",category="engine",**kw):
    d=dict(pid=code,service="01",name_en=en,name_ar=ar,bytes=nbytes,kind=kind,category=category,outputs=outputs or [])
    d.update(kw); P.append(d)
for c in ["00","20","40","60","80","A0","C0"]:
    pid(c,f"PIDs supported [{int(c,16)+1:02X}-{int(c,16)+0x20:02X}]","PIDs المدعومة",4,kind="supported_bitmask",category="meta")
pid("01","Monitor status since DTCs cleared","حالة المراقبات منذ مسح الأكواد",4,kind="monitor_status",category="emissions",
    outputs=[o("mil_on","MIL (check engine) on","لمبة فحص المحرك","bool",0,1,1,0,0,1),o("dtc_count","Confirmed DTC count","عدد الأكواد المؤكدة","count",0,1,1,0,0,127)])
pid("02","DTC that caused freeze frame","الكود المسبب للإطار المجمد",2,kind="dtc",category="meta")
pid("03","Fuel system status","حالة نظام الوقود",2,kind="fuel_system_status",category="fuel",
    outputs=[o("fuel_system_1_status","Fuel system 1 status","حالة نظام الوقود 1","enum",0,1,1,0,0,255),o("fuel_system_2_status","Fuel system 2 status","حالة نظام الوقود 2","enum",1,1,1,0,0,255)])
pid("04","Calculated engine load","حمل المحرك المحسوب",1,[o("engine_load","Calculated engine load","حمل المحرك","%",0,1,100/255,0,0,100)])
pid("05","Engine coolant temperature","حرارة سائل التبريد",1,[o("coolant_temp","Engine coolant temperature","حرارة المحرك","°C",0,1,1,-40,-40,215)],category="cooling")
for c,b,en_ in [("06","1","Short term fuel trim — Bank 1"),("07","1","Long term fuel trim — Bank 1"),("08","2","Short term fuel trim — Bank 2"),("09","2","Long term fuel trim — Bank 2")]:
    st="stft" if "Short" in en_ else "ltft"
    ar=("تصحيح الوقود قصير المدى" if st=="stft" else "تصحيح الوقود طويل المدى")+f" — البنك {b}"
    pid(c,en_,ar,1,[o(f"{st}_b{b}",en_,ar,"%",0,1,100/128,-100,-100,99.2)],category="fuel")
pid("0A","Fuel pressure (gauge)","ضغط الوقود",1,[o("fuel_pressure","Fuel pressure","ضغط الوقود","kPa",0,1,3,0,0,765)],category="fuel")
pid("0B","Intake manifold absolute pressure","ضغط مجمع السحب المطلق (MAP)",1,[o("map_kpa","Intake manifold absolute pressure","ضغط مجمع السحب","kPa",0,1,1,0,0,255)],category="air_intake")
pid("0C","Engine speed","سرعة دوران المحرك",2,[o("engine_rpm","Engine speed","دورات المحرك","rpm",0,2,0.25,0,0,16383.75)])
pid("0D","Vehicle speed","سرعة السيارة",1,[o("vehicle_speed","Vehicle speed","سرعة السيارة","km/h",0,1,1,0,0,255)],category="vehicle")
pid("0E","Timing advance","تقديم الشرارة",1,[o("timing_advance","Timing advance","تقديم الشرارة","°",0,1,0.5,-64,-64,63.5)],category="ignition")
pid("0F","Intake air temperature","حرارة هواء السحب",1,[o("intake_air_temp","Intake air temperature","حرارة هواء السحب","°C",0,1,1,-40,-40,215)],category="air_intake")
pid("10","Mass air flow rate","معدل تدفق الهواء (MAF)",2,[o("maf_gs","Mass air flow rate","تدفق الهواء","g/s",0,2,0.01,0,0,655.35)],category="air_intake")
pid("11","Throttle position","موضع بوابة الهواء",1,[o("throttle_pos","Throttle position","موضع بوابة الهواء","%",0,1,100/255,0,0,100)],category="air_intake")
pid("12","Commanded secondary air status","حالة الهواء الثانوي",1,kind="enum_raw",category="emissions",outputs=[o("secondary_air_status","Commanded secondary air status","حالة الهواء الثانوي","enum",0,1,1,0,0,255)])
pid("13","Oxygen sensors present (2 banks)","حساسات الأكسجين الموجودة",1,kind="bitmask_raw",category="emissions",outputs=[o("o2_sensors_present","O2 sensors present","حساسات الأكسجين","bitmask",0,1,1,0,0,255)])
for i,c in enumerate(["14","15","16","17","18","19","1A","1B"]):
    b=1 if i<4 else 2; s=i%4+1
    pid(c,f"Oxygen sensor B{b}S{s} voltage / trim",f"حساس الأكسجين البنك {b} الحساس {s}",2,category="emissions",
        outputs=[o(f"o2_b{b}s{s}_voltage",f"O2 sensor B{b}S{s} voltage",f"جهد حساس الأكسجين ب{b}ح{s}","V",0,1,0.005,0,0,1.275),
                 o(f"o2_b{b}s{s}_stft",f"O2 sensor B{b}S{s} short term trim",f"تصحيح حساس الأكسجين ب{b}ح{s}","%",1,1,100/128,-100,-100,99.2,)],
        notes="Trim output is not applicable when byte B = 0xFF")
pid("1C","OBD standard","معيار OBD",1,kind="enum_raw",category="meta",outputs=[o("obd_standard","OBD standard","معيار OBD","enum",0,1,1,0,0,255)])
pid("1F","Run time since engine start","زمن التشغيل منذ بدء المحرك",2,[o("run_time","Run time since engine start","زمن التشغيل","s",0,2,1,0,0,65535)])
pid("21","Distance traveled with MIL on","المسافة مع لمبة الفحص",2,[o("distance_mil_on","Distance with MIL on","المسافة مع لمبة الفحص","km",0,2,1,0,0,65535)],category="emissions")
pid("22","Fuel rail pressure (relative to vacuum)","ضغط سكة الوقود النسبي",2,[o("fuel_rail_pressure_rel","Fuel rail pressure (rel.)","ضغط سكة الوقود النسبي","kPa",0,2,0.079,0,0,5177.27)],category="fuel")
pid("23","Fuel rail gauge pressure","ضغط سكة الوقود",2,[o("fuel_rail_pressure","Fuel rail gauge pressure","ضغط سكة الوقود","kPa",0,2,10,0,0,655350)],category="fuel")
for i,c in enumerate(["24","25","26","27","28","29","2A","2B"]):
    pid(c,f"Oxygen sensor {i+1} (wide range) — λ / voltage",f"حساس الأكسجين واسع المدى {i+1}",4,category="emissions",
        outputs=[o(f"o2_s{i+1}_lambda",f"O2 sensor {i+1} equivalence ratio",f"نسبة التكافؤ لحساس {i+1}","λ",0,2,2/65536,0,0,2),
                 o(f"o2_s{i+1}_wr_voltage",f"O2 sensor {i+1} voltage",f"جهد حساس {i+1}","V",2,2,8/65536,0,0,8)])
pid("2C","Commanded EGR","فتحة EGR المطلوبة",1,[o("egr_commanded","Commanded EGR","EGR المطلوب","%",0,1,100/255,0,0,100)],category="emissions")
pid("2D","EGR error","خطأ EGR",1,[o("egr_error","EGR error","خطأ EGR","%",0,1,100/128,-100,-100,99.2)],category="emissions")
pid("2E","Commanded evaporative purge","تطهير EVAP المطلوب",1,[o("evap_purge","Commanded evaporative purge","تطهير EVAP","%",0,1,100/255,0,0,100)],category="emissions")
pid("2F","Fuel tank level input","مستوى خزان الوقود",1,[o("fuel_level","Fuel tank level","مستوى الوقود","%",0,1,100/255,0,0,100)],category="fuel")
pid("30","Warm-ups since codes cleared","مرات التسخين منذ المسح",1,[o("warmups_since_clear","Warm-ups since codes cleared","مرات التسخين منذ المسح","count",0,1,1,0,0,255)],category="emissions")
pid("31","Distance traveled since codes cleared","المسافة منذ مسح الأكواد",2,[o("distance_since_clear","Distance since codes cleared","المسافة منذ المسح","km",0,2,1,0,0,65535)],category="emissions")
pid("32","Evap system vapor pressure","ضغط بخار نظام EVAP",2,[o("evap_vapor_pressure","Evap system vapor pressure","ضغط بخار EVAP","Pa",0,2,0.25,0,-8192,8191.75,signed=True)],category="emissions")
pid("33","Absolute barometric pressure","الضغط الجوي",1,[o("baro_kpa","Barometric pressure","الضغط الجوي","kPa",0,1,1,0,0,255)],category="air_intake")
for i,c in enumerate(["34","35","36","37","38","39","3A","3B"]):
    pid(c,f"Oxygen sensor {i+1} (wide range) — λ / current",f"حساس الأكسجين واسع المدى {i+1} (تيار)",4,category="emissions",
        outputs=[o(f"o2_s{i+1}_lambda_c",f"O2 sensor {i+1} equivalence ratio",f"نسبة التكافؤ لحساس {i+1}","λ",0,2,2/65536,0,0,2),
                 o(f"o2_s{i+1}_current",f"O2 sensor {i+1} current",f"تيار حساس {i+1}","mA",2,2,1/256,-128,-128,128)])
for c,b,s in [("3C",1,1),("3D",2,1),("3E",1,2),("3F",2,2)]:
    pid(c,f"Catalyst temperature B{b}S{s}",f"حرارة المحفز ب{b}ح{s}",2,[o(f"cat_temp_b{b}s{s}",f"Catalyst temperature B{b}S{s}",f"حرارة المحفز ب{b}ح{s}","°C",0,2,0.1,-40,-40,6513.5)],category="emissions")
pid("41","Monitor status this drive cycle","حالة المراقبات في هذه الدورة",4,kind="bitmask_raw",category="emissions",outputs=[])
pid("42","Control module voltage","جهد وحدة التحكم",2,[o("module_voltage","Control module voltage","جهد وحدة التحكم","V",0,2,0.001,0,0,65.535)],category="charging")
pid("43","Absolute load value","قيمة الحمل المطلق",2,[o("absolute_load","Absolute load value","الحمل المطلق","%",0,2,100/255,0,0,25700)])
pid("44","Commanded air-fuel equivalence ratio","نسبة الهواء للوقود المطلوبة",2,[o("commanded_lambda","Commanded equivalence ratio","نسبة التكافؤ المطلوبة","λ",0,2,2/65536,0,0,2)],category="fuel")
pid("45","Relative throttle position","موضع بوابة الهواء النسبي",1,[o("relative_throttle","Relative throttle position","موضع البوابة النسبي","%",0,1,100/255,0,0,100)],category="air_intake")
pid("46","Ambient air temperature","حرارة الجو المحيط",1,[o("ambient_temp","Ambient air temperature","حرارة الجو","°C",0,1,1,-40,-40,215)],category="vehicle")
for c,l in [("47","B"),("48","C")]:
    pid(c,f"Absolute throttle position {l}",f"موضع بوابة الهواء المطلق {l}",1,[o(f"throttle_pos_{l.lower()}",f"Absolute throttle position {l}",f"موضع البوابة {l}","%",0,1,100/255,0,0,100)],category="air_intake")
for c,l in [("49","D"),("4A","E"),("4B","F")]:
    pid(c,f"Accelerator pedal position {l}",f"موضع دواسة الوقود {l}",1,[o(f"accel_pedal_{l.lower()}",f"Accelerator pedal position {l}",f"دواسة الوقود {l}","%",0,1,100/255,0,0,100)],category="air_intake")
pid("4C","Commanded throttle actuator","مشغل بوابة الهواء المطلوب",1,[o("commanded_throttle","Commanded throttle actuator","البوابة المطلوبة","%",0,1,100/255,0,0,100)],category="air_intake")
pid("4D","Time run with MIL on","الزمن مع لمبة الفحص",2,[o("time_mil_on","Time run with MIL on","الزمن مع لمبة الفحص","min",0,2,1,0,0,65535)],category="emissions")
pid("4E","Time since trouble codes cleared","الزمن منذ مسح الأكواد",2,[o("time_since_clear","Time since codes cleared","الزمن منذ المسح","min",0,2,1,0,0,65535)],category="emissions")
pid("51","Fuel type","نوع الوقود",1,kind="enum_raw",category="meta",outputs=[o("fuel_type","Fuel type","نوع الوقود","enum",0,1,1,0,0,255)])
pid("52","Ethanol fuel %","نسبة الإيثانول",1,[o("ethanol_pct","Ethanol fuel %","نسبة الإيثانول","%",0,1,100/255,0,0,100)],category="fuel")
pid("59","Fuel rail absolute pressure","ضغط سكة الوقود المطلق",2,[o("fuel_rail_abs_pressure","Fuel rail absolute pressure","ضغط سكة الوقود المطلق","kPa",0,2,10,0,0,655350)],category="fuel")
pid("5A","Relative accelerator pedal position","موضع الدواسة النسبي",1,[o("relative_accel_pedal","Relative accelerator pedal position","الدواسة النسبية","%",0,1,100/255,0,0,100)],category="air_intake")
pid("5B","Hybrid battery pack remaining life","عمر بطارية الهجين المتبقي",1,[o("hybrid_battery_pct","Hybrid battery remaining life","بطارية الهجين","%",0,1,100/255,0,0,100)],category="charging")
pid("5C","Engine oil temperature","حرارة زيت المحرك",1,[o("oil_temp","Engine oil temperature","حرارة الزيت","°C",0,1,1,-40,-40,210)],category="engine")
pid("5D","Fuel injection timing","توقيت حقن الوقود",2,[o("injection_timing","Fuel injection timing","توقيت الحقن","°",0,2,1/128,-210,-210,301.992)],category="fuel")
pid("5E","Engine fuel rate","معدل استهلاك الوقود",2,[o("fuel_rate","Engine fuel rate","استهلاك الوقود","L/h",0,2,0.05,0,0,3212.75)],category="fuel")
pid("61","Driver's demand engine torque","عزم المحرك المطلوب",1,[o("demand_torque_pct","Driver's demand torque","العزم المطلوب","%",0,1,1,-125,-125,130)])
pid("62","Actual engine torque","عزم المحرك الفعلي",1,[o("actual_torque_pct","Actual engine torque","العزم الفعلي","%",0,1,1,-125,-125,130)])
pid("63","Engine reference torque","العزم المرجعي للمحرك",2,[o("reference_torque","Engine reference torque","العزم المرجعي","Nm",0,2,1,0,0,65535)])
pid("A6","Odometer","عداد المسافة",4,[o("odometer_km","Odometer","عداد المسافة","km",0,4,0.1,0,0,429496729.5)],category="vehicle")

doc={"$comment":"Standard SAE J1979 service 01 PID definitions shared by the Python and Dart engines. value = raw*scale + offset where raw is the big-endian unsigned (or two's-complement if signed) integer of `length` data bytes starting at `start` (A=0). Generated by tools/gen_pids.py — edit there.",
     "version":"1.0.0","standard":"SAE J1979 / ISO 15031-5","pids":P,
     "enums":{
       "fuel_system_status":{"0":"none","1":"open_loop_cold","2":"closed_loop","4":"open_loop_load_decel","8":"open_loop_fault","16":"closed_loop_fault"},
       "fuel_system_status_labels":{"none":{"en":"Not reported","ar":"غير مُبلغ"},"open_loop_cold":{"en":"Open loop — insufficient engine temperature","ar":"حلقة مفتوحة — المحرك بارد"},"closed_loop":{"en":"Closed loop — using O2 sensor feedback","ar":"حلقة مغلقة — يعتمد على حساس الأكسجين"},"open_loop_load_decel":{"en":"Open loop — engine load or deceleration","ar":"حلقة مفتوحة — حمل أو تباطؤ"},"open_loop_fault":{"en":"Open loop — system failure","ar":"حلقة مفتوحة — خلل في النظام"},"closed_loop_fault":{"en":"Closed loop — feedback fault","ar":"حلقة مغلقة — خلل في التغذية الراجعة"}},
       "obd_standard":{"1":"OBD-II (CARB)","2":"OBD (EPA)","3":"OBD and OBD-II","4":"OBD-I","5":"Not OBD compliant","6":"EOBD (Europe)","7":"EOBD and OBD-II","8":"EOBD and OBD","9":"EOBD, OBD and OBD II","10":"JOBD (Japan)","11":"JOBD and OBD II","12":"JOBD and EOBD","13":"JOBD, EOBD, and OBD II","17":"EMD","18":"EMD+","19":"HD OBD-C","20":"HD OBD","21":"WWH OBD","23":"HD EOBD-I","24":"HD EOBD-I N","25":"HD EOBD-II","26":"HD EOBD-II N","28":"OBDBr-1","29":"OBDBr-2","30":"KOBD","31":"IOBD I","32":"IOBD II","33":"HD EOBD-IV"},
       "fuel_type":{"0":"Not available","1":"Gasoline","2":"Methanol","3":"Ethanol","4":"Diesel","5":"LPG","6":"CNG","7":"Propane","8":"Electric","9":"Bifuel running Gasoline","10":"Bifuel running Methanol","11":"Bifuel running Ethanol","12":"Bifuel running LPG","13":"Bifuel running CNG","14":"Bifuel running Propane","15":"Bifuel running Electricity","16":"Bifuel running electric and combustion engine","17":"Hybrid gasoline","18":"Hybrid Ethanol","19":"Hybrid Diesel","20":"Hybrid Electric","21":"Hybrid running electric and combustion engine","22":"Hybrid Regenerative","23":"Bifuel running diesel"}
     },
     "service09":[
       {"pid":"00","name_en":"Service 09 supported PIDs","kind":"supported_bitmask"},
       {"pid":"02","name_en":"Vehicle Identification Number (VIN)","name_ar":"رقم الهيكل","kind":"vin"},
       {"pid":"04","name_en":"Calibration ID","name_ar":"معرف المعايرة","kind":"ascii_multi"},
       {"pid":"06","name_en":"Calibration Verification Number","name_ar":"رقم التحقق من المعايرة","kind":"hex_multi"},
       {"pid":"0A","name_en":"ECU name","name_ar":"اسم وحدة التحكم","kind":"ascii"}
     ]}
json.dump(doc,open(sys.argv[1],"w"),ensure_ascii=False,indent=1)
print(len(P),"pids")
