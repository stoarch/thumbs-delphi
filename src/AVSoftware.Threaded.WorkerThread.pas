{ *******************************************************

  AVSoftware Threaded Utilities

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }

unit AVSoftware.Threaded.WorkerThread;

interface

uses
  // COMMON
  System.Classes, System.SyncObjs, System.Generics.Collections, System.SysUtils,
  // AVS COMMON
  AVSoftware.Common.Events,
  // AVS STATES
  AVSoftware.StateMachine.State;

const
  CategoryWorkerThreadError = $A00006;
  // todo: Move error categories to one place

type
  TWorkerStatus = (wsUnknown, wsStarted, wsStoped, wsComplete, wsError,
    wsStarting, wsRestarting, wsIdle);

type
  TWorkerThread = class(TThread)
  private
    FStartEvent: TEvent;
    FNeedToStopEvent: TEvent;
    FStopedEvent: TEvent;
    FRestartEvent: TEvent;

    FCurrentJobState: TState;

    FStatus: TWorkerStatus;
    FStatusGuard: TCriticalSection;

    FOnComplete: TNotifyEvent;
    FOnError: TErrorEvent;
    FOnLog: TLogEvent;
    FOnStart: TNotifyEvent;
    FOnStop: TNotifyEvent;

    FWorkerStatus: TWorkerStatus;

  protected
    procedure HandleOnTerminate(sender: TObject); virtual;
  protected type
    TInternalState = class
    private
      FOwner: TWorkerThread;
    protected
      procedure DoExecute; virtual;

    public
      constructor Create(AOwner: TWorkerThread);
      procedure Execute;

      property Owner: TWorkerThread read FOwner;
    end;

    TInternalStartingState = class(TInternalState)
    protected
      procedure DoExecute; override;
    end;

    TInternalRestartingState = class(TInternalState)
    protected
      procedure DoExecute; override;
    end;

    TInternalStartedState = class(TInternalState)
    protected
      procedure DoExecute; override;
    end;

    TInternalStopedState = class(TInternalState)
    protected
      procedure DoExecute; override;
    end;

    TInternalIdleState = class(TInternalState)
    protected
      procedure DoExecute; override;
    end;

  private
    FInternalState: TInternalState;

    FInternalStateDict: TDictionary<TWorkerStatus, TInternalState>;

    FInternalIdleState: TInternalIdleState;
    FInternalStartedState: TInternalStartedState;
    FInternalStopedState: TInternalStopedState;
    FInternalStartingState: TInternalStartingState;
    FInternalRestartingState: TInternalRestartingState;

    procedure InitializeInternalStates;
    procedure FreeInternalStates;

    function GetCurrentInternalState: TInternalState;
    function GetWorkerStatus: TWorkerStatus;

    procedure SetOnComplete(const Value: TNotifyEvent);
    procedure SetOnError(const Value: TErrorEvent);
    procedure SetOnLog(const Value: TLogEvent);
    procedure SetOnStart(const Value: TNotifyEvent);
    procedure SetOnStop(const Value: TNotifyEvent);
    procedure SetWorkerStatus(const Value: TWorkerStatus);
    procedure SetCurrentJobState(const Value: TState);

  protected
    procedure Execute; override;
    procedure Log(Message: string);

    procedure FireOnComplete;
    procedure FireOnError(ErrorCode: integer; Message: string);
    procedure FireOnStart;
    procedure FireOnStop;

    property CurrentInternalState: TInternalState read GetCurrentInternalState;
    property CurrentJobState: TState read FCurrentJobState
      write SetCurrentJobState;
    property WorkerStatus: TWorkerStatus read GetWorkerStatus
      write SetWorkerStatus;

    procedure ExecuteJob; virtual;
    procedure FinishJob; virtual;
    procedure PrepareJob; virtual;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Restart;
    procedure Start;
    procedure Stop;
    procedure WaitStop;

    property WorkerState: TWorkerStatus read GetWorkerStatus;

    property OnStart: TNotifyEvent read FOnStart write SetOnStart;
    property OnStop: TNotifyEvent read FOnStop write SetOnStop;
    property OnError: TErrorEvent read FOnError write SetOnError;
    property OnComplete: TNotifyEvent read FOnComplete write SetOnComplete;
    property OnLog: TLogEvent read FOnLog write SetOnLog;

    property StartEvent: TEvent read FStartEvent;
    property NeedToStopEvent: TEvent read FNeedToStopEvent;
    property StopedEvent: TEvent read FStopedEvent;
    property RestartEvent: TEvent read FRestartEvent;
  end;

implementation

const
  ThreadIdleTimeout = 100; // ms

  { TWorkerThread.TInternalStopedState }

procedure TWorkerThread.TInternalStopedState.DoExecute;
begin
  inherited;

  // Clear search if we stopped abnormally (by user)
  if (Owner.NeedToStopEvent.WaitFor(ThreadIdleTimeout) = wrSignaled) then
  begin
    Owner.NeedToStopEvent.ResetEvent;

    Owner.FinishJob;

    Owner.WorkerStatus := wsIdle;

    Owner.StopedEvent.SetEvent;
  end;

end;

{ TWorkerThread.TInternalStartedState }

procedure TWorkerThread.TInternalStartedState.DoExecute;
begin
  inherited;

  Owner.ExecuteJob;
end;

{ TWorkerThread.TInternalRestartingState }

procedure TWorkerThread.TInternalRestartingState.DoExecute;
begin
  inherited;

  if Owner.RestartEvent.WaitFor(ThreadIdleTimeout) = wrSignaled then
  begin
    Owner.RestartEvent.ResetEvent;

    Owner.FinishJob;

    Owner.PrepareJob;

    Owner.WorkerStatus := wsStarted;

    Owner.StartEvent.SetEvent;
  end;
end;

{ TWorkerThread.TInternalState }

procedure TWorkerThread.TInternalState.Execute;
begin
  DoExecute;
end;

constructor TWorkerThread.TInternalState.Create(AOwner: TWorkerThread);
begin
  FOwner := AOwner;
end;

procedure TWorkerThread.TInternalState.DoExecute;
begin
  // do nothing: implemented in child states
end;

{ TWorkerThread.TInternalStartingState }

procedure TWorkerThread.TInternalStartingState.DoExecute;
begin
  inherited;

  if Owner.StartEvent.WaitFor(ThreadIdleTimeout) = wrSignaled then
  begin
    Owner.StartEvent.ResetEvent;

    Owner.PrepareJob;

    Owner.WorkerStatus := wsStarted;
  end;
end;

{ TWorkerThread.TInternalIdleState }

procedure TWorkerThread.TInternalIdleState.DoExecute;
begin
  inherited;
  // this is simple dispatcher code. After setting status worker goes to another
  // state and execute next time goes to it
  repeat

    if (Owner.StartEvent.WaitFor(ThreadIdleTimeout) = wrSignaled) then
    begin
      Owner.WorkerStatus := wsStarting;
      break;
    end;

    if (Owner.RestartEvent.WaitFor(ThreadIdleTimeout) = wrSignaled) then
    begin
      Owner.WorkerStatus := wsRestarting;
      break;
    end;

  until Owner.Terminated;

end;

{ TWorkerThread }

constructor TWorkerThread.Create;
begin
  inherited;

  // SetThreadAffinityMask( handle, 3 );//dual core optimization 3 - 0,1 processor

  OnTerminate := HandleOnTerminate;

  Priority := tpLower;

  FStatusGuard := TCriticalSection.Create;

  InitializeInternalStates;

  WorkerStatus := wsIdle;

  FStartEvent := TEvent.Create(nil, true, false, 'Start' + IntToStr(ThreadId));
  FNeedToStopEvent := TEvent.Create(nil, true, false,
    'NeedToStop' + IntToStr(ThreadId));
  FRestartEvent := TEvent.Create(nil, true, false,
    'Restart' + IntToStr(ThreadId));
  FStopedEvent := TEvent.Create(nil, true, false,
    'Stoped' + IntToStr(ThreadId));
end;

destructor TWorkerThread.Destroy;
begin

  inherited;
end;

procedure TWorkerThread.HandleOnTerminate(sender: TObject);
begin
  FreeInternalStates;
  FreeAndNil(FInternalStateDict);

  FreeAndNil(FStartEvent);
  FreeAndNil(FNeedToStopEvent);
  FreeAndNil(FRestartEvent);
  FreeAndNil(FStopedEvent);

  FreeAndNil(FStatusGuard);
end;

procedure TWorkerThread.InitializeInternalStates;
begin
  FInternalStateDict := TDictionary<TWorkerStatus, TInternalState>.Create;

  FInternalIdleState := TInternalIdleState.Create(self);
  FInternalStartedState := TInternalStartedState.Create(self);
  FInternalStopedState := TInternalStopedState.Create(self);
  FInternalStartingState := TInternalStartingState.Create(self);
  FInternalRestartingState := TInternalRestartingState.Create(self);

  FInternalStateDict.Add(wsUnknown, FInternalIdleState);
  FInternalStateDict.Add(wsStarted, FInternalStartedState);
  FInternalStateDict.Add(wsStoped, FInternalStopedState);
  FInternalStateDict.Add(wsComplete, FInternalIdleState);
  FInternalStateDict.Add(wsError, FInternalIdleState);
  FInternalStateDict.Add(wsStarting, FInternalStartingState);
  FInternalStateDict.Add(wsRestarting, FInternalRestartingState);
  FInternalStateDict.Add(wsIdle, FInternalIdleState);

end;

procedure TWorkerThread.FreeInternalStates;
begin
  FreeAndNil(FInternalIdleState);
  FreeAndNil(FInternalStartedState);
  FreeAndNil(FInternalStopedState);
  FreeAndNil(FInternalStartingState);
  FreeAndNil(FInternalRestartingState);
end;

procedure TWorkerThread.Execute;
begin
  Log('Lookup execution started...');
  // these messages does not need to be localized: it debug time only

  try
    try

      repeat
        CurrentInternalState.Execute;

      until Terminated;

    finally
      FinishJob;
    end;

  except
    on E: Exception do
    begin
      Log('Error occured: ' + E.Message);
      WorkerStatus := wsError;
      FireOnError(CategoryWorkerThreadError, E.Message);
    end;
  end;

end;

procedure TWorkerThread.ExecuteJob;
begin

end;

procedure TWorkerThread.FireOnError(ErrorCode: integer; Message: string);
begin
  if Assigned(FOnError) then
    Synchronize(
      procedure
      begin
        FOnError(self, ErrorCode, Message);
      end);
end;

procedure TWorkerThread.FinishJob;
begin

end;

procedure TWorkerThread.FireOnComplete;
begin
  Log('Lookup directory complete');

  if Assigned(FOnComplete) then
    Synchronize(
      procedure
      begin
        FOnComplete(self);
      end);
end;

function TWorkerThread.GetCurrentInternalState: TInternalState;
begin
  result := FInternalState;
end;

function TWorkerThread.GetWorkerStatus: TWorkerStatus;
begin
  result := FWorkerStatus;
end;

procedure TWorkerThread.Log(Message: string);
begin
  Synchronize(
    procedure
    begin
      if Assigned(FOnLog) then
        FOnLog(self, Message);
    end);
end;

procedure TWorkerThread.PrepareJob;
begin

end;

procedure TWorkerThread.SetCurrentJobState(const Value: TState);
begin
  FCurrentJobState := Value;
end;

procedure TWorkerThread.SetOnComplete(const Value: TNotifyEvent);
begin
  FOnComplete := Value;
end;

procedure TWorkerThread.SetWorkerStatus(const Value: TWorkerStatus);
begin
  FStatusGuard.Acquire;
  try
    FStatus := Value;

    FInternalState := FInternalStateDict[Value];
  finally
    FStatusGuard.Release;
  end;
end;

procedure TWorkerThread.Start;
begin
  WorkerStatus := wsStarting;
  NeedToStopEvent.ResetEvent;
  StartEvent.SetEvent;
end;

procedure TWorkerThread.WaitStop;
begin
  repeat
    if StopedEvent.WaitFor(ThreadIdleTimeout) = wrSignaled then
      break;
  until Terminated;
end;

procedure TWorkerThread.SetOnError(const Value: TErrorEvent);
begin
  FOnError := Value;
end;

procedure TWorkerThread.SetOnLog(const Value: TLogEvent);
begin
  FOnLog := Value;
end;

procedure TWorkerThread.SetOnStart(const Value: TNotifyEvent);
begin
  FOnStart := Value;
end;

procedure TWorkerThread.SetOnStop(const Value: TNotifyEvent);
begin
  FOnStop := Value;
end;

procedure TWorkerThread.Restart;
begin
  WorkerStatus := wsRestarting;
  RestartEvent.SetEvent;
end;

procedure TWorkerThread.FireOnStart;
begin
  if Assigned(FOnStart) then
    Synchronize(
      procedure
      begin
        FOnStart(self);
      end);
end;

procedure TWorkerThread.Stop;
begin
  if WorkerStatus = wsStoped then
    exit;

  Log('Lookup directory stoped.');

  WorkerStatus := wsStoped;

  FireOnStop();

  StartEvent.ResetEvent;
  NeedToStopEvent.SetEvent;
end;

procedure TWorkerThread.FireOnStop();
begin
  if Assigned(FOnStop) then
    Synchronize(
      procedure
      begin
        FOnStop(self);
      end);
end;

end.
