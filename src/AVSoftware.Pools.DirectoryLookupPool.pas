{ *******************************************************

  AVSoftware Thumbnails Browser

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }

unit AVSoftware.Pools.DirectoryLookupPool;

interface

uses
  // common
  System.Generics.Collections, System.SysUtils, System.SyncObjs,
  // avs threads
  AVSoftware.Threaded.DirectoryLookup;

const
  MaxPoolSize = 5;

  { DirectoryLookupPool

    Kind: Class utility

    Goal:

    Store and provide asynchronous access to directory lookuper threads.

    Info:

    1. This can be done asynchronously and for resource management we use
    Semaphore

    2. When client does not need lookup more - it release lookuper to pool.
    If no more workers on pool - then it will wait (1 second) and return
    timeout or next free directory lookuper

    Usage:

    1. Aquire lookuper

    if not DirectoryLookupPool.Aquire( lookuper ) then
    Show('Error message')
    else
    DoSomething;

    2. Release lookuper (when not need anymore)

    DirectoryLookupPool.Release( lookuper );

    Methods:

    * Aquire() : TDirectoryLookuper

    Tries to acquire lookuper and lock if no more free, when freed then
    returns instance of lookuper

    * Release( lookuper )

    Release the lookuper and put it on thread to work with it later.
    Increase semaphore so next waiting client can use lookuper. }

type
  DirectoryLookupPool = class
  private
    class var FPool: TQueue<TDirectoryLookupThread>;
    class var FAccessGuard: TCriticalSection;
    class var FLookuperSemaphore: TSemaphore;

  protected
    class procedure InitPool;
    class procedure ClearPool;

  public
    class function Aquire(): TDirectoryLookupThread;
    class procedure Release(Lookuper: TDirectoryLookupThread);

  end;

implementation

{ DirectoryLookupPool }

class function DirectoryLookupPool.Aquire(): TDirectoryLookupThread;
begin
  FAccessGuard.Acquire;
  try
    FLookuperSemaphore.Acquire();
    result := FPool.Extract;
  finally
    FAccessGuard.Release;
  end;
end;

class procedure DirectoryLookupPool.ClearPool;
var
  Lookuper: TDirectoryLookupThread;
begin
  FAccessGuard.Acquire;
  try
    while FPool.Count > 0 do
    begin
      Lookuper := FPool.Extract;
      Lookuper.Free;
    end;

    FreeAndNil(FPool);

  finally
    FAccessGuard.Release;
  end;

  FreeAndNil(FAccessGuard);
  FreeAndNil(FLookuperSemaphore);
end;

class procedure DirectoryLookupPool.InitPool;
var
  i: integer;
begin
  FAccessGuard := TCriticalSection.Create;
  FLookuperSemaphore := TSemaphore.Create(nil, MaxPoolSize, MaxPoolSize, '');

  FAccessGuard.Acquire;
  try
    FPool := TQueue<TDirectoryLookupThread>.Create;

    for i := 0 to MaxPoolSize - 1 do
    begin
      FPool.Enqueue(TDirectoryLookupThread.Create);
    end;
  finally
    FAccessGuard.Release;
  end;
end;

class procedure DirectoryLookupPool.Release(Lookuper: TDirectoryLookupThread);
begin
  if (not assigned(Lookuper)) then
    raise EArgumentException.Create('Unable to return to pool nil object');

  FAccessGuard.Acquire;
  try
    FLookuperSemaphore.Release();
    FPool.Enqueue(Lookuper);
  finally
    FAccessGuard.Release;
  end;

end;

initialization

DirectoryLookupPool.InitPool;

finalization

DirectoryLookupPool.ClearPool;

end.
