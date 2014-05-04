{ *******************************************************

  AVSoftware Thumbnails Browser

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }

unit AVSoftware.DirectoryLookup.LookupManager;

interface

uses
  // common
  System.Classes, System.Generics.Collections, System.SysUtils,
  // avs common
  AVSoftware.Common.Events,
  // pools
  AVSoftware.Pools.DirectoryLookupPool,
  // threads
  AVSoftware.Threaded.DirectoryLookup;

type
  {
    TLookupManager

    goal:

    Lookup directories and files and change data (directory tree, files list)

    info:

    1. Only error is propogated to form

    2. All events of data changes propagated by usage of
    NotificationLists/Trees/Objects (pattern: Subscriber)

    3. Handling of directory lookup and file lookup simplified
    by facade: you only need to start/stop/restart

  }
  TLookupManager = class
  private
    FDirectoryLookup: TDirectoryLookupThread;
    FDirectories: TList<String>;
    FRootDirectory: String;
    FOnError: TErrorEvent;
    FOnLog: TLogEvent;
    FOnComplete: TNotifyEvent;
    FOnStart: TNotifyEvent;
    FOnStop: TNotifyEvent;

    procedure InitDirectoryLookup;
    procedure SetRootDirectory(const Value: String);
    procedure HandleDirRefreshError(Sender: TObject; Error: Integer;
      ErrorMessage: String);
    procedure HandleDirRefreshProgress(Sender: TObject;
      NewDirectories: Array Of String);
    procedure HandleDirRefreshStart(Sender: TObject);
    procedure HandleDirRefreshStop(Sender: TObject);
    procedure SetOnError(const Value: TErrorEvent);
    procedure FireOnError(ErrorCode: Integer; ErrorMessage: String);
    procedure HandleOnLog(Sender: TObject; Message: String);
    procedure SetOnLog(const Value: TLogEvent);
    procedure SetOnComplete(const Value: TNotifyEvent);
    procedure SetOnStart(const Value: TNotifyEvent);
    procedure FireOnStart;
    procedure FireOnStop;
    procedure SetOnStop(const Value: TNotifyEvent);
    procedure FireOnLog(Message: String);
    procedure FreeDirectoryLookup;

  public
    constructor Create;
    destructor Destroy; override;

    procedure RestartAt(NewDirectory: String);
    procedure Start;

    property DirectoryLookupThread: TDirectoryLookupThread
      read FDirectoryLookup;
    property Directories: TList<String> read FDirectories;
    property RootDirectory: String read FRootDirectory write SetRootDirectory;

    property OnError: TErrorEvent read FOnError write SetOnError;
    property OnLog: TLogEvent read FOnLog write SetOnLog;
    property OnStart: TNotifyEvent read FOnStart write SetOnStart;
    property OnStop: TNotifyEvent read FOnStop write SetOnStop;
    property OnComplete: TNotifyEvent read FOnComplete write SetOnComplete;
  end;

implementation

{ TLookupManager }

constructor TLookupManager.Create;
begin
  FDirectories := TList<String>.Create;

end;

destructor TLookupManager.Destroy;
begin
  FreeDirectoryLookup;

  if assigned(FDirectories) then
    FreeAndNil(FDirectories)
  else
    FireOnLog(
      'LookupManager::Destroy Already freed FDirectories, that is bug...');

  inherited;
end;

procedure TLookupManager.FireOnLog(Message: string);
begin
  if assigned(FOnLog) then
    FOnLog(self, Message);
end;

procedure TLookupManager.InitDirectoryLookup;
begin
  if (not assigned(FDirectoryLookup)) then
    FDirectoryLookup := DirectoryLookupPool.Aquire;

  // attribs
  FDirectoryLookup.Directory := FRootDirectory;
  // dirs to handle at once
  FDirectoryLookup.ChunkSize := 100; // dirs at once
  FDirectoryLookup.Attribute := faDirectory;
  FDirectoryLookup.FileMask := '*.*';

  // events
  FDirectoryLookup.OnStart := HandleDirRefreshStart;
  FDirectoryLookup.OnStop := HandleDirRefreshStop;
  FDirectoryLookup.OnProgress := HandleDirRefreshProgress;
  FDirectoryLookup.OnError := HandleDirRefreshError;
  FDirectoryLookup.OnLog := HandleOnLog;
end;

procedure TLookupManager.RestartAt(NewDirectory: String);
begin
  FRootDirectory := NewDirectory;

  InitDirectoryLookup;

  FDirectoryLookup.Directory := FRootDirectory;
  FDirectoryLookup.Restart();
end;

procedure TLookupManager.HandleOnLog(Sender: TObject; Message: string);
begin
  if assigned(FOnLog) then
    FOnLog(self, Message);
end;

procedure TLookupManager.SetOnComplete(const Value: TNotifyEvent);
begin
  FOnComplete := Value;
end;

procedure TLookupManager.SetOnError(const Value: TErrorEvent);
begin
  FOnError := Value;
end;

procedure TLookupManager.SetOnLog(const Value: TLogEvent);
begin
  FOnLog := Value;
end;

procedure TLookupManager.SetOnStart(const Value: TNotifyEvent);
begin
  FOnStart := Value;
end;

procedure TLookupManager.SetOnStop(const Value: TNotifyEvent);
begin
  FOnStop := Value;
end;

procedure TLookupManager.SetRootDirectory(const Value: string);
begin
  FRootDirectory := Value;
end;

procedure TLookupManager.Start;
begin
  InitDirectoryLookup;
  FDirectoryLookup.Start;
end;

procedure TLookupManager.FreeDirectoryLookup;
begin
  if assigned(FDirectoryLookup) then
  begin
    FDirectoryLookup.OnProgress := nil;
    FDirectoryLookup.OnStart := nil;
    FDirectoryLookup.OnStop := nil;
    FDirectoryLookup.OnError := nil;
    FDirectoryLookup.OnComplete := nil;
    FDirectoryLookup.OnLog := nil;
    FDirectoryLookup.OnTerminate := nil;

    DirectoryLookupPool.Release(FDirectoryLookup);
    FDirectoryLookup := nil;
  end;
end;

procedure TLookupManager.FireOnStart;
begin
  if assigned(FOnStart) then
    FOnStart(self);
end;

procedure TLookupManager.FireOnStop;
begin
  if assigned(FOnStop) then
    FOnStop(self);
end;

procedure TLookupManager.FireOnError(ErrorCode: Integer; ErrorMessage: string);
begin
  if assigned(FOnError) then
    FOnError(self, ErrorCode, ErrorMessage);
end;

{ Directory lookup event handlers }

procedure TLookupManager.HandleDirRefreshError(Sender: TObject; Error: Integer;
  ErrorMessage: string);
begin
  FireOnError(Error, ErrorMessage);
  FreeDirectoryLookup;
end;

procedure TLookupManager.HandleDirRefreshStart(Sender: TObject);
begin
  FDirectories.Clear;
  FireOnStart;
end;

procedure TLookupManager.HandleDirRefreshStop(Sender: TObject);
begin
  FireOnStop;
  FreeDirectoryLookup;
end;

procedure TLookupManager.HandleDirRefreshProgress(Sender: TObject;
  NewDirectories: array of string);
begin
  FDirectories.AddRange(NewDirectories);
end;

end.
