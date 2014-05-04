unit form_main;

{$DEFINE DEBUG_DIRS}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, System.IOUtils, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.Menus, Vcl.ComCtrls, Vcl.StdCtrls,
  Vcl.ImgList, Vcl.ExtCtrls, System.Types,
  System.SyncObjs, jpeg, pngimage, System.DateUtils,
  // --[ common ]--
  AVSoftware.Common.Events,
  // --[ threads ]--
  AVSoftware.Threaded.DirectoryLookup,
  AVSoftware.Threaded.ThumbnailGenerator;

type
  // ##[ GlobalLog ]##
  //
  // goal: Store global log
  //
  GlobalLog = class
  private
    class var FLog: TThreadedQueue<String>;

    class procedure CheckOrCreateLog;
  public
    class procedure Write(message: string);
    class function Extract(): string;

    class function HasEntries(): boolean;

    class procedure CleanUp();
  end;

  // ##[ TLookupManager ]##
  //
  // goal: Lookup directories and files and change
  // data (directory tree, files list)
  //
  // info:
  // 1. Only error is propogated to form
  // 2. All events of data changes propagated by usage of
  // NotificationLists/Trees/Objects (patter: Subscriber)
  // 3. Handling of directory lookup and file lookup simplified
  // by facade: you only need to start/stop/restart
  //
  //
  TLookupManager = class
  private
    FDirectoryLookup: TDirectoryLookupThread;
    FDirectories: TList<String>;
    FRootDirectory: string;
    FOnError: TErrorEvent;
    FOnLog: TLogEvent;
    FOnComplete: TNotifyEvent;
    FOnStart: TNotifyEvent;
    FOnStop: TNotifyEvent;
    procedure InitDirectoryLookup;
    procedure SetRootDirectory(const Value: string);
    procedure Handle_DirRefreshError(sender: TObject; error: integer;
      error_message: string);
    procedure Handle_DirRefreshProgress(sender: TObject; dirs: array of string);
    procedure Handle_DirRefreshStart(sender: TObject);
    procedure Handle_DirRefreshStop(sender: TObject);
    procedure SetOnError(const Value: TErrorEvent);
    procedure DoError(errorCode: integer; errorMessage: string);
    procedure Handle_Log(sender: TObject; message: string);
    procedure SetOnLog(const Value: TLogEvent);
    procedure SetOnComplete(const Value: TNotifyEvent);
    procedure SetOnStart(const Value: TNotifyEvent);
    procedure DoStart;
    procedure DoStop;
    procedure SetOnStop(const Value: TNotifyEvent);
    procedure DoLog(message: string);

  public
    constructor Create;
    destructor Destroy; override;

    procedure Start;
    procedure Restart(newDirectory: String);

    property DirectoryLookup: TDirectoryLookupThread read FDirectoryLookup;

    property RootDirectory: string read FRootDirectory write SetRootDirectory;

    property Directories: TList<String> read FDirectories;

    property OnError: TErrorEvent read FOnError write SetOnError;
    property OnLog: TLogEvent read FOnLog write SetOnLog;
    property OnStart: TNotifyEvent read FOnStart write SetOnStart;
    property OnStop: TNotifyEvent read FOnStop write SetOnStop;
    property OnComplete: TNotifyEvent read FOnComplete write SetOnComplete;
  end;

type
  // ##[ TNodeInfo ]##
  //
  // goal: Contain and provide lookup manager and nodeDict for tree node
  //
  TNodeInfo = class
  private
    FLookupManager: TLookupManager;
    FNodesDict: TDictionary<String, TTreeNode>;
    FNode: TTreeNode;
    FRootDirectory: string;
    FDirectories: TList<String>;

    procedure SetLookupManager(const Value: TLookupManager);
    procedure SetNode(const Value: TTreeNode);
    procedure SetRootDirectory(const Value: string);
    procedure Handle_LookupError(sender: TObject; error: integer;
      error_message: string);
    procedure Handle_LookupStart(sender: TObject);
    procedure Handle_LookupStop(sender: TObject);
    procedure Handle_Log(sender: TObject; message: string);
    procedure Handle_DirectoryListNotification(sender: TObject;
      const Item: String; Action: TCollectionNotification);
    procedure RemoveDirectoryItem(dir: string);
  public
    constructor Create;
    destructor Destroy; override;

    function TryFindNode(dirName: string; var resNode: TTreeNode): boolean;

    procedure AddNode(dirName: string; node: TTreeNode);

    procedure StartLookup;
    procedure RestartLookup(dir: string);

    property Directories: TList<String> read FDirectories;

    property RootDirectory: string read FRootDirectory write SetRootDirectory;
    property node: TTreeNode read FNode write SetNode;

    property NodesDict: TDictionary<String, TTreeNode> read FNodesDict;
    property LookupManager: TLookupManager read FLookupManager
      write SetLookupManager;
  end;

  // ##[ TEmptyNodeInfo ]##
  //
  // goal: Null class for TNodeInfo
  //
  // info:
  // 1. This is singleton class with one instance
  // 2. Each methods is overriden to avoid errors (do nothing)
  //
  TEmptyNodeInfo = class(TNodeInfo)
  private
    class var FInstance: TEmptyNodeInfo;

    constructor Create;
  public
    class function Instance: TEmptyNodeInfo;
    class procedure CleanUp;
  end;

  // ##[ TTreeNodeNodeInfoExtractor ]##
  //
  // kind: class helper
  //
  // goal: Extract NodeInfo from Data (if availabled) or return
  // EmptyNodeInfo.Instance instead
  //
  TTreeNodeNodeInfoExtractor = class helper for TTreeNode
  private
    function GetNodeInfo: TNodeInfo;
  public
    property NodeInfo: TNodeInfo read GetNodeInfo;
  end;

type
  // ##[ TThumbnailDisplayerForm
  //
  // goal: Load and display thumbnails for directories.
  // Provide navigation with asynchronous and lag
  // free loading of images thumbs
  //
  // info:
  // 1. This form uses threads for heavy lifting. User
  // interface only display result of their work
  //
  // 2. DirectoryLookupThread used for searching content
  // of directory by specific file mask and attribute.
  // This form has two threads scanners: one - for directory
  // structure lookup (subdirs), another - for image file search
  //
  // 3. For thumbnail generation this form uses ThumbnailGeneratorThread
  // which can generate thumbnails for images and return list of images
  // to display
  //
  //
  TThumbnailDisplayerMainForm = class(TForm)
    MainMenu: TMainMenu;
    File1: TMenuItem;
    FileExitMenuItem: TMenuItem;
    Help1: TMenuItem;
    HelpAboutMenuItem: TMenuItem;
    DirectoryTreeView: TTreeView;
    StatusBar: TStatusBar;
    Label1: TLabel;
    ThumbnailListView: TListView;
    Label2: TLabel;
    Thumbnails_ImageList: TImageList;
    DirRefreshProgress_Animate: TAnimate;
    filesLookupProgress_Animate: TAnimate;
    DirErrorPopupPanel: TPanel;
    DirErrorPopupAnimationTimer: TTimer;
    LogMemo: TMemo;
    FilesLookupErrorPopupPanel: TPanel;
    loadingProgressBar: TProgressBar;
    TreeStates_ImageList: TImageList;
    DirLookupStatusShape: TShape;
    FileLookupStatusShape: TShape;
    ThumbGeneratorStatusShape: TShape;
    messageCheckerTimer: TTimer;
    procedure FileExitMenuItemClick(sender: TObject);
    procedure FormActivate(sender: TObject);
    procedure FormResize(sender: TObject);
    procedure DirectoryTreeViewChange(sender: TObject; node: TTreeNode);
    procedure DirectoryTreeViewDblClick(sender: TObject);
    procedure messageCheckerTimerTimer(sender: TObject);
    procedure DirectoryTreeViewDeletion(sender: TObject; node: TTreeNode);
    procedure HelpAboutMenuItemClick(sender: TObject);
  private
    FFilesLookup: TDirectoryLookupThread;
    FThumbGenerator: TThumbnailGeneratorThread;

    FNodeInfoList: TObjectList<TNodeInfo>;

    FInitializing: boolean;

    FFilesDict: TDictionary<String, TListItem>;
    FRootDirectory: string;

    procedure Handle_Log(sender: TObject; message: string);
    procedure Log(message: string);
    procedure SelectDirectoryForSelectedNode(dir_name: string);
    procedure AddDirectoryTree(node: TTreeNode; curDir: string);
    function AddSubDirectoryAt(node: TTreeNode; dirName: string): TTreeNode;
    procedure InitFileLookuper(root_dir: string);
    procedure Handle_FilesLookupError(sender: TObject; error: integer;
      error_message: string);
    procedure Handle_FilesLookupProgress(sender: TObject;
      files: array of string);
    procedure Handle_FilesLookupStart(sender: TObject);
    procedure Handle_FilesLookupStop(sender: TObject);
    procedure AddNewFile(curFile: string);
    procedure InitThumbnailGenerator;
    procedure Handle_ThumbnailComplete(sender: TObject;
      images: TImageInfoArray);
    procedure Handle_ThumbnailError(sender: TObject; errorCode: integer;
      errorMessage: string);
    procedure SetImageIndexFor(imageNo, index: integer); overload;
    procedure SetImageIndexFor(fileName: string; index: integer); overload;
    function ExpandToFullPath(files: array of string): TStringArray; overload;
    function ExpandToFullPath(fileName: string): string; overload;
    function GetNodeFullPath(node: TTreeNode): String;
    procedure Handle_ThumbnailReset(sender: TObject);
    procedure DirectoryLookupStart(node: TTreeNode);
    procedure DirectoryLookupRestart(node: TTreeNode; dir: string);
    procedure SelectDirectoryAt(node: TTreeNode; dirName: string);
    { Private declarations }
  public
    { Public declarations }
    constructor Create(aowner: TComponent); override;
    destructor Destroy; override;

    property RootDirectory: string read FRootDirectory;
  end;

var
  ThumbnailDisplayerMainForm: TThumbnailDisplayerMainForm;

procedure PropagateError(errorCode: integer; errorMessage: String);

implementation

{$R *.dfm}

uses form_about;

resourcestring
  STR_UNKNOWN_ERROR = 'Unknown errror';
  STR_DISK_ERROR = 'Disk error occured';

const
  ERROR_CATEGORY_SYSTEM = $100000;
  ERROR_CATEGORY_DIRECTORY_LOOKUP = $100001;

const
  DISK_ERROR = $A00001;

type
  TErrorPair = record
    category: integer;
    error_code: integer;
  end;

  TErrorInfo = record
    errorCode: integer;
    errorMessage: string;
  end;

var
  g_ErrorDict: TDictionary<TErrorPair, String>;
  g_ErrorQueue: TThreadedQueue<TErrorInfo>;

function GetErrorInfo(errorCode: integer; errorMessage: string): TErrorInfo;
begin
  result.errorCode := errorCode;
  result.errorMessage := errorMessage;
end;

procedure PropagateError(errorCode: integer; errorMessage: String);
begin
  g_ErrorQueue.PushItem(GetErrorInfo(errorCode, errorMessage));
end;

function GetLastError(): TErrorInfo;
begin
  result := g_ErrorQueue.PopItem;
end;

function HasErrors(): boolean;
begin
  result := g_ErrorQueue.QueueSize > 0;
end;

function ErrorPair(category, error: integer): TErrorPair;
begin
  result.category := category;
  result.error_code := error;
end;

function GetErrorString(category: integer; error: integer): string;
var
  error_msg: string;
begin
  result := STR_UNKNOWN_ERROR;

  if (g_ErrorDict.TryGetValue(ErrorPair(category, error), error_msg)) then
    result := error_msg;
end;

procedure PrepareErrors;
begin
  g_ErrorDict.Add(ErrorPair(ERROR_CATEGORY_DIRECTORY_LOOKUP, DISK_ERROR),
    STR_DISK_ERROR);
end;

(* * TThumbnailDisplayerMainForm * *)
(* ******************************* *)

constructor TThumbnailDisplayerMainForm.Create(aowner: TComponent);
var
  NodeInfo: TNodeInfo;
  drives: TStringDynArray;
  disk: string;
begin
  inherited;

  FInitializing := true;

  FFilesDict := TDictionary<String, TListItem>.Create;

  drives := TDirectory.GetLogicalDrives;

  FRootDirectory := Copy(drives[0], 1, length(drives[0]) - 1);
  // todo: Move to ui
  for disk in drives do
  begin
    AddSubDirectoryAt(nil, Copy(disk, 1, length(disk) - 1));
  end;

  DirectoryTreeView.Items[0].Selected := true;

  FNodeInfoList := TObjectList<TNodeInfo>.Create(true);
  // owns objects and frees them

  NodeInfo := DirectoryTreeView.Selected.NodeInfo;
  NodeInfo.RootDirectory := FRootDirectory;

  FNodeInfoList.Add(NodeInfo);

  DirectoryTreeView.Items[0].Expand(true);

  InitFileLookuper(FRootDirectory);

  InitThumbnailGenerator;

  FInitializing := false;

end;

destructor TThumbnailDisplayerMainForm.Destroy;
begin
  if (assigned(FThumbGenerator)) then
    FThumbGenerator.Reset;

  if (assigned(FFilesLookup)) then
  begin
    FFilesLookup.Stop;
    FFilesLookup.Terminate;
    FFilesLookup.WaitFor;
    FreeAndNil(FFilesLookup);
  end;

  if (assigned(FThumbGenerator)) then
  begin
    FThumbGenerator.Reset;
    FThumbGenerator.Terminate;
    FThumbGenerator.WaitFor;
    FreeAndNil(FThumbGenerator);
  end;

  FreeAndNil(FFilesDict);

  inherited;

  FreeAndNil(FNodeInfoList);
end;

procedure TThumbnailDisplayerMainForm.DirectoryTreeViewChange(sender: TObject;
  node: TTreeNode);
const
  WAIT = true;
begin
  if FInitializing then
    exit;

  FRootDirectory := GetNodeFullPath(node);

  ThumbnailListView.Clear;
  Thumbnails_ImageList.Clear;

  FThumbGenerator.Reset;
  FFilesLookup.Restart(FRootDirectory);

  Log('Node changed to ' + node.Text);

end;

procedure TThumbnailDisplayerMainForm.DirectoryTreeViewDblClick
  (sender: TObject);
var
  node: TTreeNode;
begin
  node := DirectoryTreeView.Selected;
  if assigned(node) then
  begin

    FThumbGenerator.Reset;

    FRootDirectory := GetNodeFullPath(node);

    if (node.Count = 0) then
    begin
      DirectoryLookupRestart(node, FRootDirectory);
    end;

    if (FFilesLookup.Directory <> FRootDirectory) then
      FFilesLookup.Restart(FRootDirectory);
  end;
end;

procedure TThumbnailDisplayerMainForm.DirectoryTreeViewDeletion(sender: TObject;
  node: TTreeNode);
begin
  FNodeInfoList.Remove(node.NodeInfo);
end;

procedure TThumbnailDisplayerMainForm.messageCheckerTimerTimer(sender: TObject);
var
  error: TErrorInfo;
begin
  while (HasErrors) do
  begin
    error := GetLastError;
    Log(Format('Error (%d): %s', [error.errorCode, error.errorMessage]));
  end;

  while (GlobalLog.HasEntries) do
  begin
    Log('Message: ' + GlobalLog.Extract);
  end;
end;

procedure TThumbnailDisplayerMainForm.DirectoryLookupRestart(node: TTreeNode;
  dir: string);
begin
  node.NodeInfo.RestartLookup(dir);
end;

function TThumbnailDisplayerMainForm.GetNodeFullPath(node: TTreeNode): String;
begin
  if (not assigned(node)) then
    exit('');

  if (node.Parent = nil) then
    exit(node.Text);

  result := GetNodeFullPath(node.Parent) + '\' + node.Text;
end;

procedure TThumbnailDisplayerMainForm.InitFileLookuper(root_dir: string);
begin
  FFilesLookup := TDirectoryLookupThread.Create();

  // attribs
  FFilesLookup.Directory := root_dir;
  // dirs to handle at once
  FFilesLookup.ChunkSize := {$IFDEF DEBUG_DIRS}10{$ELSE}100{$ENDIF};
  // files at once
  FFilesLookup.Attribute := faAnyFile - faDirectory;
  FFilesLookup.FileMask := String.Join(',', ['.jpg', '.jpeg', '.bmp']);

  // events
  FFilesLookup.OnStart := Handle_FilesLookupStart;
  FFilesLookup.OnStop := Handle_FilesLookupStop;
  FFilesLookup.OnProgress := Handle_FilesLookupProgress;
  FFilesLookup.OnError := Handle_FilesLookupError;
  FFilesLookup.OnLog := Handle_Log;
end;

procedure TThumbnailDisplayerMainForm.FileExitMenuItemClick(sender: TObject);
begin
  Close;
end;

procedure TThumbnailDisplayerMainForm.FormActivate(sender: TObject);
begin
  if assigned(DirectoryTreeView.Selected) then
    if DirectoryTreeView.Selected.Count = 0 then
    begin
      DirectoryLookupStart(DirectoryTreeView.Selected);

      FFilesLookup.Start;
    end;
end;

procedure TThumbnailDisplayerMainForm.DirectoryLookupStart(node: TTreeNode);
begin
  DirectoryTreeView.Selected.NodeInfo.StartLookup;
end;

procedure TThumbnailDisplayerMainForm.FormResize(sender: TObject);
begin
  ThumbnailListView.Arrange(arAlignLeft);
end;

procedure TThumbnailDisplayerMainForm.InitThumbnailGenerator;
begin
  FThumbGenerator := TThumbnailGeneratorThread.Create;

  if (not assigned(FThumbGenerator)) then
    raise Exception.Create('Unable to create Thumbnail Generator');

  FThumbGenerator.OnComplete := Handle_ThumbnailComplete;
  FThumbGenerator.OnError := Handle_ThumbnailError;
  FThumbGenerator.OnLog := Handle_Log;
  FThumbGenerator.OnReset := Handle_ThumbnailReset;

  FThumbGenerator.ThumbnailWidth := Thumbnails_ImageList.Width;
  FThumbGenerator.ThumbnailHeight := Thumbnails_ImageList.Height;
end;

procedure TThumbnailDisplayerMainForm.AddDirectoryTree(node: TTreeNode;
  curDir: string);
var
  subDir: string;
  subNode: TTreeNode;
  slashPos: integer;
begin
  if (curDir = '') then
    exit;

  slashPos := pos('\', curDir);
  subDir := Copy(curDir, 1, slashPos - 1);

  if (slashPos = 1) and (subDir = '') then // we found \\ sequence and skip it
  begin
    slashPos := pos('\', curDir, 3);
    subDir := Copy(curDir, 1, slashPos - 1);
  end;

  if (subDir = '') then // we at last item
  begin
    AddSubDirectoryAt(node, curDir);

    if (assigned(node)) then
      SelectDirectoryAt(node, curDir)
    else // we has one root item, select it
      DirectoryTreeView.Items[0].Selected := true;

    exit;
  end
  else
  begin
    subNode := AddSubDirectoryAt(node, subDir);
  end;

  AddDirectoryTree(subNode, Copy(curDir, slashPos + 1, length(curDir)));
end;

function TThumbnailDisplayerMainForm.AddSubDirectoryAt(node: TTreeNode;
  dirName: string): TTreeNode;
var
  newNode: TTreeNode;
begin
  newNode := DirectoryTreeView.Items.AddChild(node, dirName);
  newNode.StateIndex := 1;

  if (assigned(node)) then
    node.NodeInfo.AddNode(dirName, newNode);

  result := newNode;
end;

procedure TThumbnailDisplayerMainForm.SelectDirectoryForSelectedNode
  (dir_name: string);
begin

  if not assigned(DirectoryTreeView.Selected) then
  begin
    Log('Error unable to select with selected:nil node');

    exit;
  end;

  SelectDirectoryAt(DirectoryTreeView.Selected, dir_name);

end;

procedure TThumbnailDisplayerMainForm.SelectDirectoryAt(node: TTreeNode;
  dirName: string);
var
  foundNode: TTreeNode;
  info: TNodeInfo;
begin
  if not assigned(node) then
  begin
    exit;
  end;

  info := node.NodeInfo;

  if (info.TryFindNode(dirName, foundNode)) then
    DirectoryTreeView.Select(foundNode)
  else
    Log('Unable to locate:' + dirName);
end;

procedure TThumbnailDisplayerMainForm.Handle_Log(sender: TObject;
  message: string);
begin
  Log(message);
end;

procedure TThumbnailDisplayerMainForm.Log(message: string);
begin
  LogMemo.Lines.Add(Format('%s: %s', [FormatDateTime('h-m-s', Now), message]));
end;

procedure TThumbnailDisplayerMainForm.SetImageIndexFor(imageNo: integer;
  index: integer);
begin
  ThumbnailListView.Items[imageNo].ImageIndex := index;
end;

procedure TThumbnailDisplayerMainForm.SetImageIndexFor(fileName: string;
  index: integer);
var
  Item: TListItem;
begin
  if (FFilesDict.TryGetValue(fileName, Item)) then
    Item.ImageIndex := index;
end;

function TThumbnailDisplayerMainForm.ExpandToFullPath(files: array of string)
  : TStringArray;
var
  i: integer;
begin
  SetLength(result, length(files));
  for i := 0 to length(files) - 1 do
    result[i] := ExpandToFullPath(files[i]);
end;

function TThumbnailDisplayerMainForm.ExpandToFullPath(fileName: string): string;
begin
  result := RootDirectory + '\' + fileName;
end;

procedure TThumbnailDisplayerMainForm.AddNewFile(curFile: string);
var
  Item: TListItem;
begin
  Item := ThumbnailListView.Items.Add;
  Item.Caption := curFile;
  Item.ImageIndex := 0;

  FFilesDict.Add(ExpandToFullPath(curFile), Item);
end;


// ########################
// ###[ EVENT HANDLERS ]###
// ########################





// #                                 #
// ##[ Files lookup event handlers ]##
// #                                 #

procedure TThumbnailDisplayerMainForm.Handle_FilesLookupError(sender: TObject;
  error: integer; error_message: string);
begin
  FilesLookupErrorPopupPanel.Caption := error_message;
  StatusBar.Panels[0].Text := 'Error';
  StatusBar.Panels[1].Text := 'Files lookup';
  StatusBar.Panels[2].Text := error_message;

  FileLookupStatusShape.Brush.Color := clRed;
  FileLookupStatusShape.Hint := 'File lookup: ERROR:' + error_message;
  Log('File lookup: ERROR:' + error_message);

  filesLookupProgress_Animate.Active := false;
  filesLookupProgress_Animate.Visible := false;
end;

procedure TThumbnailDisplayerMainForm.Handle_FilesLookupStart(sender: TObject);
begin
  ThumbnailListView.Items.Clear;
  FFilesDict.Clear;
  Thumbnails_ImageList.Clear;
  loadingProgressBar.Max := 0;
  loadingProgressBar.Position := 0;

  filesLookupProgress_Animate.Show;
  filesLookupProgress_Animate.Active := true;

  FileLookupStatusShape.Brush.Color := clYellow;
  FileLookupStatusShape.Hint := 'File lookup: PROCESSING';

  FThumbGenerator.Reset;
end;

procedure TThumbnailDisplayerMainForm.Handle_FilesLookupStop(sender: TObject);
begin
  filesLookupProgress_Animate.Hide;
  filesLookupProgress_Animate.Active := false;

  FileLookupStatusShape.Brush.Color := clMoneyGreen;
  FileLookupStatusShape.Hint := 'File lookup: IDLE';
end;

procedure TThumbnailDisplayerMainForm.Handle_FilesLookupProgress
  (sender: TObject; files: array of string);
var
  curFile: String;
begin
  for curFile in files do
  begin
    AddNewFile(ExtractFileName(curFile));
    Log('File is:' + curFile);
  end;

  loadingProgressBar.Max := loadingProgressBar.Max + length(files);

  FThumbGenerator.Process(files);

  ThumbGeneratorStatusShape.Brush.Color := clYellow;
  ThumbGeneratorStatusShape.Hint := 'Thumbnail generator: PROCESSING';

  Application.ProcessMessages;
end;

// #                               #
// ##[ ThumbnailGenerator events ]##
// #                               #

procedure TThumbnailDisplayerMainForm.Handle_ThumbnailComplete(sender: TObject;
  images: TImageInfoArray);
var
  info: TImageInfo;
  i: integer;
begin
  Log('Thumbnails generated count:' + IntToStr(length(images)));

  for info in images do
  begin
    if not assigned(info) then
      continue;
    if not assigned(info.Image) then
      continue;

    i := Thumbnails_ImageList.AddMasked(info.Image.Bitmap, clWhite);

    SetImageIndexFor(info.fileName, i);
    // image less by 1 because we have unknown type image in list

    loadingProgressBar.StepIt;

    if loadingProgressBar.Position = loadingProgressBar.Max then
    begin
      loadingProgressBar.Position := 0;
      loadingProgressBar.Max := 0;

      ThumbGeneratorStatusShape.Brush.Color := clMoneyGreen;
      ThumbGeneratorStatusShape.Hint := 'Thumbnail generator: IDLE';
    end;
  end;
end;

procedure TThumbnailDisplayerMainForm.Handle_ThumbnailError(sender: TObject;
  errorCode: integer; errorMessage: string);
begin
  Log('Error:' + errorMessage + ' code:' + IntToStr(errorCode));

  ThumbGeneratorStatusShape.Brush.Color := clRed;
  ThumbGeneratorStatusShape.Hint := 'Thumbnail generator: ERROR:' +
    errorMessage;
end;

procedure TThumbnailDisplayerMainForm.Handle_ThumbnailReset(sender: TObject);
begin
  Log('Thumbnail generating stoped');

  ThumbGeneratorStatusShape.Brush.Color := clAqua;
  ThumbGeneratorStatusShape.Hint := 'Thumbnail generator: RESET';
end;

procedure TThumbnailDisplayerMainForm.HelpAboutMenuItemClick(sender: TObject);
var
  aboutForm: TAboutForm;
begin
  aboutForm := TAboutForm.Create(self);
  try
    aboutForm.ShowModal;
  finally
    FreeAndNil(aboutForm);
  end;
end;

{ TLookupManager }

constructor TLookupManager.Create;
begin
  FDirectories := TList<String>.Create;

  InitDirectoryLookup;
end;

destructor TLookupManager.Destroy;
begin
  if assigned(FDirectoryLookup) then
  begin
    FDirectoryLookup.Stop;
    FDirectoryLookup.Terminate;
    FDirectoryLookup.WaitFor;
    FreeAndNil(FDirectoryLookup);
  end;

  if assigned(FDirectories) then
    FreeAndNil(FDirectories)
  else
    DoLog('LookupManager::Destroy Already freed FDirectories, that is bug...');

  inherited;
end;

procedure TLookupManager.DoLog(message: string);
begin
  if assigned(FOnLog) then
    FOnLog(self, message);
end;

procedure TLookupManager.InitDirectoryLookup;
begin
  FDirectoryLookup := TDirectoryLookupThread.Create();

  // attribs
  FDirectoryLookup.Directory := FRootDirectory;
  // dirs to handle at once
  FDirectoryLookup.ChunkSize := 100; // dirs at once
  FDirectoryLookup.Attribute := faDirectory;
  FDirectoryLookup.FileMask := '*.*';

  // events
  FDirectoryLookup.OnStart := Handle_DirRefreshStart;
  FDirectoryLookup.OnStop := Handle_DirRefreshStop;
  FDirectoryLookup.OnProgress := Handle_DirRefreshProgress;
  FDirectoryLookup.OnError := Handle_DirRefreshError;
  FDirectoryLookup.OnLog := Handle_Log;
end;

procedure TLookupManager.Restart(newDirectory: String);
begin
  FRootDirectory := newDirectory;
  FDirectoryLookup.Restart(newDirectory);
end;

procedure TLookupManager.Handle_Log(sender: TObject; message: string);
begin
  if assigned(FOnLog) then
    FOnLog(self, message);
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
  FDirectoryLookup.Directory := Value;
end;

procedure TLookupManager.Start;
begin
  FDirectoryLookup.Start;
end;

procedure TLookupManager.DoStart;
begin
  if assigned(FOnStart) then
    FOnStart(self);
end;

procedure TLookupManager.DoStop;
begin
  if assigned(FOnStop) then
    FOnStop(self);
end;

procedure TLookupManager.DoError(errorCode: integer; errorMessage: string);
begin
  if assigned(FOnError) then
    FOnError(self, errorCode, errorMessage);
end;



// #                                     #
// ##[ Directory lookup event handlers ]##
// #                                     #

procedure TLookupManager.Handle_DirRefreshError(sender: TObject; error: integer;
  error_message: string);
begin
  DoError(error, error_message);
end;

procedure TLookupManager.Handle_DirRefreshStart(sender: TObject);
begin
  FDirectories.Clear;
  DoStart;
end;

procedure TLookupManager.Handle_DirRefreshStop(sender: TObject);
begin
  DoStop;
end;

procedure TLookupManager.Handle_DirRefreshProgress(sender: TObject;
  dirs: array of string);
begin
  FDirectories.AddRange(dirs);
end;

{ TNodeInfo }

procedure TNodeInfo.AddNode(dirName: string; node: TTreeNode);
begin
  FNodesDict.Add(dirName, node);
end;

constructor TNodeInfo.Create;
begin
  FLookupManager := TLookupManager.Create;
  LookupManager.OnError := Handle_LookupError;
  LookupManager.OnLog := Handle_Log;
  LookupManager.OnStart := Handle_LookupStart;
  LookupManager.OnStop := Handle_LookupStop;

  FDirectories := FLookupManager.Directories;
  FDirectories.OnNotify := Handle_DirectoryListNotification;

  FNodesDict := TDictionary<String, TTreeNode>.Create;
end;

destructor TNodeInfo.Destroy;
begin
  // we borrow this object, so we must let it go
  if (assigned(FDirectories)) then
  begin
    FDirectories.OnNotify := nil;
    FDirectories := nil;
  end;

  if assigned(FLookupManager) then
    FreeAndNil(FLookupManager);

  if assigned(FNodesDict) then
    FreeAndNil(FNodesDict);

  inherited;
end;

procedure TNodeInfo.RestartLookup(dir: string);
begin
  FLookupManager.Restart(dir);
end;

procedure TNodeInfo.SetLookupManager(const Value: TLookupManager);
begin
  FLookupManager := Value;
end;

procedure TNodeInfo.SetNode(const Value: TTreeNode);
begin
  FNode := Value;
end;

procedure TNodeInfo.SetRootDirectory(const Value: string);
begin
  FRootDirectory := Value;
  FLookupManager.RootDirectory := Value;
end;

procedure TNodeInfo.StartLookup;
begin
  FLookupManager.Start();
end;

function TNodeInfo.TryFindNode(dirName: string; var resNode: TTreeNode)
  : boolean;
begin
  result := FNodesDict.TryGetValue(dirName, resNode);
end;

procedure TNodeInfo.RemoveDirectoryItem(dir: string);
var
  anode: TTreeNode;
  fileName: String;
  i: integer;
begin
  fileName := ExtractFileName(dir);

  if (NodesDict.TryGetValue(fileName, anode)) then
  begin
    NodesDict.Remove(fileName);

    anode.Delete;
  end;
end;

// #                                   #
// ##[ Lookup manager event handlers ]##
// #                                   #

procedure TNodeInfo.Handle_LookupError(sender: TObject; error: integer;
  error_message: string);
begin
  PropagateError(error, error_message);
end;

procedure TNodeInfo.Handle_LookupStart(sender: TObject);
begin
end;

procedure TNodeInfo.Handle_LookupStop(sender: TObject);
begin
end;

procedure TNodeInfo.Handle_Log(sender: TObject; message: string);
begin
  GlobalLog.Write(message);
end;


// #                                   #
// ##[ TDirectoryList event handlers ]##
// #                                   #

procedure TNodeInfo.Handle_DirectoryListNotification(sender: TObject;
  const Item: String; Action: TCollectionNotification);
begin
  case Action of
    cnAdded:
      begin
        node.Owner.AddChild(node, ExtractFileName(Item));

        if not node.Expanded then
          node.Expand(false);

        Application.ProcessMessages;
      end;

    cnRemoved:
      begin
        RemoveDirectoryItem(Item);
      end;

    cnExtracted:
      begin
        // do nothing: list does not allow extracting
      end;
  end;
end;

{ TEmptyNodeInfo }

constructor TEmptyNodeInfo.Create;
begin

end;

class function TEmptyNodeInfo.Instance: TEmptyNodeInfo;
begin
  if assigned(FInstance) then
    exit(FInstance);

  FInstance := TEmptyNodeInfo.Create;
  result := FInstance;
end;

class procedure TEmptyNodeInfo.CleanUp;
begin
  if assigned(FInstance) then
    FreeAndNil(FInstance);
end;

{ TTreeNodeNodeInfoExtractor }

function TTreeNodeNodeInfoExtractor.GetNodeInfo: TNodeInfo;
begin
  result := TEmptyNodeInfo.Instance;

  if (not assigned(Data)) then
  begin
    result := TNodeInfo.Create;
    Data := result;
    result.node := self;

    exit(result);
  end;

  if (TObject(Data).ClassType <> TNodeInfo) then
    exit;

  result := TNodeInfo(Data);
end;

{ GlobalLog }

class procedure GlobalLog.CheckOrCreateLog;
begin
  if (not assigned(FLog)) then
    FLog := TThreadedQueue<String>.Create;
end;

class procedure GlobalLog.CleanUp;
begin
  if assigned(FLog) then
    FreeAndNil(FLog);
end;

class function GlobalLog.Extract: string;
begin
  CheckOrCreateLog;

  result := '<none>';
  if HasEntries then
    result := FLog.PopItem;

end;

class function GlobalLog.HasEntries: boolean;
begin
  CheckOrCreateLog;

  result := FLog.QueueSize > 0;
end;

class procedure GlobalLog.Write(message: string);
begin
  CheckOrCreateLog;

  FLog.PushItem(message);
end;

initialization

g_ErrorQueue := TThreadedQueue<TErrorInfo>.Create;

finalization

TEmptyNodeInfo.CleanUp;
FreeAndNil(g_ErrorDict);
FreeAndNil(g_ErrorQueue);
GlobalLog.CleanUp;

end.
