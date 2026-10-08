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
