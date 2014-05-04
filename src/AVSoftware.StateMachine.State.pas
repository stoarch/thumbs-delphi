{ *********************************************************

  AVSoftware State Machines

  Created by Afonin Vladimir

  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ********************************************************* }

unit AVSoftware.StateMachine.State;

interface

uses
  // --[ AVS COMMON ]--
  AVSoftware.Common.Events;

type
  TGuardProc = reference to function(): boolean;

type
  { TState

    goal: Generic state logic for state machine

    usage:

    1.Initialization
    state := TLookupState.Create;

    state.EnterGuard := function():boolean
    begin
    result := CanStartLookup;
    end;

    state.LeaveGuard := function():boolean
    begin
    result := CanLeaveLookup;
    end;

    state.OnEnter := Handle_LookupEnter;
    state.OnExecute := Handle_LookupExecute;
    state.OnLeave := Handle_LookupLeave;
    state.OnError := Handle_LookupError;

    2. State changes

    .1. When starting something

    state.Enter;

    .2. When stoping something

    state.Leave;


    [Functions:]
    * CanEnter: boolean - check if state can be entered
    * CanLeave: boolean - check if state can be leaved

    * Enter: boolean - tries to enter state, false - if guard conditions not met
    * Leave: boolean - tries to leave state

    [Methods:]

    * Execute - execute state logic once and exit

    [Properties:]
    * EnterGuard: TGuardProc - specifies check if state can enter
    * LeaveGuard: TGuardProc - specifies check if state can leave

    * Active - true if state in execution status

    [Events:]
    OnEnter: TNotifyEvent - fires when state entered (guard passed)
    OnExecute: TNotifyEvent - fires when state executed code once
    OnLeave: TNotifyEvent - fires when state leaves and cleanup (guard passed)
    OnError: TErrorEvent - fires when error occured during execution or transmission (fired by child classes) }

  TState = class
  private
    FEnterGuard: TGuardProc;
    FLeaveGuard: TGuardProc;

    FOnLeave: TNotificationEvent;
    FOnEnter: TNotificationEvent;
    FOnExecute: TNotificationEvent;
    FOnError: TErrorEvent;
    FActive: boolean;

    procedure FireOnExecute;

    procedure SetEnterGuard(const Value: TGuardProc);
    procedure SetLeaveGuard(const Value: TGuardProc);
    procedure SetOnEnter(const Value: TNotificationEvent);
    procedure SetOnLeave(const Value: TNotificationEvent);
    procedure SetOnExecute(const Value: TNotificationEvent);
    procedure SetOnError(const Value: TErrorEvent);
  protected
    function DoEnter: boolean; virtual;
    procedure DoError(ErrorCode: integer; ErrorMessage: string); virtual;
    function DoExecute: boolean; virtual;
    function DoLeave: boolean; virtual;
  public
    function CanEnter: boolean;
    function CanLeave: boolean;

    function Enter: boolean;
    function Execute: boolean;
    function Leave: boolean;

    property EnterGuard: TGuardProc read FEnterGuard write SetEnterGuard;
    property LeaveGuard: TGuardProc read FLeaveGuard write SetLeaveGuard;

    property OnEnter: TNotificationEvent read FOnEnter write SetOnEnter;
    property OnExecute: TNotificationEvent read FOnExecute write SetOnExecute;
    property OnLeave: TNotificationEvent read FOnLeave write SetOnLeave;
    property OnError: TErrorEvent read FOnError write SetOnError;

    property Active: boolean read FActive;
  end;

implementation

{ TState }

function TState.CanEnter: boolean;
begin
  if (Active) then
    exit(false);

  if not assigned(FEnterGuard) then
    exit(true);

  result := FEnterGuard();
end;

function TState.CanLeave: boolean;
begin
  if (not Active) then
    exit(false);

  if not assigned(FLeaveGuard) then
    exit(true);

  result := FLeaveGuard();
end;

function TState.DoEnter: boolean;
begin
  If assigned(FOnEnter) then
    FOnEnter(self);

  result := true;
end;

procedure TState.DoError(ErrorCode: integer; ErrorMessage: string);
begin
  if assigned(FOnError) then
    FOnError(self, ErrorCode, ErrorMessage);

end;

function TState.DoExecute: boolean;
begin
  FireOnExecute;

  result := true;
end;

function TState.DoLeave: boolean;
begin
  if assigned(FOnLeave) then
    FOnLeave(self);

  result := true;
end;

function TState.Enter: boolean;
begin
  if not CanEnter then
    exit(false);

  if (not DoEnter) then
    exit(false);

  FActive := true;

  result := true;
end;

function TState.Execute: boolean;
begin
  result := DoExecute;
end;

procedure TState.FireOnExecute;
begin
  if assigned(FOnExecute) then
    FOnExecute(self);
end;

function TState.Leave: boolean;
begin
  if not CanLeave then
    exit(false);

  DoLeave;

  FActive := false;

  result := true;
end;

procedure TState.SetEnterGuard(const Value: TGuardProc);
begin
  FEnterGuard := Value;
end;

procedure TState.SetLeaveGuard(const Value: TGuardProc);
begin
  FLeaveGuard := Value;
end;

procedure TState.SetOnEnter(const Value: TNotificationEvent);
begin
  FOnEnter := Value;
end;

procedure TState.SetOnError(const Value: TErrorEvent);
begin
  FOnError := Value;
end;

procedure TState.SetOnExecute(const Value: TNotificationEvent);
begin
  FOnExecute := Value;
end;

procedure TState.SetOnLeave(const Value: TNotificationEvent);
begin
  FOnLeave := Value;
end;

end.
