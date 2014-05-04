unit AVSoftware.StateMachine.DirectoryLookupJobState;

interface

type
  { TDirectoryLookupJobState

    goal: Provide lookup steps when searching and cleanup search on leave

    info: This state generate directories by chunkSize items every time
    And can be useful when connection is slow

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

    state.OnProgress := Handle_LookupProgress;
    state.OnComplete := Handle_LookupComplete;

    state.Attribute := faDirectory;
    state.FileMask := '*.*';
    state.Directory := 'c:\images';
    state.ChunkSize := 10; //items to collect before fire progress


    2. State changes

    .1. When starting lookup

    state.Enter;

    .2. When stoping lookup

    state.Leave;


    [Properties:]
    * Directory - which subdirectories to lookup
    * ChunkSize - how much directories need to found before
    event firing
    * Attribute - for file to seek (i.e. faDirectory, faSystem e.t.c)
    * FileMask - of files to search (filter)

    [Events:]
    * OnError - fires when state encounter system error on lookup
    * OnStart - fires when state start looking up directories
    * OnProgress - fires when state found new chunk of directories
    * OnComplete - fires when thread found no more directories }

  TDirectoryLookupGetIncrementalJobState = class(TState)
  private
    FSearchRec: TSearchRec;
    FDirectory: string;
    FFileMask: string;
    FSingleExtension: boolean;
    FExtensions: TArray<String>;
    FAttribute: integer;

    FChunk: TQueue<String>;
    FChunkSize: integer;
    FOnComplete: TNotifyEvent;
    FOnProgress: TLookupProgressEvent;

    procedure CleanChunk;

    procedure DoComplete;
    function DoLookupStep: boolean;
    procedure DoProgress;

    function FindNextAndCheckLastFound: boolean;
    function IsExtensionExists(ext: string): boolean;
    function PrepareScan: boolean;

    procedure SetAttribute(const Value: integer);
    procedure SetChunkSize(const Value: integer);
    procedure SetDirectory(const Value: string);
    procedure SetFileMask(const Value: string);
    procedure SetOnComplete(const Value: TNotifyEvent);
    procedure SetOnProgress(const Value: TLookupProgressEvent);

  protected
    function DoEnter: boolean; override;
    function DoLeave: boolean; override;
    function DoExecute: boolean; override;

    function PrepareToEnter: boolean; virtual;
    function PrepareToLeave: boolean; virtual;

    function GetFoundFiles: TStringArray; virtual;
    procedure CleanUp; virtual;

  public
    destructor Destroy; override;

    property Attribute: integer read FAttribute write SetAttribute;
    property ChunkSize: integer read FChunkSize write SetChunkSize;
    property Directory: string read FDirectory write SetDirectory;
    property FileMask: string read FFileMask write SetFileMask;

    property OnProgress: TLookupProgressEvent read FOnProgress
      write SetOnProgress;
    property OnComplete: TNotifyEvent read FOnComplete write SetOnComplete;
  end;

implementation

{ TDirectoryLookupJobState }

const
  fsAllOk = 0;
  fsNoMoreFiles = 18;

procedure TDirectoryLookupGetIncrementalJobState.CleanUp;
begin
  if (Active) then
    FindClose(FSearchRec);

  CleanChunk;
end;

destructor TDirectoryLookupGetIncrementalJobState.Destroy;
begin
  CleanUp;

  inherited;
end;

procedure TDirectoryLookupGetIncrementalJobState.CleanChunk;
begin
  if Assigned(FChunk) then
    FreeAndNil(FChunk);
end;

function TDirectoryLookupGetIncrementalJobState.DoEnter: boolean;
begin
  inherited;

  result := PrepareToEnter;
end;

function TDirectoryLookupGetIncrementalJobState.DoExecute: boolean;
begin
  inherited;

  result := DoLookupStep;
end;

function TDirectoryLookupGetIncrementalJobState.DoLeave: boolean;
begin
  inherited;

  result := PrepareToLeave;
end;

function TDirectoryLookupGetIncrementalJobState.DoLookupStep: boolean;
var
  Extension: string;
begin
  if (FSearchRec.Name = '.') or (FSearchRec.Name = '..') then
  begin
    exit(FindNextAndCheckLastFound);
  end;

  if (FSearchRec.Attr and FAttribute = 0) then
  // selected attribs is ours: directory or archive e.t.c.
  begin
    exit(FindNextAndCheckLastFound);
  end;

  if FSingleExtension then
    FChunk.Enqueue(FSearchRec.Name)
  else
  begin
    Extension := UpperCase(ExtractFileExt(FSearchRec.Name));

    if (IsExtensionExists(Extension)) then
      FChunk.Enqueue(FSearchRec.Name);
  end;

  if (FChunk.Count >= FChunkSize) then
  begin
    DoProgress;
    FChunk.Clear;
    FChunk.TrimExcess;
  end;

  result := FindNextAndCheckLastFound;
end;

procedure TDirectoryLookupGetIncrementalJobState.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(self, GetFoundFiles);
end;

function TDirectoryLookupGetIncrementalJobState.GetFoundFiles(): TStringArray;
var
  I: integer;
begin
  SetLength(result, FChunk.Count);
  I := 0;

  while FChunk.Count > 0 do
  begin
    result[I] := FChunk.Extract;
    I := I + 1;
  end;
end;

function TDirectoryLookupGetIncrementalJobState.FindNextAndCheckLastFound: boolean;
var
  FindResult: integer;
begin
  FindResult := FindNext(FSearchRec);

  if FindResult <> fsAllOk then
  begin
    if (FindResult <> fsNoMoreFiles) then // no more files
    begin
      DoError(FindResult, SysErrorMessage(FindResult));
      Sleep(1000);

      exit(False);
    end;

    if FChunk.Count > 0 then
      // small number of files need to be processed another way
      DoProgress;

    FindClose(FSearchRec);

    FChunk.Clear;
    DoComplete;

    exit(False); // no more files to work with
  end;

  result := True;
end;

procedure TDirectoryLookupGetIncrementalJobState.DoComplete;
begin
  if Assigned(FOnComplete) then
    FOnComplete(self);
end;

function TDirectoryLookupGetIncrementalJobState.IsExtensionExists(ext: string): boolean;
var
  Item: string;
begin
  for Item in FExtensions do
  begin
    if (Item = ext) then
      exit(True);
  end;

  result := False;
end;

function TDirectoryLookupGetIncrementalJobState.PrepareScan: boolean;
var
  FindResult: integer;
begin
  if (FDirectory = '') then
    exit(False);
  if (FFileMask = '') then
    exit(False);

  FChunk := TQueue<String>.Create;

  FSingleExtension := True;

  if (pos(',', FFileMask) = 0) then
    FindResult := FindFirst(FDirectory + '\' + FFileMask, FAttribute,
      FSearchRec)
  else
  begin
    FindResult := FindFirst(FDirectory + '\' + '*.*', FAttribute, FSearchRec);

    FSingleExtension := False;
    FExtensions := UpperCase(FFileMask).Split([',']);

  end;

  if (FindResult <> fsAllOk) then
  begin
    DoError(DIRECTORY_LOOKUP_ERROR, 'Find file error:' + IntToStr(FindResult) +
      ' > ' + SysErrorMessage(FindResult));

    FindClose(FSearchRec);
    CleanChunk;

    exit(False);
  end;

  result := True;
end;

function TDirectoryLookupGetIncrementalJobState.PrepareToEnter: boolean;
begin
  result := PrepareScan
end;

function TDirectoryLookupGetIncrementalJobState.PrepareToLeave: boolean;
begin
  FindClose(FSearchRec);
  CleanChunk;

  result := True;
end;

procedure TDirectoryLookupGetIncrementalJobState.SetAttribute(const Value: integer);
begin
  FAttribute := Value;
end;

procedure TDirectoryLookupGetIncrementalJobState.SetChunkSize(const Value: integer);
begin
  FChunkSize := Value;
end;

procedure TDirectoryLookupGetIncrementalJobState.SetDirectory(const Value: string);
begin
  FDirectory := Value;
end;

procedure TDirectoryLookupGetIncrementalJobState.SetFileMask(const Value: string);
begin
  FFileMask := Value;
end;

procedure TDirectoryLookupGetIncrementalJobState.SetOnComplete(const Value: TNotifyEvent);
begin
  FOnComplete := Value;
end;

procedure TDirectoryLookupGetIncrementalJobState.SetOnProgress(const Value: TLookupProgressEvent);
begin
  FOnProgress := Value;
end;

end.
