{ *******************************************************

  AVSoftware Thumbnails Browser

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }
unit AVSoftware.DirectoryLookup.NodeInfo;

interface

uses
  // common
  Vcl.Forms, Vcl.ComCtrls, System.Generics.Collections, System.SysUtils,
  // directory lookup
  AVSoftware.DirectoryLookup.LookupManager;

type
  { TNodeInfo

    goal: Contain and provide lookup manager and nodeDict for tree node

    info:
    1. Instances of this class has two sided link to node (Node.Data and
    NodeInfo.Node) and this link is provided by
    TTreeNodeNodeInfoExtractor when instantiate NodeInfo for node first
    time

    2. This class uses TTreeNode to manage it with LookupManager found
    directories (fill) or clear them when deletion occurs

    3. Subscriber pattern is used: Directories of LookupManager provide
    notifications to list changes so we can add/delete Child TreeNode of
    our Node

  }

  TNodeInfo = class
  private
    FLookupManager: TLookupManager;
    FNodesDict: TDictionary<String, TTreeNode>;
    FNode: TTreeNode;
    FRootDirectory: String;
    FDirectories: TList<String>;

    procedure HandleDirectoryListNotification(Sender: TObject;
      const Item: String; Action: TCollectionNotification);
    procedure HandleLog(Sender: TObject; Message: String);
    procedure HandleLookupError(Sender: TObject; ErrorCode: Integer;
      ErrorMessage: String);
    procedure HandleLookupStart(Sender: TObject);
    procedure HandleLookupStop(Sender: TObject);
    procedure RemoveDirectoryItem(Directory: String);
    procedure SetLookupManager(const Value: TLookupManager);
    procedure SetNode(const Value: TTreeNode);
    procedure SetRootDirectory(const Value: String);

    property LookupManager: TLookupManager read FLookupManager
      write SetLookupManager;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddNode(Directory: String; Node: TTreeNode);
    procedure RestartLookupAt(NewDirectory: String);
    procedure StartLookup;

    function TryFindNode(Directory: String; var ResultNode: TTreeNode): boolean;

    property Directories: TList<String> read FDirectories;
    property Node: TTreeNode read FNode write SetNode;
    property NodesDict: TDictionary<String, TTreeNode> read FNodesDict;
    property RootDirectory: String read FRootDirectory write SetRootDirectory;
  end;

  { TEmptyNodeInfo

    goal: Null class for TNodeInfo

    info:

    1. This is singleton class with one instance

    2. Each methods is overriden to avoid errors (do nothing) }

  TEmptyNodeInfo = class(TNodeInfo)
  private
    class var FInstance: TEmptyNodeInfo;

    constructor Create;
  public
    class procedure CleanUp;
    class function Instance: TEmptyNodeInfo;
  end;

  { TTreeNodeNodeInfoExtractor

    kind: class helper

    goal: Extract NodeInfo from TreeNode Data (if availabled) or return
    EmptyNodeInfo.Instance instead }

  TTreeNodeNodeInfoExtractor = class helper for TTreeNode
  private
    function GetNodeInfo: TNodeInfo;
  public
    property NodeInfo: TNodeInfo read GetNodeInfo;
  end;

implementation

uses
  // errors
  AVSoftware.Common.GlobalLog,
  AVSoftware.Common.ErrorQueue;

{ TNodeInfo }

procedure TNodeInfo.AddNode(Directory: string; Node: TTreeNode);
begin
  FNodesDict.Add(Directory, Node);
end;

constructor TNodeInfo.Create;
begin
  FLookupManager := TLookupManager.Create;
  LookupManager.OnError := HandleLookupError;
  LookupManager.OnLog := HandleLog;
  LookupManager.OnStart := HandleLookupStart;
  LookupManager.OnStop := HandleLookupStop;

  FDirectories := FLookupManager.Directories;
  FDirectories.OnNotify := HandleDirectoryListNotification;

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

procedure TNodeInfo.RestartLookupAt(NewDirectory: string);
begin
  FLookupManager.RestartAt(NewDirectory);
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

function TNodeInfo.TryFindNode(Directory: string;
  var ResultNode: TTreeNode): boolean;
begin
  Result := FNodesDict.TryGetValue(Directory, ResultNode);
end;

procedure TNodeInfo.RemoveDirectoryItem(Directory: string);
var
  ANode: TTreeNode;
  FileName: String;
begin
  FileName := ExtractFileName(Directory);

  if (NodesDict.TryGetValue(FileName, ANode)) then
  begin
    NodesDict.Remove(FileName);

    ANode.Delete;
  end;
end;

{
  Lookup manager event handlers
}

procedure TNodeInfo.HandleLookupError(Sender: TObject; ErrorCode: Integer;
  ErrorMessage: string);
begin
  PropagateError(ErrorCode, ErrorMessage);
end;

procedure TNodeInfo.HandleLookupStart(Sender: TObject);
begin
  // do nothing
end;

procedure TNodeInfo.HandleLookupStop(Sender: TObject);
begin
  // do nothing
end;

procedure TNodeInfo.HandleLog(Sender: TObject; Message: string);
begin
  GlobalLog.Write(Message);
end;

{
  TDirectoryList event handlers
}

procedure TNodeInfo.HandleDirectoryListNotification(Sender: TObject;
  const Item: String; Action: TCollectionNotification);
begin
  case Action of
    cnAdded:
      begin
        Node.Owner.AddChild(Node, ExtractFileName(Item));

        if not Node.Expanded then
          Node.Expand(False);

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
  inherited;
  // do nothing: make some null objects for parent fields
end;

class function TEmptyNodeInfo.Instance: TEmptyNodeInfo;
begin
  if assigned(FInstance) then
    exit(FInstance);

  FInstance := TEmptyNodeInfo.Create;
  Result := FInstance;
end;

class procedure TEmptyNodeInfo.CleanUp;
begin
  if assigned(FInstance) then
    FreeAndNil(FInstance);
end;

{ TTreeNodeNodeInfoExtractor }

function TTreeNodeNodeInfoExtractor.GetNodeInfo: TNodeInfo;
begin
  Result := TEmptyNodeInfo.Instance;

  if (not assigned(Data)) then
  begin
    Result := TNodeInfo.Create;
    Data := Result;
    Result.Node := self;

    exit(Result);
  end;

  if (TObject(Data).ClassType <> TNodeInfo) then
    exit;

  Result := TNodeInfo(Data);
end;

initialization

finalization

TEmptyNodeInfo.CleanUp;

end.
