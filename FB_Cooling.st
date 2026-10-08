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
(* BODY *)
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
