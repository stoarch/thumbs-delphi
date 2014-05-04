{ *******************************************************

  AVSoftware Thumbnails Browser

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }

unit AVSoftware.Threaded.DirectoryLookup;

interface

uses
  // COMMON
  System.Classes, System.SysUtils, System.SyncObjs, System.Generics.Collections,
  System.TypInfo, System.IOUtils, System.Types,
  // AVS COMMON
  AVSoftware.Common.Events,
  // DIRECTORY LOOKUP
  AVSoftware.DirectoryLookup.Events,
  // STATES
  AVSoftware.StateMachine.State,
  AVSoftware.StateMachine.DirectoryLookup.JobState.IncrementalReceiver,
  // THREADS
  AVSoftware.Threaded.WorkerThread;

const
  DirectoryLookupError = $A00002;

type
  TIdleJobState = class(TState)

  end;

type
  { TDirectoryLookupThread

    Thread to lookup files or subdirs of specified path.

    Info:
    1. You can setup callbacks, start, stop searches
    2. Callbacks: for found chunk of dirs, for error
    messages, for lookup start and completion
    3. Events synchronised with main thread, so you can
    treat it as normal
    4. For debugging purposes you can attach OnLog event handler

    Usage:
    1. Setup:

    instance := TDirectoryLookupThread.Create(true); //suspended
    instance.Directory := 'c:\';
    instance.ChunkSize := 5; //dirs at once
    instance.Attribute := faDirectory; //or any SysUtils file attributes
    instance.FileMask := '*.*'

    instance.OnError := Handle_LookupError;
    instance.OnStart := Handle_LookupStart;
    instance.OnProgress := Handle_LookupProgress;
    instance.OnStop := Handle_LookupStop;
    instance.OnCompleted := Handle_LookupComplete;

    2. Launch

    instance.Start

    3. Abnormal stop (when this directory is closed and
    no scanning needed to proceed)

    instance.Stop


    4. If you decided to force restart,use:

    instance.Restart( newDirectory )


    [Properties:]
    * Directory - which subdirectories to lookup
    * ChunkSize - how much directories need to found before
    event firing
    * Status - which state is lookuper now (read only)
    * Attribute - for file to seek (i.e. faDirectory, faSystem e.t.c)
    * FileMask - of files to search (filter)

    [Events:]
    * OnError - fires when thread encounter system error on lookup
    * OnStart - fires when thread start looking up directories
    * OnProgress - fires when thread found new chunk of directories
    * OnStop - fires when thread abnormally stoped by user
    * OnCompleted - fires when thread found no more directories
    * OnLog - fires when something technical happened (for debugging)

    [Methods:]
    * Start - start scanning, resumes thread and fires event
    * Stop - stop and reset search and frees all resources,
    suspend thread for future changes of params
    * Stop( wait, timeout ) - stop scanning and wait until finished
    * Restart( newDir ) - stops/set new config/start with new config scanning }

  TDirectoryLookupThread = class(TWorkerThread)
  private
    FAccessor: TCriticalSection;

    FChunkSize: integer;

    FDirectory: string;
    FFoundDirectories: TArray<String>;

    FAttribute: integer;
    FFileMask: string;

    FOnProgress: TLookupProgressEvent;

    FIdleJobState: TIdleJobState;
    FLookupJobState: TIncrementalReceiverJobState;

    procedure ChangeJobStateIdleToLookup;
    procedure ChangeJobStateLookupToIdle;

    procedure FireOnProgress();

    function GetAttribute: integer;
    function GetChunkSize: integer;
    function GetDirectory: string;
    function GetFileMask: string;
    function GetFoundDirectories: TArray<String>;

    procedure HandleLookupComplete(sender: TObject);
    procedure HandleLookupEnter(sender: TObject);
    procedure HandleLookupError(sender: TObject; ErrorCode: integer;
      ErrorMessage: string);
    procedure HandleLookupExecute(sender: TObject);
    procedure HandleLookupLeave(sender: TObject);
    procedure HandleLookupProgress(sender: TObject;
      NewDirectories: array of string);

    procedure InitializeIdleJobState;
    procedure InitializeLookupJobState;
    procedure InitializeJobStateMachine;

    function PrepareAndStart: boolean;

    procedure SetAttribute(const Value: integer);
    procedure SetChunkSize(const Value: integer);
    procedure SetDirectory(const Value: string);
    procedure SetFileMask(const Value: string);
    procedure SetOnProgress(const Value: TLookupProgressEvent);
    procedure FreeDirectoryLookup(const Value: TLookupProgressEvent);

  protected
    procedure ExecuteJob; override;
    procedure FinishJob; override;
    procedure PrepareJob; override;

    procedure HandleOnTerminate(sender: TObject); override;

  public
    constructor Create;

    property OnProgress: TLookupProgressEvent read FOnProgress
      write SetOnProgress;

    // --[ Properties ]--
    property Directory: string read GetDirectory write SetDirectory;
    property ChunkSize: integer read GetChunkSize write SetChunkSize;
    property Attribute: integer read GetAttribute write SetAttribute;
    property FileMask: string read GetFileMask write SetFileMask;

  end;

implementation

const
  ThreadIdleTimeout = 100;

  { TDirectoryLookupThread }

constructor TDirectoryLookupThread.Create;
begin
  inherited;

  FAccessor := TCriticalSection.Create();

  InitializeJobStateMachine;

end;

procedure TDirectoryLookupThread.FreeDirectoryLookup
  (const Value: TLookupProgressEvent);
begin
  FOnProgress := Value;
end;

procedure TDirectoryLookupThread.ExecuteJob;
begin
  if not CurrentJobState.Execute then
    ChangeJobStateLookupToIdle;
end;

procedure TDirectoryLookupThread.FinishJob;
begin
  inherited;
  ChangeJobStateLookupToIdle;
end;

procedure TDirectoryLookupThread.HandleOnTerminate(sender: TObject);
begin
  inherited;

  FreeAndNil(FIdleJobState);
  FreeAndNil(FLookupJobState);
  FreeAndNil(FAccessor);

end;

procedure TDirectoryLookupThread.InitializeJobStateMachine;
begin
  InitializeIdleJobState;
  InitializeLookupJobState;
end;

procedure TDirectoryLookupThread.InitializeIdleJobState;
begin
  FIdleJobState := TIdleJobState.Create;
end;

procedure TDirectoryLookupThread.InitializeLookupJobState;
begin
  FLookupJobState := TIncrementalReceiverJobState.Create;

  FLookupJobState.OnEnter := HandleLookupEnter;
  FLookupJobState.OnExecute := HandleLookupExecute;
  FLookupJobState.OnLeave := HandleLookupLeave;

  FLookupJobState.OnError := HandleLookupError;

  FLookupJobState.OnProgress := HandleLookupProgress;
  FLookupJobState.OnComplete := HandleLookupComplete;
end;

procedure TDirectoryLookupThread.HandleLookupEnter(sender: TObject);
begin
  // do nothing
end;

procedure TDirectoryLookupThread.HandleLookupLeave(sender: TObject);
begin
  // do nothing
end;

procedure TDirectoryLookupThread.HandleLookupExecute(sender: TObject);
begin
  // do nothing
end;

procedure TDirectoryLookupThread.HandleLookupError(sender: TObject;
  ErrorCode: integer; ErrorMessage: string);
begin
  FireOnError(ErrorCode, ErrorMessage);
end;

procedure TDirectoryLookupThread.HandleLookupProgress(sender: TObject;
  NewDirectories: array of string);
var
  I: integer;
  Count: integer;
begin
  Count := Length(NewDirectories);
  SetLength(FFoundDirectories, Count);

  for I := 0 to Count - 1 do
    FFoundDirectories[I] := FDirectory + '\' + NewDirectories[I];

  FireOnProgress;
end;

procedure TDirectoryLookupThread.HandleLookupComplete(sender: TObject);
begin
  FireOnComplete();
  Stop;
end;

procedure TDirectoryLookupThread.ChangeJobStateIdleToLookup;
begin
  FIdleJobState.Leave;
  FLookupJobState.Enter;
  CurrentJobState := FLookupJobState;
end;

procedure TDirectoryLookupThread.ChangeJobStateLookupToIdle;
begin
  FLookupJobState.Leave;
  FIdleJobState.Enter;
  CurrentJobState := FIdleJobState;
end;

function TDirectoryLookupThread.GetAttribute: integer;
begin
  FAccessor.Enter;
  try
    result := FAttribute;
  finally
    FAccessor.Leave;
  end;
end;

function TDirectoryLookupThread.GetChunkSize: integer;
begin
  FAccessor.Enter;
  try
    result := FChunkSize;
  finally
    FAccessor.Leave;
  end;
end;

function TDirectoryLookupThread.GetDirectory: string;
begin
  FAccessor.Enter;
  try
    result := FDirectory;
  finally
    FAccessor.Leave;
  end;
end;

function TDirectoryLookupThread.GetFileMask: string;
begin
  FAccessor.Enter;
  try
    result := FFileMask;
  finally
    FAccessor.Leave;
  end;

end;

function TDirectoryLookupThread.GetFoundDirectories(): TArray<String>;
begin
  result := FFoundDirectories;
end;

procedure TDirectoryLookupThread.SetAttribute(const Value: integer);
begin
  FAccessor.Enter;
  try
    FAttribute := Value;
  finally
    FAccessor.Leave;
  end;
end;

procedure TDirectoryLookupThread.SetChunkSize(const Value: integer);
begin
  FAccessor.Enter;
  try
    FChunkSize := Value;
  finally
    FAccessor.Leave;
  end;
end;

procedure TDirectoryLookupThread.SetDirectory(const Value: string);
begin
  FAccessor.Enter;
  try
    FDirectory := Value;
  finally
    FAccessor.Leave;
  end;

end;

procedure TDirectoryLookupThread.SetFileMask(const Value: string);
begin
  FAccessor.Enter;
  try
    FFileMask := Value;
  finally
    FAccessor.Leave;
  end;
end;

procedure TDirectoryLookupThread.SetOnProgress(const Value
  : TLookupProgressEvent);
begin
  FAccessor.Enter;
  try
    FreeDirectoryLookup(Value);
  finally
    FAccessor.Leave;
  end;
end;

function TDirectoryLookupThread.PrepareAndStart: boolean;
begin
  if WorkerStatus = wsStarted then
    exit(false);

  FLookupJobState.FileMask := FFileMask;
  FLookupJobState.Directory := FDirectory;
  FLookupJobState.Attribute := FAttribute;
  FLookupJobState.ChunkSize := FChunkSize;

  if (not FLookupJobState.Enter) then
  begin
    FireOnError(DirectoryLookupError, 'Unable to lookup');
    WorkerStatus := wsError;
    exit(false);
  end
  else
  begin
    WorkerStatus := wsStarted;
    FireOnStart();
    StartEvent.SetEvent;
    exit(true);
  end;
end;

procedure TDirectoryLookupThread.FireOnProgress();
begin
  if Assigned(FOnProgress) then
    (FOnProgress(self, (GetFoundDirectories)));
end;

procedure TDirectoryLookupThread.PrepareJob;
begin
  inherited;

  if PrepareAndStart then // initialization succeeded
    ChangeJobStateIdleToLookup;
end;

end.
