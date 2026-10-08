(* Охлаждение трансформатора, ПЛК210-04, CODESYS 3.5, один файл.
   Секции ниже — отдельные объекты проекта. Имя объекта — заголовок секции.
   В CODESYS проще импортировать plc/Cooling.xml: там те же типы, списки
   GVL_Const, GVL_IO, GVL_Set, GVL_HMI, функции, FB_Cooling и PRG_Cooling.
   Этот текст собран из plc/st. Править нужно исходники и заново запустить
   python3 plc/build_plcopen.py
*)

(* ===== DUT_Types ===== *)
(* Структуры проекта охлаждения трансформатора.
   Импорт: в CODESYS создать DUT с этими именами или импортировать Cooling.xml. *)

TYPE ST_Stage :
STRUCT
    Used : BOOL;
    TmOn : REAL;   (* °C, масло, включение *)
    TmOff : REAL;
    TwOn : REAL;   (* °C, обмотка *)
    TwOff : REAL;
    LoadOn : REAL; (* % In *)
    LoadOff : REAL;
END_STRUCT
END_TYPE

TYPE ST_Analog :
STRUCT
    Eu : REAL;
    Milliamp : REAL;
    Fault : BOOL;
END_STRUCT
END_TYPE

(* ===== GVL_Const ===== *)
(* Константы алгоритма. Числа ступеней — с листа «Алгоритмы СО». *)
VAR_GLOBAL CONSTANT
    CO_MD : INT := 1;          (* М/Д *)
    CO_MD1D2 : INT := 2;       (* М/Д1/Д2 *)
    CO_MD_DC : INT := 3;       (* М/Д/ДЦ *)
    CO_MD1D2_DC : INT := 4;    (* М/Д1/Д2/ДЦ *)
    FAN_MAX : INT := 8;
    PUMP_MAX : INT := 4;
    COOLER_MAX : INT := 4;

    (* Сигнализация, гистерезис 5 °C. Снятие при значении <= уставка − 5. *)
    OIL_WARN_ON : REAL := 95.0;
    OIL_WARN_OFF : REAL := 90.0;
    OIL_ALARM_ON : REAL := 105.0;
    OIL_ALARM_OFF : REAL := 100.0;
    WND_WARN_ON : REAL := 100.0;
    WND_WARN_OFF : REAL := 95.0;
    WND_ALARM_ON : REAL := 115.0;
    WND_ALARM_OFF : REAL := 110.0;

    (* Таблица 4: вентиляторы группы при масле >= 40 °C, снятие при <= 35 °C. *)
    FAN_OIL_ON : REAL := 40.0;
    FAN_OIL_OFF : REAL := 35.0;
    G2_LOAD_ON : REAL := 40.0;
    G2_LOAD_OFF : REAL := 35.0;
    G2_TW_ON : REAL := 75.0;
    G2_TW_OFF : REAL := 70.0;
    G3_LOAD_ON : REAL := 75.0;
    G3_LOAD_OFF : REAL := 70.0;
    G3_TW_ON : REAL := 85.0;
    G3_TW_OFF : REAL := 80.0;
    G4_LOAD_ON : REAL := 105.0;
    G4_LOAD_OFF : REAL := 100.0;
    G4_TW_ON : REAL := 95.0;
    G4_TW_OFF : REAL := 90.0;

    (* Причины пуска двигателя, биты слова Reason. *)
    R_D1 : WORD := 16#0001;
    R_D2 : WORD := 16#0002;
    R_DC : WORD := 16#0004;
    R_GROUP_FAN : WORD := 16#0008;
    R_GROUP_PUMP : WORD := 16#0010;
    R_SENSOR : WORD := 16#0020;
    R_OVERTEMP : WORD := 16#0040;
    R_MANUAL : WORD := 16#0080;
    R_BREAKER : WORD := 16#0100;
    R_THERMAL : WORD := 16#0200;
    R_UNUSED : WORD := 16#0400;

    (* Коды конфигурации. *)
    CFG_FAN_RANGE : WORD := 16#0001;
    CFG_PUMP_RANGE : WORD := 16#0002;
    CFG_COOLER_RANGE : WORD := 16#0004;
    CFG_FANS_FOR_COOLER : WORD := 16#0008;
    CFG_PUMPS_FOR_COOLER : WORD := 16#0010;
    CFG_NOMINAL : WORD := 16#0020;
    CFG_GRADIENT : WORD := 16#0040;

    MB_PROBE : REAL := 25.0; (* регистры 90…91, проверка порядка слов *)
END_VAR

(* ===== GVL_IO ===== *)
(* Клеммы ПЛК210-04-CS в CODESYS V3.5 ОВЕН.
   На борту 12 входов FDI, 12 реле DO и 4 входа AI. Адресов %IX у этого
   контроллера нет: каналы привязываются по имени на вкладке
   «Сопоставление входов/выходов» узлов LeftSide и RightSide.

   FDI1…FDI12 перевести в режим «определение логического уровня» и привязать
   BOOL. В режиме счётчика канал имеет тип UDINT и к этим переменным не подойдёт.
   Логическая единица — 9…30 В на входе.

   DO1…DO12 — реле с нормально разомкнутым контактом, режим
   «переключение логического состояния». ШИМ на этих реле не используется:
   максимальная частота ШИМ у ПЛК210-04 всего 1 Гц.
   Тумблер СТАРТ/СТОП на лицевой панели должен стоять в положении СТАРТ,
   иначе среда не выдаёт выходы.

   AI1 и AI2: тип сигнала «Ток 4…20 мА». В REAL приходит 0…100 % диапазона,
   не миллиамперы и не градусы. AI3 и AI4 в конфигураторе выключить: опрос
   входов идёт по очереди, до 0,6 с на каждый включённый канал. *)
VAR_GLOBAL
    AI_Tm : REAL;       (* AI1, масло, 0…100 % шкалы 4…20 мА *)
    AI_I : REAL;        (* AI2, ток нагрузки, 0…100 % шкалы 4…20 мА *)
    DI_Breaker : BOOL;  (* FDI1, блок-контакт выключателя ВН, 24 В = включён *)
    DI_FanOk1 : BOOL;   (* FDI2, тепловое реле вентилятора 1, НЗ, TRUE = норма *)
    DI_FanOk2 : BOOL;   (* FDI3 *)
    DI_FanOk3 : BOOL;   (* FDI4 *)
    DI_FanOk4 : BOOL;   (* FDI5 *)
    DI_FanOk5 : BOOL;   (* FDI6 *)
    DI_FanOk6 : BOOL;   (* FDI7 *)
    DI_FanOk7 : BOOL;   (* FDI8 *)
    DI_FanOk8 : BOOL;   (* FDI9 *)
    DI_PumpOk1 : BOOL;  (* FDI10, тепловое реле насоса 1 *)
    DI_PumpOk2 : BOOL;  (* FDI11 *)
    DI_PumpOk3 : BOOL;  (* FDI12, последний дискретный вход контроллера *)
    (* Четвёртого входа на борту нет. Пока реле насоса 4 не заведено через модуль
       Мх210, переменная остаётся TRUE и не даёт ложный останов. *)
    DI_PumpOk4 : BOOL := TRUE;
    DO_Fan1 : BOOL;     (* DO1, реле, пускатель вентилятора 1 *)
    DO_Fan2 : BOOL;     (* DO2 *)
    DO_Fan3 : BOOL;     (* DO3 *)
    DO_Fan4 : BOOL;     (* DO4 *)
    DO_Fan5 : BOOL;     (* DO5 *)
    DO_Fan6 : BOOL;     (* DO6 *)
    DO_Fan7 : BOOL;     (* DO7 *)
    DO_Fan8 : BOOL;     (* DO8 *)
    DO_Pump1 : BOOL;    (* DO9, реле, пускатель насоса 1 *)
    DO_Pump2 : BOOL;    (* DO10 *)
    DO_Pump3 : BOOL;    (* DO11 *)
    DO_Pump4 : BOOL;    (* DO12, последнее реле контроллера *)
END_VAR

(* ===== GVL_Set ===== *)
(* Уставки, которые задаёт персонал с СП307 или по Modbus.
   RETAIN PERSISTENT — сохраняются в MRAM ПЛК210. *)
VAR_GLOBAL RETAIN PERSISTENT
    CoolingType : INT := 2;         (* 1 М/Д, 2 М/Д1/Д2, 3 М/Д/ДЦ, 4 М/Д1/Д2/ДЦ *)
    Gradient : REAL := 20.0;        (* Gr, К *)
    NominalCurrent : REAL := 5.0;   (* In, А, в тех же единицах, что и измерение *)
    FanCount : INT := 4;
    PumpCount : INT := 0;
    CoolerCount : INT := 0;
    RotationHours : REAL := 168.0;  (* 0 — без ротации *)
    AiMode : INT := 0;              (* 0: канал 0…100 %, 1: канал уже в мА *)
    TmAt4mA : REAL := 0.0;
    TmAt20mA : REAL := 150.0;
    IAt20mA : REAL := 5.0;          (* по пометке 0…5 А → 4…20 мА *)
    BreakerRequired : BOOL := TRUE;
    UseTable4 : BOOL := TRUE;
    Group1AtIdle : BOOL := TRUE;    (* насосы 1-й группы на холостом ходу *)
    UseMotorFaults : BOOL := FALSE;
    ExponentY : REAL := 1.2;        (* по ТЗ *)
    TauSec : REAL := 480.0;         (* 8 минут, по ТЗ *)
    Simulation : BOOL := FALSE;
    SimTm : REAL := 40.0;
    SimCurrent : REAL := 0.0;
    Manual : BOOL := FALSE;
    ManualFan : ARRAY[1..8] OF BOOL;
    ManualPump : ARRAY[1..4] OF BOOL;
    Ack : BOOL := FALSE;
    ResetHours : BOOL := FALSE;
    ResetTheta : BOOL := FALSE;
    SwapWords : BOOL := FALSE;      (* TRUE, если панель читает REAL наоборот *)
END_VAR

(* ===== GVL_HMI ===== *)
(* Образ для панели СП307, веб-визуализации и верхнего уровня. *)
VAR_GLOBAL
    Tm : REAL;
    Current : REAL;
    Tw : REAL;              (* температура обмотки To *)
    LoadPercent : REAL;
    Kfactor : REAL;
    DeltaSteady : REAL;
    Theta : REAL;
    TmMilliamp : REAL;
    IMilliamp : REAL;
    StageD1 : BOOL;
    StageD2 : BOOL;
    StageDC : BOOL;
    SensorFaultTm : BOOL;
    SensorFaultI : BOOL;
    ConfigBits : WORD;
    Failsafe : BOOL;
    TransformerOn : BOOL;
    WarnOil : BOOL;
    AlarmOil : BOOL;
    WarnWinding : BOOL;
    AlarmWinding : BOOL;
    Horn : BOOL;
    TmFans : BOOL;
    GroupPump : ARRAY[1..4] OF BOOL;
    FanRun : ARRAY[1..8] OF BOOL;
    PumpRun : ARRAY[1..4] OF BOOL;
    FanHours : ARRAY[1..8] OF REAL;
    FanStarts : ARRAY[1..8] OF UDINT;
    PumpHours : ARRAY[1..4] OF REAL;
    PumpStarts : ARRAY[1..4] OF UDINT;
    FanReason : ARRAY[1..8] OF WORD;
    PumpReason : ARRAY[1..4] OF WORD;
    FanFault : ARRAY[1..8] OF BOOL;
    PumpFault : ARRAY[1..4] OF BOOL;
    CoolerRole : ARRAY[1..4] OF INT;
    CoolerDutyHours : ARRAY[1..4] OF REAL;
    EffFanCount : INT;
    EffPumpCount : INT;
    EffCoolerCount : INT;
    HasD2 : BOOL;
    HasDC : BOOL;
    (* Образ Modbus TCP slave. Сопоставить с holding-регистрами с адреса 0. *)
    MB : ARRAY[0..255] OF WORD;
END_VAR

(* ===== GVL_Visu ===== *)
(* Команды веб-визуализации ПЛК210. Экран Visu_Main пишет сюда кнопки,
   программа снимает их в том же цикле. Числа и лампы веб-экран берёт
   напрямую из GVL_HMI и GVL_Set, второй образ для них не нужен.
   Текст кода BannerCode — в plc/WEBVISU.md, список текстов Text_Banner. *)
VAR_GLOBAL
    BtnAck : BOOL;          (* кнопка «Квитировать», Tap *)
    BtnResetHours : BOOL;   (* кнопка «Сбросить наработку» *)
    BtnResetTheta : BOOL;   (* кнопка «Сбросить нагрев обмотки» *)
    BannerCode : INT;       (* 0…9, текст состояния для WebVisu *)
    Heartbeat : WORD;       (* +1 каждый цикл PRG_Cooling, то же значение в MB[19] *)
END_VAR

(* ===== F_Hyst ===== *)
FUNCTION F_Hyst : BOOL
VAR_INPUT
    Prev : BOOL;
    Value : REAL;
    LevelOn : REAL;
    LevelOff : REAL;
END_VAR

IF (NOT Prev) AND (Value >= LevelOn) THEN
    F_Hyst := TRUE;
ELSIF Prev AND (Value <= LevelOff) THEN
    F_Hyst := FALSE;
ELSE
    F_Hyst := Prev;
END_IF
END_FUNCTION

(* ===== F_Scale ===== *)
FUNCTION F_Scale : ST_Analog
VAR_INPUT
    Raw : REAL;
    Mode : INT; (* 0 — проценты диапазона 4…20 мА, 1 — уже миллиамперы *)
    EuAt4 : REAL;
    EuAt20 : REAL;
END_VAR
VAR
    result : ST_Analog;
    percent : REAL;
END_VAR

(* ПЛК210-04, сигнал «Ток 4…20 мА»: канал отдаёт REAL 0…100 %, не миллиамперы.
   Обрыв линии уходит ниже 0 % (порог −1 % ≈ 3,8 мА), перегруз — выше 103 % ≈ 20,5 мА.
   Неиспользуемые AI3 и AI4 нужно выключить: контроллер опрашивает входы по очереди. *)
IF Mode = 1 THEN
    result.Milliamp := Raw;
    percent := ((Raw - 4.0) / 16.0) * 100.0;
ELSE
    percent := Raw;
    result.Milliamp := 4.0 + (percent / 100.0) * 16.0;
END_IF
result.Fault := (percent < -1.0) OR (percent > 103.0);
result.Eu := EuAt4 + (percent / 100.0) * (EuAt20 - EuAt4);
F_Scale := result;
END_FUNCTION

(* ===== F_Theta ===== *)
FUNCTION F_Theta : REAL
VAR_INPUT
    Theta : REAL;
    DeltaSteady : REAL;
    dtSec : REAL;
    TauSec : REAL;
END_VAR
VAR
    alpha : REAL;
END_VAR

(* Шаг формулы To = ΔT·(1 − e^(−t/τ)) + Tm.
   При скачке нагрузки это апериодическое звено, а не время от включения контроллера. *)
IF (dtSec > 0.0) AND (TauSec > 0.0) THEN
    alpha := 1.0 - EXP(-dtSec / TauSec);
    F_Theta := Theta + (DeltaSteady - Theta) * alpha;
ELSE
    F_Theta := Theta;
END_IF
END_FUNCTION

(* ===== F_Stage ===== *)
FUNCTION F_Stage : BOOL
VAR_INPUT
    Prev : BOOL;
    Enabled : BOOL;
    Permit : BOOL;
    Tm : REAL;
    Tw : REAL;
    LoadPct : REAL;
    Limits : ST_Stage;
END_VAR
VAR
    turnOn : BOOL;
    turnOff : BOOL;
END_VAR

(* Включение по любому из трёх условий, отключение когда все три не выше уставок «откл.». *)
IF (NOT Enabled) OR (NOT Permit) OR (NOT Limits.Used) THEN
    F_Stage := FALSE;
    RETURN;
END_IF
turnOn := (Tm >= Limits.TmOn) OR (Tw >= Limits.TwOn) OR (LoadPct >= Limits.LoadOn);
turnOff := (Tm <= Limits.TmOff) AND (Tw <= Limits.TwOff) AND (LoadPct <= Limits.LoadOff);
IF (NOT Prev) AND turnOn THEN
    F_Stage := TRUE;
ELSIF Prev AND turnOff THEN
    F_Stage := FALSE;
ELSE
    F_Stage := Prev;
END_IF
END_FUNCTION

(* ===== F_StageTable ===== *)
FUNCTION F_StageTable : ST_Stage
VAR_INPUT
    CoolingType : INT;
    Stage : INT; (* 1 — Д1, 2 — Д2, 3 — ДЦ *)
END_VAR
VAR
    row : ST_Stage;
END_VAR

row.Used := FALSE;
IF Stage = 1 THEN
    row.Used := TRUE;
    row.TmOn := 55.0;
    row.TmOff := 50.0;
    row.TwOn := 75.0;
    row.TwOff := 70.0;
    row.LoadOn := 80.0;
    row.LoadOff := 75.0;
ELSIF Stage = 2 THEN
    IF CoolingType = CO_MD1D2 THEN
        row.Used := TRUE;
        row.TmOn := 65.0;
        row.TmOff := 60.0;
        row.TwOn := 85.0;
        row.TwOff := 80.0;
        row.LoadOn := 105.0;
        row.LoadOff := 100.0;
    ELSIF CoolingType = CO_MD1D2_DC THEN
        row.Used := TRUE;
        row.TmOn := 65.0;
        row.TmOff := 60.0;
        row.TwOn := 85.0;
        row.TwOff := 80.0;
        row.LoadOn := 90.0;
        row.LoadOff := 85.0;
    END_IF
    (* У М/Д/ДЦ строка Д2 на листе пустая — ступень не используется. *)
ELSIF Stage = 3 THEN
    IF (CoolingType = CO_MD_DC) OR (CoolingType = CO_MD1D2_DC) THEN
        row.Used := TRUE;
        row.TmOn := 75.0;
        row.TmOff := 70.0;
        row.TwOn := 90.0;
        row.TwOff := 85.0;
        row.LoadOn := 105.0;
        row.LoadOff := 100.0;
    END_IF
END_IF
F_StageTable := row;
END_FUNCTION

(* ===== F_SplitReal ===== *)
FUNCTION F_SplitReal : BOOL
VAR_INPUT
    Value : REAL;
END_VAR
VAR_OUTPUT
    Hi : WORD;
    Lo : WORD;
END_VAR
VAR
    tmp : REAL;
    pw : POINTER TO WORD;
END_VAR

(* Память ПЛК210 little-endian: первое слово REAL — младшее. *)
tmp := Value;
pw := ADR(tmp);
Lo := pw^;
pw := pw + 1;
Hi := pw^;
F_SplitReal := TRUE;
END_FUNCTION

(* ===== F_JoinReal ===== *)
FUNCTION F_JoinReal : REAL
VAR_INPUT
    Hi : WORD;
    Lo : WORD;
    Swap : BOOL;
END_VAR
VAR
    tmp : REAL;
    pw : POINTER TO WORD;
END_VAR

tmp := 0.0;
pw := ADR(tmp);
IF Swap THEN
    pw^ := Hi;
    pw := pw + 1;
    pw^ := Lo;
ELSE
    pw^ := Lo;
    pw := pw + 1;
    pw^ := Hi;
END_IF
F_JoinReal := tmp;
END_FUNCTION

(* ===== FB_Cooling ===== *)
FUNCTION_BLOCK FB_Cooling
VAR_INPUT
    dtSec : REAL;
END_VAR
VAR
    i : INT;
    j : INT;
    fans : INT;
    pumps : INT;
    coolers : INT;
    half : INT;
    cfg : WORD;
    hasD2 : BOOL;
    hasDC : BOOL;
    permit : BOOL;
    transformerOn : BOOL;
    tmFault : BOOL;
    iFault : BOOL;
    tmMeas : REAL;
    iMeas : REAL;
    analog : ST_Analog;
    k : REAL;
    dSteady : REAL;
    lim : ST_Stage;
    tableOn : BOOL;
    g2 : BOOL;
    g3 : BOOL;
    g4 : BOOL;
    failsafe : BOOL;
    run : BOOL;
    reason : WORD;
    healthy : BOOL;
    stageName : INT;
    cooler : INT;
    role : INT;
    demanded : BOOL;
    replacement : INT;
    least : REAL;
    worked : REAL;
    fanOk : ARRAY[1..8] OF BOOL;
    pumpOk : ARRAY[1..4] OF BOOL;
    alphaHours : REAL;
END_VAR
VAR RETAIN PERSISTENT
    ThetaR : REAL;
    TwR : REAL;
    TmHold : REAL;
    IHold : REAL;
    KHold : REAL;
    LoadHold : REAL;
    DeltaHold : REAL;
    StageD1R : BOOL;
    StageD2R : BOOL;
    StageDCR : BOOL;
    WarnOilR : BOOL;
    AlarmOilR : BOOL;
    WarnWndR : BOOL;
    AlarmWndR : BOOL;
    HornR : BOOL;
    TmFansR : BOOL;
    G2Load : BOOL;
    G2Tw : BOOL;
    G3Load : BOOL;
    G3Tw : BOOL;
    G4Load : BOOL;
    G4Tw : BOOL;
    FanHoursR : ARRAY[1..8] OF REAL;
    FanStartsR : ARRAY[1..8] OF UDINT;
    PumpHoursR : ARRAY[1..4] OF REAL;
    PumpStartsR : ARRAY[1..4] OF UDINT;
    PrevFan : ARRAY[1..8] OF BOOL;
    PrevPump : ARRAY[1..4] OF BOOL;
    RoleR : ARRAY[1..4] OF INT;
    DutyR : ARRAY[1..4] OF REAL;
    AppliedCoolers : INT := -1;
    AckPrev : BOOL;
    ResetHoursPrev : BOOL;
    ResetThetaPrev : BOOL;
    HornOilW : BOOL;
    HornOilA : BOOL;
    HornWndW : BOOL;
    HornWndA : BOOL;
    HornTm : BOOL;
    HornI : BOOL;
    HornCfg : BOOL;
END_VAR

fans := GVL_Set.FanCount;
pumps := GVL_Set.PumpCount;
coolers := GVL_Set.CoolerCount;
cfg := 0;
IF (fans < 0) OR (fans > FAN_MAX) THEN
    cfg := cfg OR CFG_FAN_RANGE;
END_IF
IF (pumps < 0) OR (pumps > PUMP_MAX) THEN
    cfg := cfg OR CFG_PUMP_RANGE;
END_IF
IF (coolers < 0) OR (coolers > COOLER_MAX) THEN
    cfg := cfg OR CFG_COOLER_RANGE;
END_IF
fans := LIMIT(0, fans, FAN_MAX);
pumps := LIMIT(0, pumps, PUMP_MAX);
coolers := LIMIT(0, coolers, COOLER_MAX);
IF coolers * 2 > fans THEN
    cfg := cfg OR CFG_FANS_FOR_COOLER;
    coolers := fans / 2;
END_IF
IF coolers > pumps THEN
    cfg := cfg OR CFG_PUMPS_FOR_COOLER;
    coolers := pumps;
END_IF
IF GVL_Set.NominalCurrent <= 0.0 THEN
    cfg := cfg OR CFG_NOMINAL;
END_IF
IF GVL_Set.Gradient < 0.0 THEN
    cfg := cfg OR CFG_GRADIENT;
END_IF

IF coolers <> AppliedCoolers THEN
    FOR i := 1 TO COOLER_MAX DO
        IF i <= coolers THEN
            RoleR[i] := i;
        ELSE
            RoleR[i] := 0;
        END_IF
        DutyR[i] := 0.0;
    END_FOR
    AppliedCoolers := coolers;
END_IF

IF GVL_Set.ResetHours AND (NOT ResetHoursPrev) THEN
    FOR i := 1 TO FAN_MAX DO
        FanHoursR[i] := 0.0;
        FanStartsR[i] := 0;
    END_FOR
    FOR i := 1 TO PUMP_MAX DO
        PumpHoursR[i] := 0.0;
        PumpStartsR[i] := 0;
    END_FOR
    FOR i := 1 TO COOLER_MAX DO
        DutyR[i] := 0.0;
    END_FOR
END_IF
ResetHoursPrev := GVL_Set.ResetHours;
GVL_Set.ResetHours := FALSE;

IF GVL_Set.ResetTheta AND (NOT ResetThetaPrev) THEN
    ThetaR := 0.0;
END_IF
ResetThetaPrev := GVL_Set.ResetTheta;
GVL_Set.ResetTheta := FALSE;

analog := F_Scale(GVL_IO.AI_Tm, GVL_Set.AiMode, GVL_Set.TmAt4mA, GVL_Set.TmAt20mA);
tmMeas := analog.Eu;
tmFault := analog.Fault;
TmMilliamp := analog.Milliamp;
analog := F_Scale(GVL_IO.AI_I, GVL_Set.AiMode, 0.0, GVL_Set.IAt20mA);
iMeas := analog.Eu;
IF iMeas < 0.0 THEN
    iMeas := 0.0;
END_IF
iFault := analog.Fault;
IMilliamp := analog.Milliamp;

IF GVL_Set.Simulation THEN
    tmMeas := GVL_Set.SimTm;
    iMeas := GVL_Set.SimCurrent;
    IF iMeas < 0.0 THEN
        iMeas := 0.0;
    END_IF
    tmFault := FALSE;
    iFault := FALSE;
    IF (GVL_Set.TmAt20mA - GVL_Set.TmAt4mA) <> 0.0 THEN
        TmMilliamp := 4.0 + ((tmMeas - GVL_Set.TmAt4mA) / (GVL_Set.TmAt20mA - GVL_Set.TmAt4mA)) * 16.0;
    END_IF
    IF GVL_Set.IAt20mA <> 0.0 THEN
        IMilliamp := 4.0 + (iMeas / GVL_Set.IAt20mA) * 16.0;
    END_IF
END_IF

SensorFaultTm := tmFault;
SensorFaultI := iFault;
IF tmFault THEN
    Tm := TmHold;
ELSE
    Tm := tmMeas;
    TmHold := tmMeas;
END_IF
IF iFault THEN
    Current := IHold;
ELSE
    Current := iMeas;
    IHold := iMeas;
END_IF

IF GVL_Set.BreakerRequired THEN
    transformerOn := GVL_IO.DI_Breaker;
ELSE
    transformerOn := TRUE;
END_IF
TransformerOn := transformerOn;

IF (NOT iFault) AND (GVL_Set.NominalCurrent > 0.0) THEN
    k := Current / GVL_Set.NominalCurrent;
    KHold := k;
    LoadHold := k * 100.0;
ELSE
    k := KHold;
END_IF
Kfactor := KHold;
LoadPercent := LoadHold;

IF NOT iFault THEN
    IF (GVL_Set.Gradient > 0.0) AND (k > 0.0) THEN
        (* EXPT входит в библиотеку Standard среды CODESYS 3.5 ОВЕН. *)
        dSteady := GVL_Set.Gradient * EXPT(k, GVL_Set.ExponentY);
    ELSE
        dSteady := 0.0;
    END_IF
    DeltaHold := dSteady;
ELSE
    dSteady := DeltaHold;
END_IF
DeltaSteady := dSteady;

IF (NOT tmFault) AND (NOT iFault) THEN
    ThetaR := F_Theta(ThetaR, dSteady, dtSec, GVL_Set.TauSec);
    TwR := ThetaR + tmMeas;
ELSIF NOT tmFault THEN
    TwR := ThetaR + tmMeas;
END_IF
Theta := ThetaR;
Tw := TwR;

IF NOT tmFault THEN
    WarnOilR := F_Hyst(WarnOilR, tmMeas, OIL_WARN_ON, OIL_WARN_OFF);
    AlarmOilR := F_Hyst(AlarmOilR, tmMeas, OIL_ALARM_ON, OIL_ALARM_OFF);
    TmFansR := F_Hyst(TmFansR, tmMeas, FAN_OIL_ON, FAN_OIL_OFF);
    WarnWndR := F_Hyst(WarnWndR, TwR, WND_WARN_ON, WND_WARN_OFF);
    AlarmWndR := F_Hyst(AlarmWndR, TwR, WND_ALARM_ON, WND_ALARM_OFF);
END_IF
WarnOil := WarnOilR;
AlarmOil := AlarmOilR;
WarnWinding := WarnWndR;
AlarmWinding := AlarmWndR;
TmFans := TmFansR;

permit := transformerOn AND (NOT GVL_Set.Manual);
hasD2 := (GVL_Set.CoolingType = CO_MD1D2) OR (GVL_Set.CoolingType = CO_MD1D2_DC);
hasDC := (GVL_Set.CoolingType = CO_MD_DC) OR (GVL_Set.CoolingType = CO_MD1D2_DC);
HasD2 := hasD2;
HasDC := hasDC;

lim := F_StageTable(GVL_Set.CoolingType, 1);
StageD1R := F_Stage(StageD1R, TRUE, permit, Tm, Tw, LoadPercent, lim);
lim := F_StageTable(GVL_Set.CoolingType, 2);
StageD2R := F_Stage(StageD2R, hasD2, permit, Tm, Tw, LoadPercent, lim);
lim := F_StageTable(GVL_Set.CoolingType, 3);
StageDCR := F_Stage(StageDCR, hasDC, permit, Tm, Tw, LoadPercent, lim);
StageD1 := StageD1R;
StageD2 := StageD2R;
StageDC := StageDCR;

IF (NOT iFault) AND (NOT tmFault) THEN
    G2Load := F_Hyst(G2Load, LoadPercent, G2_LOAD_ON, G2_LOAD_OFF);
    G2Tw := F_Hyst(G2Tw, Tw, G2_TW_ON, G2_TW_OFF);
    G3Load := F_Hyst(G3Load, LoadPercent, G3_LOAD_ON, G3_LOAD_OFF);
    G3Tw := F_Hyst(G3Tw, Tw, G3_TW_ON, G3_TW_OFF);
    G4Load := F_Hyst(G4Load, LoadPercent, G4_LOAD_ON, G4_LOAD_OFF);
    G4Tw := F_Hyst(G4Tw, Tw, G4_TW_ON, G4_TW_OFF);
END_IF
g2 := G2Load OR G2Tw;
g3 := G3Load OR G3Tw;
g4 := G4Load OR G4Tw;
tableOn := GVL_Set.UseTable4 AND hasDC AND (coolers > 0) AND permit;
GroupPump[1] := tableOn AND (GVL_Set.Group1AtIdle OR StageDCR OR g2 OR g3 OR g4);
GroupPump[2] := tableOn AND g2;
GroupPump[3] := tableOn AND g3;
GroupPump[4] := tableOn AND g4;

failsafe := permit AND (tmFault OR iFault OR AlarmOilR OR AlarmWndR);
Failsafe := failsafe;

fanOk[1] := GVL_IO.DI_FanOk1;
fanOk[2] := GVL_IO.DI_FanOk2;
fanOk[3] := GVL_IO.DI_FanOk3;
fanOk[4] := GVL_IO.DI_FanOk4;
fanOk[5] := GVL_IO.DI_FanOk5;
fanOk[6] := GVL_IO.DI_FanOk6;
fanOk[7] := GVL_IO.DI_FanOk7;
fanOk[8] := GVL_IO.DI_FanOk8;
pumpOk[1] := GVL_IO.DI_PumpOk1;
pumpOk[2] := GVL_IO.DI_PumpOk2;
pumpOk[3] := GVL_IO.DI_PumpOk3;
pumpOk[4] := GVL_IO.DI_PumpOk4;

FOR i := 1 TO PUMP_MAX DO
    PumpFault[i] := (i <= pumps) AND GVL_Set.UseMotorFaults AND (NOT pumpOk[i]);
END_FOR

(* Ротация: смена вступает в силу на этом цикле, если наработка уже набрана. *)
IF permit AND GVL_Set.UseTable4 AND (coolers >= 2) THEN
    FOR i := 1 TO coolers DO
        role := RoleR[i];
        demanded := FALSE;
        IF (role >= 1) AND (role <= 4) THEN
            demanded := GroupPump[role];
        END_IF
        IF demanded AND (PumpFault[i] OR ((GVL_Set.RotationHours > 0.0) AND (DutyR[i] >= GVL_Set.RotationHours))) THEN
            replacement := 0;
            least := 999999.0;
            FOR j := 1 TO coolers DO
                IF j <> i THEN
                    role := RoleR[j];
                    demanded := FALSE;
                    IF (role >= 1) AND (role <= 4) THEN
                        demanded := GroupPump[role];
                    END_IF
                    IF (NOT demanded) AND (NOT PumpFault[j]) AND (PumpHoursR[j] < least) THEN
                        least := PumpHoursR[j];
                        replacement := j;
                    END_IF
                END_IF
            END_FOR
            IF replacement <> 0 THEN
                role := RoleR[i];
                RoleR[i] := RoleR[replacement];
                RoleR[replacement] := role;
                DutyR[i] := 0.0;
                DutyR[replacement] := 0.0;
                EXIT;
            END_IF
        END_IF
    END_FOR
END_IF

IF fans > 0 THEN
    half := (fans + 1) / 2;
ELSE
    half := 0;
END_IF

FOR i := 1 TO FAN_MAX DO
    reason := 0;
    run := FALSE;
    healthy := (NOT GVL_Set.UseMotorFaults) OR fanOk[i];
    FanFault[i] := (i <= fans) AND GVL_Set.UseMotorFaults AND (NOT fanOk[i]);
    IF i > fans THEN
        run := FALSE;
    ELSIF GVL_Set.Manual THEN
        run := GVL_Set.ManualFan[i] AND healthy;
        IF run THEN
            reason := reason OR R_MANUAL;
        END_IF
        IF NOT healthy THEN
            reason := reason OR R_THERMAL;
        END_IF
    ELSIF NOT transformerOn THEN
        reason := reason OR R_BREAKER;
    ELSIF NOT healthy THEN
        reason := reason OR R_THERMAL;
    ELSIF failsafe THEN
        run := TRUE;
        IF tmFault OR iFault THEN
            reason := reason OR R_SENSOR;
        END_IF
        IF AlarmOilR OR AlarmWndR THEN
            reason := reason OR R_OVERTEMP;
        END_IF
    ELSE
        IF hasD2 AND (i > half) THEN
            stageName := 2;
        ELSE
            stageName := 1;
        END_IF
        IF ((stageName = 1) AND StageD1R) OR ((stageName = 2) AND StageD2R) THEN
            run := TRUE;
            IF stageName = 1 THEN
                reason := reason OR R_D1;
            ELSE
                reason := reason OR R_D2;
            END_IF
        END_IF
        cooler := (i + 1) / 2;
        IF (cooler >= 1) AND (cooler <= coolers) AND tableOn THEN
            role := RoleR[cooler];
            IF (role >= 1) AND (role <= 4) AND TmFansR THEN
                IF GroupPump[role] THEN
                    run := TRUE;
                    reason := reason OR R_GROUP_FAN;
                END_IF
            END_IF
        END_IF
    END_IF
    IF run AND (NOT PrevFan[i]) THEN
        FanStartsR[i] := FanStartsR[i] + 1;
    END_IF
    IF run AND (dtSec > 0.0) THEN
        FanHoursR[i] := FanHoursR[i] + dtSec / 3600.0;
    END_IF
    PrevFan[i] := run;
    FanRun[i] := run;
    FanReason[i] := reason;
    FanHours[i] := FanHoursR[i];
    FanStarts[i] := FanStartsR[i];
END_FOR

FOR i := 1 TO PUMP_MAX DO
    reason := 0;
    run := FALSE;
    healthy := (NOT GVL_Set.UseMotorFaults) OR pumpOk[i];
    IF (NOT hasDC) AND (i <= pumps) AND (NOT GVL_Set.Manual) THEN
        reason := R_UNUSED;
    ELSIF i > pumps THEN
        run := FALSE;
    ELSIF GVL_Set.Manual THEN
        run := GVL_Set.ManualPump[i] AND healthy;
        IF run THEN
            reason := reason OR R_MANUAL;
        END_IF
        IF NOT healthy THEN
            reason := reason OR R_THERMAL;
        END_IF
    ELSIF NOT transformerOn THEN
        reason := reason OR R_BREAKER;
    ELSIF NOT healthy THEN
        reason := reason OR R_THERMAL;
    ELSIF failsafe AND hasDC AND (i <= pumps) THEN
        run := TRUE;
        IF tmFault OR iFault THEN
            reason := reason OR R_SENSOR;
        END_IF
        IF AlarmOilR OR AlarmWndR THEN
            reason := reason OR R_OVERTEMP;
        END_IF
    ELSIF hasDC AND (i <= pumps) THEN
        IF (i <= coolers) AND tableOn THEN
            role := RoleR[i];
            IF (role >= 1) AND (role <= 4) THEN
                IF GroupPump[role] THEN
                    run := TRUE;
                    reason := reason OR R_GROUP_PUMP;
                END_IF
            END_IF
        ELSIF StageDCR THEN
            run := TRUE;
            reason := reason OR R_DC;
        END_IF
    END_IF
    IF run AND (NOT PrevPump[i]) THEN
        PumpStartsR[i] := PumpStartsR[i] + 1;
    END_IF
    IF run AND (dtSec > 0.0) THEN
        PumpHoursR[i] := PumpHoursR[i] + dtSec / 3600.0;
    END_IF
    PrevPump[i] := run;
    PumpRun[i] := run;
    PumpReason[i] := reason;
    PumpHours[i] := PumpHoursR[i];
    PumpStarts[i] := PumpStartsR[i];
END_FOR

IF permit AND GVL_Set.UseTable4 AND (dtSec > 0.0) THEN
    alphaHours := dtSec / 3600.0;
    FOR i := 1 TO coolers DO
        IF PumpRun[i] THEN
            DutyR[i] := DutyR[i] + alphaHours;
        END_IF
    END_FOR
END_IF

FOR i := 1 TO COOLER_MAX DO
    CoolerRole[i] := RoleR[i];
    CoolerDutyHours[i] := DutyR[i];
END_FOR
EffFanCount := fans;
EffPumpCount := pumps;
EffCoolerCount := coolers;
ConfigBits := cfg;

IF (WarnOilR AND NOT HornOilW) OR (AlarmOilR AND NOT HornOilA) OR (WarnWndR AND NOT HornWndW) OR (AlarmWndR AND NOT HornWndA) OR (tmFault AND NOT HornTm) OR (iFault AND NOT HornI) OR ((cfg <> 0) AND NOT HornCfg) THEN
    HornR := TRUE;
END_IF
HornOilW := WarnOilR;
HornOilA := AlarmOilR;
HornWndW := WarnWndR;
HornWndA := AlarmWndR;
HornTm := tmFault;
HornI := iFault;
HornCfg := cfg <> 0;
IF GVL_Set.Ack AND (NOT AckPrev) THEN
    HornR := FALSE;
END_IF
AckPrev := GVL_Set.Ack;
GVL_Set.Ack := FALSE;
Horn := HornR;
END_FUNCTION_BLOCK

(* ===== PRG_Cooling ===== *)
PROGRAM PRG_Cooling
VAR
    ctrl : FB_Cooling;
    tNow : DWORD;
    tPrev : DWORD;
    dtMs : DWORD;
    dtSec : REAL;
    first : BOOL := TRUE;
    hi : WORD;
    lo : WORD;
    ok : BOOL;
    i : INT;
    addr : INT;
    bits : WORD;
    flags : WORD;
    strobe : WORD;
END_VAR

(* В задаче Main: только эта программа. Цикл 100 мс.
   Аналоговые входы ПЛК210-04 обновляются сами, до 0,6 с на включённый канал,
   и между опросами держат прошлое значение. Время нагрева обмотки считается
   по циклу задачи, а не по периоду АЦП.
   Среда — CODESYS V3.5 ОВЕН для устройства ПЛК210-04-CS. Пустой цикл
   контроллера около 3 мс, такт 100 мс для реле достаточен: контакт
   переключается до 10 мс. Память RETAIN PERSISTENT лежит в MRAM 64 Кбайт.
   Три клиента смотрят одни и те же переменные:
   веб-браузер — WebVisu, переменные GVL_Visu / GVL_HMI / GVL_Set;
   панель СП307 — Modbus TCP, команды в MB[100];
   верхний уровень — чтение MB[0]…MB[91] и действующих уставок MB[128]…MB[171]. *)

strobe := MB[100];
IF strobe = 1 THEN
    CoolingType := LIMIT(1, WORD_TO_INT(MB[101]), 4);
    Gradient := F_JoinReal(MB[102], MB[103], SwapWords);
    NominalCurrent := F_JoinReal(MB[104], MB[105], SwapWords);
    FanCount := LIMIT(0, WORD_TO_INT(MB[106]), FAN_MAX);
    PumpCount := LIMIT(0, WORD_TO_INT(MB[107]), PUMP_MAX);
    CoolerCount := LIMIT(0, WORD_TO_INT(MB[108]), COOLER_MAX);
    RotationHours := F_JoinReal(MB[109], MB[110], SwapWords);
    TmAt4mA := F_JoinReal(MB[111], MB[112], SwapWords);
    TmAt20mA := F_JoinReal(MB[113], MB[114], SwapWords);
    IAt20mA := F_JoinReal(MB[115], MB[116], SwapWords);
    flags := MB[117];
    BreakerRequired := (flags AND WORD#16#0001) <> WORD#0;
    UseTable4 := (flags AND WORD#16#0002) <> WORD#0;
    Group1AtIdle := (flags AND WORD#16#0004) <> WORD#0;
    UseMotorFaults := (flags AND WORD#16#0008) <> WORD#0;
    Simulation := (flags AND WORD#16#0010) <> WORD#0;
    Manual := (flags AND WORD#16#0020) <> WORD#0;
    IF (flags AND WORD#16#0040) <> WORD#0 THEN
        AiMode := 1;
    ELSE
        AiMode := 0;
    END_IF
    SwapWords := (flags AND WORD#16#0080) <> WORD#0;
    SimTm := F_JoinReal(MB[118], MB[119], SwapWords);
    SimCurrent := F_JoinReal(MB[120], MB[121], SwapWords);
    FOR i := 1 TO FAN_MAX DO
        ManualFan[i] := (MB[122] AND SHL(WORD#1, i - 1)) <> WORD#0;
    END_FOR
    FOR i := 1 TO PUMP_MAX DO
        ManualPump[i] := (MB[123] AND SHL(WORD#1, i - 1)) <> WORD#0;
    END_FOR
    ExponentY := F_JoinReal(MB[124], MB[125], SwapWords);
    TauSec := F_JoinReal(MB[126], MB[127], SwapWords);
    IF ExponentY <= 0.0 THEN
        ExponentY := 1.2;
    END_IF
    IF TauSec <= 0.0 THEN
        TauSec := 480.0;
    END_IF
ELSIF strobe = 2 THEN
    Ack := TRUE;
ELSIF strobe = 3 THEN
    ResetHours := TRUE;
ELSIF strobe = 4 THEN
    ResetTheta := TRUE;
END_IF
IF strobe <> 0 THEN
    MB[100] := 0;
END_IF

(* Кнопки WebVisu. Сброс в этом же цикле, иначе Tap останется нажат. *)
IF BtnAck THEN
    Ack := TRUE;
    BtnAck := FALSE;
END_IF
IF BtnResetHours THEN
    ResetHours := TRUE;
    BtnResetHours := FALSE;
END_IF
IF BtnResetTheta THEN
    ResetTheta := TRUE;
    BtnResetTheta := FALSE;
END_IF

tNow := TIME_TO_DWORD(TIME());
dtMs := tNow - tPrev;
tPrev := tNow;
IF first OR (dtMs > 2000) THEN
    dtSec := 0.0;
    first := FALSE;
ELSE
    dtSec := DWORD_TO_REAL(dtMs) / 1000.0;
END_IF

ctrl(dtSec := dtSec);

DO_Fan1 := FanRun[1];
DO_Fan2 := FanRun[2];
DO_Fan3 := FanRun[3];
DO_Fan4 := FanRun[4];
DO_Fan5 := FanRun[5];
DO_Fan6 := FanRun[6];
DO_Fan7 := FanRun[7];
DO_Fan8 := FanRun[8];
DO_Pump1 := PumpRun[1];
DO_Pump2 := PumpRun[2];
DO_Pump3 := PumpRun[3];
DO_Pump4 := PumpRun[4];

ok := F_SplitReal(Value := Tm, Hi => hi, Lo => lo);
MB[0] := SEL(SwapWords, hi, lo);
MB[1] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := Current, Hi => hi, Lo => lo);
MB[2] := SEL(SwapWords, hi, lo);
MB[3] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := Tw, Hi => hi, Lo => lo);
MB[4] := SEL(SwapWords, hi, lo);
MB[5] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := LoadPercent, Hi => hi, Lo => lo);
MB[6] := SEL(SwapWords, hi, lo);
MB[7] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := Kfactor, Hi => hi, Lo => lo);
MB[8] := SEL(SwapWords, hi, lo);
MB[9] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := DeltaSteady, Hi => hi, Lo => lo);
MB[10] := SEL(SwapWords, hi, lo);
MB[11] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := Theta, Hi => hi, Lo => lo);
MB[12] := SEL(SwapWords, hi, lo);
MB[13] := SEL(SwapWords, lo, hi);

MB[14] := INT_TO_WORD(CoolingType);

bits := 0;
IF SensorFaultTm THEN bits := bits OR WORD#16#0001; END_IF
IF SensorFaultI THEN bits := bits OR WORD#16#0002; END_IF
IF ConfigBits <> 0 THEN bits := bits OR WORD#16#0004; END_IF
IF TransformerOn THEN bits := bits OR WORD#16#0008; END_IF
IF Failsafe THEN bits := bits OR WORD#16#0010; END_IF
IF Horn THEN bits := bits OR WORD#16#0020; END_IF
IF Manual THEN bits := bits OR WORD#16#0040; END_IF
IF Simulation THEN bits := bits OR WORD#16#0080; END_IF
IF StageD1 THEN bits := bits OR WORD#16#0100; END_IF
IF StageD2 THEN bits := bits OR WORD#16#0200; END_IF
IF StageDC THEN bits := bits OR WORD#16#0400; END_IF
IF GroupPump[1] THEN bits := bits OR WORD#16#0800; END_IF
IF GroupPump[2] THEN bits := bits OR WORD#16#1000; END_IF
IF GroupPump[3] THEN bits := bits OR WORD#16#2000; END_IF
IF GroupPump[4] THEN bits := bits OR WORD#16#4000; END_IF
IF TmFans THEN bits := bits OR WORD#16#8000; END_IF
MB[15] := bits;

bits := 0;
IF WarnOil THEN bits := bits OR WORD#16#0001; END_IF
IF AlarmOil THEN bits := bits OR WORD#16#0002; END_IF
IF WarnWinding THEN bits := bits OR WORD#16#0004; END_IF
IF AlarmWinding THEN bits := bits OR WORD#16#0008; END_IF
FOR i := 1 TO FAN_MAX DO
    IF FanFault[i] THEN bits := bits OR WORD#16#0010; END_IF
END_FOR
FOR i := 1 TO PUMP_MAX DO
    IF PumpFault[i] THEN bits := bits OR WORD#16#0010; END_IF
END_FOR
MB[16] := bits;

bits := 0;
FOR i := 1 TO FAN_MAX DO
    IF FanRun[i] THEN bits := bits OR SHL(WORD#1, i - 1); END_IF
END_FOR
MB[17] := bits;
bits := 0;
FOR i := 1 TO PUMP_MAX DO
    IF PumpRun[i] THEN bits := bits OR SHL(WORD#1, i - 1); END_IF
END_FOR
MB[18] := bits;

Heartbeat := DWORD_TO_WORD(WORD_TO_DWORD(Heartbeat) + 1);
MB[19] := Heartbeat;

addr := 20;
FOR i := 1 TO FAN_MAX DO
    ok := F_SplitReal(Value := FanHours[i], Hi => hi, Lo => lo);
    MB[addr] := SEL(SwapWords, hi, lo);
    MB[addr + 1] := SEL(SwapWords, lo, hi);
    addr := addr + 2;
END_FOR
addr := 36;
FOR i := 1 TO FAN_MAX DO
    (* UDINT в двух словах: старшее слово по младшему адресу, как у REAL. *)
    lo := DWORD_TO_WORD(UDINT_TO_DWORD(FanStarts[i]) AND DWORD#16#FFFF);
    hi := DWORD_TO_WORD(SHR(UDINT_TO_DWORD(FanStarts[i]), 16));
    IF SwapWords THEN
        MB[addr] := lo;
        MB[addr + 1] := hi;
    ELSE
        MB[addr] := hi;
        MB[addr + 1] := lo;
    END_IF
    addr := addr + 2;
END_FOR

addr := 52;
FOR i := 1 TO PUMP_MAX DO
    ok := F_SplitReal(Value := PumpHours[i], Hi => hi, Lo => lo);
    MB[addr] := SEL(SwapWords, hi, lo);
    MB[addr + 1] := SEL(SwapWords, lo, hi);
    addr := addr + 2;
END_FOR
addr := 60;
FOR i := 1 TO PUMP_MAX DO
    lo := DWORD_TO_WORD(UDINT_TO_DWORD(PumpStarts[i]) AND DWORD#16#FFFF);
    hi := DWORD_TO_WORD(SHR(UDINT_TO_DWORD(PumpStarts[i]), 16));
    IF SwapWords THEN
        MB[addr] := lo;
        MB[addr + 1] := hi;
    ELSE
        MB[addr] := hi;
        MB[addr + 1] := lo;
    END_IF
    addr := addr + 2;
END_FOR
addr := 68;
FOR i := 1 TO COOLER_MAX DO
    ok := F_SplitReal(Value := CoolerDutyHours[i], Hi => hi, Lo => lo);
    MB[addr] := SEL(SwapWords, hi, lo);
    MB[addr + 1] := SEL(SwapWords, lo, hi);
    addr := addr + 2;
END_FOR
FOR i := 1 TO COOLER_MAX DO
    MB[75 + i] := INT_TO_WORD(CoolerRole[i]);
END_FOR
ok := F_SplitReal(Value := TmMilliamp, Hi => hi, Lo => lo);
MB[80] := SEL(SwapWords, hi, lo);
MB[81] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := IMilliamp, Hi => hi, Lo => lo);
MB[82] := SEL(SwapWords, hi, lo);
MB[83] := SEL(SwapWords, lo, hi);
MB[84] := INT_TO_WORD(EffFanCount);
MB[85] := INT_TO_WORD(EffPumpCount);
MB[86] := INT_TO_WORD(EffCoolerCount);
MB[87] := ConfigBits;
ok := F_SplitReal(Value := MB_PROBE, Hi => hi, Lo => lo);
MB[90] := SEL(SwapWords, hi, lo);
MB[91] := SEL(SwapWords, lo, hi);

(* Действующие уставки. Буфер записи 101…127 программа не перезаписывает,
   чтобы недописанный кадр панели не затирался. Верхний уровень и экран
   «как сейчас» читают 128…155. *)
MB[128] := INT_TO_WORD(CoolingType);
ok := F_SplitReal(Value := Gradient, Hi => hi, Lo => lo);
MB[129] := SEL(SwapWords, hi, lo);
MB[130] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := NominalCurrent, Hi => hi, Lo => lo);
MB[131] := SEL(SwapWords, hi, lo);
MB[132] := SEL(SwapWords, lo, hi);
MB[133] := INT_TO_WORD(FanCount);
MB[134] := INT_TO_WORD(PumpCount);
MB[135] := INT_TO_WORD(CoolerCount);
ok := F_SplitReal(Value := RotationHours, Hi => hi, Lo => lo);
MB[136] := SEL(SwapWords, hi, lo);
MB[137] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := TmAt4mA, Hi => hi, Lo => lo);
MB[138] := SEL(SwapWords, hi, lo);
MB[139] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := TmAt20mA, Hi => hi, Lo => lo);
MB[140] := SEL(SwapWords, hi, lo);
MB[141] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := IAt20mA, Hi => hi, Lo => lo);
MB[142] := SEL(SwapWords, hi, lo);
MB[143] := SEL(SwapWords, lo, hi);
flags := 0;
IF BreakerRequired THEN flags := flags OR WORD#16#0001; END_IF
IF UseTable4 THEN flags := flags OR WORD#16#0002; END_IF
IF Group1AtIdle THEN flags := flags OR WORD#16#0004; END_IF
IF UseMotorFaults THEN flags := flags OR WORD#16#0008; END_IF
IF Simulation THEN flags := flags OR WORD#16#0010; END_IF
IF Manual THEN flags := flags OR WORD#16#0020; END_IF
IF AiMode = 1 THEN flags := flags OR WORD#16#0040; END_IF
IF SwapWords THEN flags := flags OR WORD#16#0080; END_IF
MB[144] := flags;
ok := F_SplitReal(Value := SimTm, Hi => hi, Lo => lo);
MB[145] := SEL(SwapWords, hi, lo);
MB[146] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := SimCurrent, Hi => hi, Lo => lo);
MB[147] := SEL(SwapWords, hi, lo);
MB[148] := SEL(SwapWords, lo, hi);
bits := 0;
FOR i := 1 TO FAN_MAX DO
    IF ManualFan[i] THEN bits := bits OR SHL(WORD#1, i - 1); END_IF
END_FOR
MB[149] := bits;
bits := 0;
FOR i := 1 TO PUMP_MAX DO
    IF ManualPump[i] THEN bits := bits OR SHL(WORD#1, i - 1); END_IF
END_FOR
MB[150] := bits;
ok := F_SplitReal(Value := ExponentY, Hi => hi, Lo => lo);
MB[151] := SEL(SwapWords, hi, lo);
MB[152] := SEL(SwapWords, lo, hi);
ok := F_SplitReal(Value := TauSec, Hi => hi, Lo => lo);
MB[153] := SEL(SwapWords, hi, lo);
MB[154] := SEL(SwapWords, lo, hi);
FOR i := 1 TO FAN_MAX DO
    MB[159 + i] := FanReason[i];
END_FOR
FOR i := 1 TO PUMP_MAX DO
    MB[167 + i] := PumpReason[i];
END_FOR

IF ConfigBits <> 0 THEN
    BannerCode := 7;
ELSIF SensorFaultTm OR SensorFaultI THEN
    BannerCode := 6;
ELSIF AlarmOil THEN
    BannerCode := 2;
ELSIF AlarmWinding THEN
    BannerCode := 3;
ELSIF WarnOil THEN
    BannerCode := 4;
ELSIF WarnWinding THEN
    BannerCode := 5;
ELSIF NOT TransformerOn THEN
    BannerCode := 8;
ELSIF Manual THEN
    BannerCode := 9;
ELSE
    BannerCode := 0;
END_IF
END_PROGRAM
