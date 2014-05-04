{ *******************************************************

  AVSoftware Thumbnails Browser

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }

unit AVSoftware.Thumbs.Forms.MainForm;

interface

uses
  // common
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, System.IOUtils, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.Menus, Vcl.ComCtrls, Vcl.StdCtrls,
  Vcl.ImgList, Vcl.ExtCtrls, System.Types,
  System.SyncObjs, jpeg, pngimage, System.DateUtils,
  // AVS classes
  AVSoftware.Common.Events,
  AVSoftware.Common.GlobalLog,
  AVSoftware.Common.ErrorQueue,
  AVSoftware.DirectoryLookup.NodeInfo,
  AVSoftware.Pools.DirectoryLookupPool,
  AVSoftware.Threaded.DirectoryLookup,
  AVSoftware.Threaded.ThumbnailGenerator;

type
  { TThumbnailDisplayerForm

    goal:

    Load and display thumbnails for directories.
    Provide navigation with asynchronous and lag
    free loading of images thumbs

    info:

    1. This form uses threads for heavy lifting. User
    interface only display result of their work

    2. DirectoryLookupThread used for searching content
    of directory by specific file mask and attribute.
    This form has two threads scanners: one - for directory
    structure lookup (subdirs), another - for image file search

    3. For thumbnail generation this form uses ThumbnailGeneratorThread
    which can generate thumbnails for images and return list of images
    to display

    4. Each node in TreeView attached to NodeInfo for recursive lookup and
    management of child nodes asynchronously }

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
    DirErrorPopupAnimationTimer: TTimer;
    LogMemo: TMemo;
    LoadingProgressBar: TProgressBar;
    TreeStates_ImageList: TImageList;
    messageCheckerTimer: TTimer;

    procedure DirectoryTreeViewChange(Sender: TObject; Node: TTreeNode);
    procedure DirectoryTreeViewDblClick(Sender: TObject);
    procedure DirectoryTreeViewDeletion(Sender: TObject; Node: TTreeNode);
    procedure FileExitMenuItemClick(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure HelpAboutMenuItemClick(Sender: TObject);
    procedure messageCheckerTimerTimer(Sender: TObject);
  private
    FFilesLookuper: TDirectoryLookupThread;
    FThumbGenerator: TThumbnailGeneratorThread;

    FNodeInfoList: TObjectList<TNodeInfo>;

    FInitializing: boolean;

    FFilesDict: TDictionary<String, TListItem>;
    FRootDirectory: String;

    procedure AddDirectoryTreeAt(Node: TTreeNode; Directory: String);
    procedure AddNewFile(FileName: String);
    function AddSubDirectoryAt(Node: TTreeNode; Directory: String): TTreeNode;

    procedure DirectoryLookupRestart(Node: TTreeNode; Directory: String);
    procedure DirectoryLookupStart(Node: TTreeNode);

    function ExpandToFullPath(Files: Array Of String): TArray<String>; overload;
    function ExpandToFullPath(FileName: String): String; overload;

    function GetNodeFullPath(Node: TTreeNode): String;

    procedure HandleFileLookuperError(Sender: TObject; ErrorCode: Integer;
      ErrorMessage: String);
    procedure HandleFileLookuperProgress(Sender: TObject;
      NewFiles: Array Of String);
    procedure HandleFileLookuperStart(Sender: TObject);
    procedure HandleFileLookuperStop(Sender: TObject);
    procedure HandleOnLog(Sender: TObject; Message: String);
    procedure HandleThumbnailGenerationComplete(Sender: TObject;
      NewImages: TImageInfoArray);
    procedure HandleThumbnailGeneratorError(Sender: TObject; ErrorCode: Integer;
      ErrorMessage: String);
    procedure HandleThumbnailGeneratorReset(Sender: TObject);

    procedure InitFileLookuper(RootDir: String);
    procedure InitThumbnailGenerator;

    procedure SelectDirectoryAt(Node: TTreeNode; Directory: String);
    procedure SetImageIndex(ImageNo, Index: Integer); overload;
    procedure SetImageIndex(FileName: string; Index: Integer); overload;

    procedure WriteLog(Message: String);

    { Private declarations }
  public
    { Public declarations }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    property RootDirectory: String read FRootDirectory;
  end;

var
  ThumbnailDisplayerMainForm: TThumbnailDisplayerMainForm;

implementation

{$R *.dfm}

uses AVSoftware.Thumbs.Forms.AboutForm;

(* TThumbnailDisplayerMainForm *)

constructor TThumbnailDisplayerMainForm.Create(AOwner: TComponent);
var
  NodeInfo: TNodeInfo;
  Drives: TStringDynArray;
  Disk: string;
begin
  inherited;

  FInitializing := True;

  FFilesDict := TDictionary<String, TListItem>.Create;

  Drives := TDirectory.GetLogicalDrives;

  FRootDirectory := Copy(Drives[0], 1, Length(Drives[0]) - 1);

  for Disk in Drives do
  begin
    AddSubDirectoryAt(Nil, Copy(Disk, 1, Length(Disk) - 1));
  end;

  DirectoryTreeView.Items[0].Selected := True;

  // owns TNodeInfo objects and frees them on terminate
  // so we donot need to traverse tree to terminate manually

  FNodeInfoList := TObjectList<TNodeInfo>.Create(True);

  NodeInfo := DirectoryTreeView.Selected.NodeInfo;
  NodeInfo.RootDirectory := FRootDirectory;

  FNodeInfoList.Add(NodeInfo);

  DirectoryTreeView.Items[0].Expand(True);

  InitFileLookuper(FRootDirectory);

  InitThumbnailGenerator;

  FInitializing := False;

end;

destructor TThumbnailDisplayerMainForm.Destroy;
begin
  if (assigned(FFilesLookuper)) then
  begin
    FFilesLookuper.Stop;
    FFilesLookuper.WaitStop;

    FFilesLookuper.OnProgress := nil;
    FFilesLookuper.OnStart := nil;
    FFilesLookuper.OnStop := nil;
    FFilesLookuper.OnError := nil;
    FFilesLookuper.OnComplete := nil;
    FFilesLookuper.OnLog := nil;
    FFilesLookuper.OnTerminate := nil;

    DirectoryLookupPool.Release(FFilesLookuper);
  end;

  if (assigned(FThumbGenerator)) then
  begin
    FThumbGenerator.OnComplete := nil;
    FThumbGenerator.OnError := nil;
    FThumbGenerator.OnLog := nil;
    FThumbGenerator.OnReset := nil;
    FThumbGenerator.OnTerminate := nil;

    FThumbGenerator.Reset;
    FThumbGenerator.Terminate;
    FThumbGenerator.WaitStop;
    FreeAndNil(FThumbGenerator);
  end;

  FreeAndNil(FFilesDict);

  inherited;

  FreeAndNil(FNodeInfoList);
end;

procedure TThumbnailDisplayerMainForm.DirectoryTreeViewChange(Sender: TObject;
  Node: TTreeNode);
const
  WAIT = True;
begin
  if FInitializing then
    exit;

  FRootDirectory := GetNodeFullPath(Node);

  ThumbnailListView.Clear;
  Thumbnails_ImageList.Clear;

  FThumbGenerator.Reset;
  FFilesLookuper.Directory := FRootDirectory;
  FFilesLookuper.Restart;

  WriteLog('Node changed to ' + Node.Text);

end;

procedure TThumbnailDisplayerMainForm.DirectoryTreeViewDblClick
  (Sender: TObject);
var
  Node: TTreeNode;
begin
  Node := DirectoryTreeView.Selected;
  if assigned(Node) then
  begin

    FThumbGenerator.Reset;

    FRootDirectory := GetNodeFullPath(Node);

    if (Node.Count = 0) then
    begin
      DirectoryLookupRestart(Node, FRootDirectory);
    end;

    if (FFilesLookuper.Directory <> FRootDirectory) then
    begin
      FFilesLookuper.Directory := FRootDirectory;
      FFilesLookuper.Restart;
    end;
  end;
end;

procedure TThumbnailDisplayerMainForm.DirectoryTreeViewDeletion(Sender: TObject;
  Node: TTreeNode);
begin
  FNodeInfoList.Remove(Node.NodeInfo);
end;

procedure TThumbnailDisplayerMainForm.messageCheckerTimerTimer(Sender: TObject);
var
  Error: TErrorInfo;
begin
  while (IsAnyErrorInQueue) do
  begin
    Error := GetLastError;
    WriteLog(Format('Error (%d): %s', [Error.ErrorCode, Error.ErrorMessage]));
  end;

  while (GlobalLog.IsLogEntriesExists) do
  begin
    WriteLog('Message: ' + GlobalLog.Extract);
  end;
end;

procedure TThumbnailDisplayerMainForm.DirectoryLookupRestart(Node: TTreeNode;
  Directory: string);
begin
  Node.NodeInfo.RestartLookupAt(Directory);
end;

function TThumbnailDisplayerMainForm.GetNodeFullPath(Node: TTreeNode): String;
begin
  if (not assigned(Node)) then
    exit('');

  if (Node.Parent = nil) then
    exit(Node.Text);

  Result := GetNodeFullPath(Node.Parent) + '\' + Node.Text;
end;

procedure TThumbnailDisplayerMainForm.InitFileLookuper(RootDir: string);
begin
  FFilesLookuper := DirectoryLookupPool.Aquire;

  FFilesLookuper.Directory := RootDir;
  // how many files to handle at once
  FFilesLookuper.ChunkSize := {$IFDEF DEBUG_DIRS}10{$ELSE}100{$ENDIF};

  FFilesLookuper.Attribute := faAnyFile - faDirectory;
  FFilesLookuper.FileMask := String.Join(',', ['.jpg', '.jpeg', '.bmp']);

  // events
  FFilesLookuper.OnStart := HandleFileLookuperStart;
  FFilesLookuper.OnStop := HandleFileLookuperStop;
  FFilesLookuper.OnProgress := HandleFileLookuperProgress;
  FFilesLookuper.OnError := HandleFileLookuperError;
  FFilesLookuper.OnLog := HandleOnLog;
end;

procedure TThumbnailDisplayerMainForm.FileExitMenuItemClick(Sender: TObject);
begin
  Close;
end;

procedure TThumbnailDisplayerMainForm.FormActivate(Sender: TObject);
begin
  if assigned(DirectoryTreeView.Selected) then
    if DirectoryTreeView.Selected.Count = 0 then
    begin
      DirectoryLookupStart(DirectoryTreeView.Selected);

      FFilesLookuper.Start;
    end;
end;

procedure TThumbnailDisplayerMainForm.DirectoryLookupStart(Node: TTreeNode);
begin
  DirectoryTreeView.Selected.NodeInfo.StartLookup;
end;

procedure TThumbnailDisplayerMainForm.FormResize(Sender: TObject);
begin
  ThumbnailListView.Arrange(arAlignLeft);
end;

procedure TThumbnailDisplayerMainForm.InitThumbnailGenerator;
begin
  FThumbGenerator := TThumbnailGeneratorThread.Create;

  if (not assigned(FThumbGenerator)) then
    raise Exception.Create('Unable to create Thumbnail Generator');

  FThumbGenerator.OnComplete := HandleThumbnailGenerationComplete;
  FThumbGenerator.OnError := HandleThumbnailGeneratorError;
  FThumbGenerator.OnLog := HandleOnLog;
  FThumbGenerator.OnReset := HandleThumbnailGeneratorReset;

  FThumbGenerator.ThumbnailWidth := Thumbnails_ImageList.Width;
  FThumbGenerator.ThumbnailHeight := Thumbnails_ImageList.Height;
end;

procedure TThumbnailDisplayerMainForm.AddDirectoryTreeAt(Node: TTreeNode;
  Directory: string);
var
  SubDir: string;
  ChildNode: TTreeNode;
  SlashPos: Integer;
begin
  if (Directory = '') then
    exit;

  SlashPos := pos('\', Directory);
  SubDir := Copy(Directory, 1, SlashPos - 1);

  if (SlashPos = 1) and (SubDir = '') then // we found \\ sequence and skip it
  begin
    SlashPos := pos('\', Directory, 3);
    SubDir := Copy(Directory, 1, SlashPos - 1);
  end;

  if (SubDir = '') then // we at last item
  begin
    AddSubDirectoryAt(Node, Directory);

    if (assigned(Node)) then
      SelectDirectoryAt(Node, Directory)
    else // we has one root item, select it
      DirectoryTreeView.Items[0].Selected := True;

    exit;
  end
  else
  begin
    ChildNode := AddSubDirectoryAt(Node, SubDir);
  end;

  AddDirectoryTreeAt(ChildNode, Copy(Directory, SlashPos + 1,
    Length(Directory)));
end;

function TThumbnailDisplayerMainForm.AddSubDirectoryAt(Node: TTreeNode;
  Directory: string): TTreeNode;
var
  NewNode: TTreeNode;
begin
  NewNode := DirectoryTreeView.Items.AddChild(Node, Directory);
  NewNode.StateIndex := 1;

  if (assigned(Node)) then
    Node.NodeInfo.AddNode(Directory, NewNode);

  Result := NewNode;
end;

procedure TThumbnailDisplayerMainForm.SelectDirectoryAt(Node: TTreeNode;
  Directory: string);
var
  FoundNode: TTreeNode;
  Info: TNodeInfo;
begin
  if not assigned(Node) then
  begin
    exit;
  end;

  Info := Node.NodeInfo;

  if (Info.TryFindNode(Directory, FoundNode)) then
    DirectoryTreeView.Select(FoundNode)
  else
    WriteLog('Unable to locate:' + Directory);
end;

procedure TThumbnailDisplayerMainForm.HandleOnLog(Sender: TObject;
  Message: string);
begin
  WriteLog(Message);
end;

procedure TThumbnailDisplayerMainForm.WriteLog(Message: string);
const
  MaxLogLines = 100;
begin
  if not LogMemo.Visible then
    exit;

  LogMemo.Lines.Add(Format('%s: %s', [FormatDateTime('h-m-s', Now), Message]));
  if LogMemo.Lines.Count > MaxLogLines then
  begin
    LogMemo.Lines.Delete(0);
  end;
end;

procedure TThumbnailDisplayerMainForm.SetImageIndex(ImageNo: Integer;
  Index: Integer);
begin
  ThumbnailListView.Items[ImageNo].ImageIndex := Index;
end;

procedure TThumbnailDisplayerMainForm.SetImageIndex(FileName: string;
  Index: Integer);
var
  Item: TListItem;
begin
  if (FFilesDict.TryGetValue(FileName, Item)) then
    Item.ImageIndex := Index;
end;

function TThumbnailDisplayerMainForm.ExpandToFullPath(Files: array of string)
  : TArray<String>;
var
  I: Integer;
begin
  SetLength(Result, Length(Files));
  for I := 0 to Length(Files) - 1 do
    Result[I] := ExpandToFullPath(Files[I]);
end;

function TThumbnailDisplayerMainForm.ExpandToFullPath(FileName: string): string;
begin
  Result := RootDirectory + '\' + FileName;
end;

procedure TThumbnailDisplayerMainForm.AddNewFile(FileName: string);
var
  Item: TListItem;
begin
  Item := ThumbnailListView.Items.Add;
  Item.Caption := FileName;
  Item.ImageIndex := 0;

  FFilesDict.Add(ExpandToFullPath(FileName), Item);
end;

{ EVENT HANDLERS }

{ Files lookup event handlers }

procedure TThumbnailDisplayerMainForm.HandleFileLookuperError(Sender: TObject;
  ErrorCode: Integer; ErrorMessage: string);
const
  StatePanelNo = 0;
  WorkPanelNo = 1;
  MessagePanelNo = 2;
begin
  StatusBar.Panels[StatePanelNo].Text := 'Error';
  StatusBar.Panels[WorkPanelNo].Text := 'Files lookup';
  StatusBar.Panels[MessagePanelNo].Text := ErrorMessage;

  WriteLog('File lookup: ERROR:' + ErrorMessage);

  filesLookupProgress_Animate.Active := False;
  filesLookupProgress_Animate.Visible := False;
end;

procedure TThumbnailDisplayerMainForm.HandleFileLookuperStart(Sender: TObject);
begin
  ThumbnailListView.Items.Clear;
  FFilesDict.Clear;
  Thumbnails_ImageList.Clear;
  LoadingProgressBar.Max := 0;
  LoadingProgressBar.Position := 0;

  filesLookupProgress_Animate.Show;
  filesLookupProgress_Animate.Active := True;

  FThumbGenerator.Reset;
end;

procedure TThumbnailDisplayerMainForm.HandleFileLookuperStop(Sender: TObject);
begin
  filesLookupProgress_Animate.Hide;
  filesLookupProgress_Animate.Active := False;
end;

procedure TThumbnailDisplayerMainForm.HandleFileLookuperProgress
  (Sender: TObject; NewFiles: array of string);
var
  CurFile: String;
begin
  for CurFile in NewFiles do
  begin
    AddNewFile(ExtractFileName(CurFile));
  end;

  LoadingProgressBar.Max := LoadingProgressBar.Max + Length(NewFiles);

  FThumbGenerator.Process(NewFiles);

  Application.ProcessMessages;
end;

{ ThumbnailGenerator events }

procedure TThumbnailDisplayerMainForm.HandleThumbnailGenerationComplete
  (Sender: TObject; NewImages: TImageInfoArray);
var
  Info: TImageInfo;
  I: Integer;
begin
  WriteLog('Thumbnails generated count:' + IntToStr(Length(NewImages)));

  for Info in NewImages do
  begin
    if not assigned(Info) then
      continue;
    if not assigned(Info.Image) then
      continue;

    I := Thumbnails_ImageList.AddMasked(Info.Image.Bitmap, clWhite);

    SetImageIndex(Info.FileName, I);
    // image less by 1 because we have unknown type image in list

    LoadingProgressBar.StepIt;

    if LoadingProgressBar.Position = LoadingProgressBar.Max then
    begin
      LoadingProgressBar.Position := 0;
      LoadingProgressBar.Max := 0;
    end;
  end;
end;

procedure TThumbnailDisplayerMainForm.HandleThumbnailGeneratorError
  (Sender: TObject; ErrorCode: Integer; ErrorMessage: string);
begin
  WriteLog('Error:' + ErrorMessage + ' code:' + IntToStr(ErrorCode));
end;

procedure TThumbnailDisplayerMainForm.HandleThumbnailGeneratorReset
  (Sender: TObject);
begin
  WriteLog('Thumbnail generating stoped');
end;

procedure TThumbnailDisplayerMainForm.HelpAboutMenuItemClick(Sender: TObject);
var
  AboutForm: TAboutForm;
begin
  AboutForm := TAboutForm.Create(self);
  try
    AboutForm.ShowModal;
  finally
    FreeAndNil(AboutForm);
  end;
end;

end.
