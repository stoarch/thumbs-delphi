{ *******************************************************

  AVSoftware Logging Utilities

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }
unit AVSoftware.Common.GlobalLog;

interface

uses
  // common
  System.Generics.Collections, System.SysUtils;

type
  GlobalLog = class
  private
    class var FLog: TThreadedQueue<String>;

    class procedure CheckOrCreateLog;
  public
    class procedure Write(Message: String);
    class function Extract(): String;

    class function IsLogEntriesExists(): boolean;

    class procedure CleanUp();
  end;

implementation

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

  Result := '<none>';
  if IsLogEntriesExists then
    Result := FLog.PopItem;

end;

class function GlobalLog.IsLogEntriesExists: boolean;
begin
  CheckOrCreateLog;

  Result := FLog.QueueSize > 0;
end;

class procedure GlobalLog.Write(Message: string);
begin
  CheckOrCreateLog;

  FLog.PushItem(Message);
end;

initialization

finalization

GlobalLog.CleanUp;

end.
