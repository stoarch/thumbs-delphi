{ *******************************************************

  AVSoftware Error Utilities

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }
unit AVSoftware.Common.ErrorQueue;

interface

const
  CategorySystemErrorCode = $100000;
  CategoryDirectoryLookupErrorCode = $100001;

type
  TErrorInfo = record
    ErrorCode: Integer;
    ErrorMessage: String;
  end;

function IsAnyErrorInQueue(): boolean;
function GetLastError(): TErrorInfo;
procedure PropagateError(ErrorCode: Integer; ErrorMessage: String);

implementation

uses
  System.Generics.Collections, System.SysUtils;

resourcestring
  UnknownErrorString = 'Unknown errror';
  DiskErrorString = 'Disk error occured';

const
  DiskErrorCode = $A00001;

type
  TErrorPair = record
    CategoryCode: Integer;
    ErrorCode: Integer;
  end;

var
  GlobalErrorDictionary: TDictionary<TErrorPair, String>;
  GlobalErrorQueue: TThreadedQueue<TErrorInfo>;

function GetErrorInfo(ErrorCode: Integer; ErrorMessage: String): TErrorInfo;
begin
  Result.ErrorCode := ErrorCode;
  Result.ErrorMessage := ErrorMessage;
end;

procedure PropagateError(ErrorCode: Integer; ErrorMessage: String);
begin
  GlobalErrorQueue.PushItem(GetErrorInfo(ErrorCode, ErrorMessage));
end;

function GetLastError(): TErrorInfo;
begin
  Result := GlobalErrorQueue.PopItem;
end;

function IsAnyErrorInQueue(): boolean;
begin
  Result := GlobalErrorQueue.QueueSize > 0;
end;

function ErrorPair(CategoryCode, ErrorCode: Integer): TErrorPair;
begin
  Result.CategoryCode := CategoryCode;
  Result.ErrorCode := ErrorCode;
end;

function GetErrorString(CategoryCode: Integer; ErrorCode: Integer): string;
var
  ErrorMsg: String;
begin
  Result := UnknownErrorString;

  if (GlobalErrorDictionary.TryGetValue(ErrorPair(CategoryCode, ErrorCode),
    ErrorMsg)) then
    Result := ErrorMsg;
end;

procedure PrepareErrors;
begin
  GlobalErrorDictionary.Add(ErrorPair(CategoryDirectoryLookupErrorCode,
    DiskErrorCode), DiskErrorString);
end;

initialization

GlobalErrorQueue := TThreadedQueue<TErrorInfo>.Create;

finalization

FreeAndNil(GlobalErrorDictionary);
FreeAndNil(GlobalErrorQueue);

end.
