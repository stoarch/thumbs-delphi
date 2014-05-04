{ *******************************************************

  AVSoftware Thumbnails Browser

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }
unit AVSoftware.StateMachine.DirectoryLookup.JobState.AllAtOnceReceiver;

interface

uses
  // COMMON
  System.Types, System.SysUtils, System.IOUtils,
  // States
  AVSoftware.StateMachine.State,
  AVSoftware.StateMachine.DirectoryLookup.JobState.IncrementalReceiver;

type
  { TGetAllAtOnceJobState

    goal: Usage TDirectory instead of FindFirst/FindNext

    info: This state is used when directories need at once }

  TAllAtOnceReceiverJobState = class(TIncrementalReceiverJobState)
  private
    FFoundFiles: TArray<String>;
  protected
    procedure CleanUp; override;
    function DoExecute: boolean; override;
    function GetFoundFiles: TArray<String>; override;

    function PrepareToEnter: boolean; override;
    function PrepareToLeave: boolean; override;

  end;

implementation

{ TGetAllAtOnceState }

const
  CategoryLookup2StateError = $A00005;

procedure TAllAtOnceReceiverJobState.CleanUp;
begin
  // we does not initialize parent data so we not need to clean it
  // todo: Change parent to TState and use ILookupState interface instead!
end;

function TAllAtOnceReceiverJobState.DoExecute: boolean;
var
  FoundItems: TStringDynArray;
  I: integer;
begin
  if (faDirectory and Attribute = 16) then // get dirs
    FoundItems := TDirectory.GetDirectories(Directory)
  else // files
    FoundItems := TDirectory.GetFiles(Directory,
      function(const path: string; const searchRec: TSearchRec): boolean
      begin
        result := pos(UpperCase(ExtractFileExt(searchRec.Name)), FileMask) > 0;
      end);

  SetLength(FFoundFiles, Length(FoundItems));
  for I := 0 to Length(FoundItems) - 1 do
    FFoundFiles[I] := ExtractFileName(FoundItems[I]);

  DoProgress;
  DoComplete;

  result := True;

end;

function TAllAtOnceReceiverJobState.GetFoundFiles: TArray<String>;
begin
  result := FFoundFiles;
end;

function TAllAtOnceReceiverJobState.PrepareToEnter: boolean;
begin
  result := False;
  if (Directory = '') then
  begin
    DoError(CategoryLookup2StateError, 'Directory needed for processing');
    exit;
  end;

  if (FileMask = '') then
  begin
    DoError(CategoryLookup2StateError, 'Filemask must be specified');
    exit;
  end;

  FileMask := UpperCase(FileMask);

  if (not TDirectory.Exists(Directory)) then
  begin
    DoError(CategoryLookup2StateError, 'Not found directory ' + Directory);
    exit;
  end;

  result := True;
end;

function TAllAtOnceReceiverJobState.PrepareToLeave: boolean;
begin
  result := True;
end;

end.
