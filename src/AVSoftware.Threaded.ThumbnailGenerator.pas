{ *******************************************************

  AVSoftware Thumbnails Browser

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }

unit AVSoftware.Threaded.ThumbnailGenerator;

interface

uses
  // COMMON
  System.Classes, System.SysUtils, System.SyncObjs, System.Generics.Collections,
  VCL.Graphics, System.DateUtils, pngimage, jpeg, gifimg,
  VCL.ExtCtrls, Winapi.Windows, VCL.Clipbrd, System.Math,
  // --[ AVS COMMON ]--
  AVSoftware.Common.Events;

type

  TPictureArray = array of TPicture;

  TImageInfo = class
  private
    FFileName: string;
    FImage: TPicture;
    procedure SetFileName(const Value: string);
    procedure SetImage(const Value: TPicture);
  public
    property Image: TPicture read FImage write SetImage;
    property FileName: string read FFileName write SetFileName;
  end;

  TImageInfoArray = array of TImageInfo;

  TThumbnailCompleteEvent = procedure(sender: TObject; images: TImageInfoArray)
    of object;

const
  THUMBNAIL_GENERATOR_ERROR = $A00003;

type
  { TThumbnailGeneratorThread

    goal: Asynchronously generate thumbnails for specified files (with
    path) and send result to listener

    usage:

    1. Setup

    generator := TThumbnailGeneratorThread.Create;

    generator.OnComplete := Handle_ThumbnailComplete;
    generator.OnError := Handle_ThumbnailError;

    generator.ThumbnailWidth := 64;
    generator.ThumbnailHeight := 64;


    2. Process images

    generator.Process( imageList ) - and get them to oncomplete event


    3. Reset process

    generator.Reset - and get event about reseting


    [methods:]
    * Process - handle generation of thumbnails for specified list
    of files
    * Reset - stops processing, clear queue and wait

    [events:]
    * OnComplete - fires when processing is done and result ready
    * OnError - fires when processing encountered an error
    * OnLog - fires when generator has something to say (debugging)
    * OnReset - fires when generator resets and stop waiting command

    [properties:]
    * ThumbnailWidth, ThumbnailHeight - dimension of resulting thumbnail }

  TThumbnailGeneratorThread = class(TThread)
  private
    FAccessorGuard : TCriticalSection;

    FStartEvent: TEvent;
    FStopEvent: TEvent;

    FFilesQueue: TQueue<String>;
    FCompleteImages: TImageInfoArray;

    FThumbnailWidth: UInt16;
    FThumbnailHeight: UInt16;

    FResetFlag: boolean;
    FProcessingFlag: boolean;

    FOnComplete: TThumbnailCompleteEvent;
    FOnLog: TLogEvent;
    FOnError: TErrorEvent;
    FOnReset: TNotifyEvent;

    procedure FireOnComplete(NewImages: TImageInfoArray);
    procedure FireOnError(ErrorCode: integer; ErrorMessage: string);
    procedure FireOnReset;

    function GetScaledImage(FileName: string; ThumbWidth, ThumbHeight: integer)
      : TPicture;
    function GetCompleteImages: TImageInfoArray;

    function ImageInfo(Image: TPicture; FileName: string): TImageInfo;
    procedure Log(Message: string);
    procedure ProcessImages;
    procedure ReplaceJPEGWithBitmap(SourceImage: TPicture);

    procedure SendImages(NewImages: TQueue<TImageInfo>);
    procedure SetOnComplete(const Value: TThumbnailCompleteEvent);
    procedure SetOnError(const Value: TErrorEvent);
    procedure SetOnLog(const Value: TLogEvent);
    procedure SetOnReset(const Value: TNotifyEvent);
    procedure SetThumbnailHeight(const Value: UInt16);
    procedure SetThumbnailWidth(const Value: UInt16);

    procedure WaitForProcessing;
    procedure HandleOnTerminate(sender: TObject);
    function GetResetFlag: boolean;
    procedure SetResetFlag(const Value: boolean);
    function GetProcessingFlag: boolean;
    procedure SetProcessingFlag(const Value: boolean);
  protected
    procedure Execute; override;

    property ProcessingFlag: boolean read GetProcessingFlag
      write SetProcessingFlag;
    property ResetFlag : boolean read GetResetFlag write SetResetFlag;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Process(images: array of string);
    procedure Reset;
    procedure WaitStop;

    property ThumbnailWidth: UInt16 read FThumbnailWidth
      write SetThumbnailWidth;
    property ThumbnailHeight: UInt16 read FThumbnailHeight
      write SetThumbnailHeight;


    property OnComplete: TThumbnailCompleteEvent read FOnComplete
      write SetOnComplete;
    property OnError: TErrorEvent read FOnError write SetOnError;
    property OnLog: TLogEvent read FOnLog write SetOnLog;
    property OnReset: TNotifyEvent read FOnReset write SetOnReset;
  end;

implementation

{ TThumbnailGeneratorThread }

constructor TThumbnailGeneratorThread.Create;
begin
  FAccessorGuard := TCriticalSection.Create;

  FStartEvent := TEvent.Create(nil, true, false, '');
  FStartEvent.ResetEvent;

  FStopEvent := TEvent.Create(nil, true, false, '');
  FStopEvent.ResetEvent;

  FFilesQueue := TQueue<String>.Create;

  OnTerminate := HandleOnTerminate;

  FResetFlag := false;
  FProcessingFlag := false;

  inherited Create(false);

end;

destructor TThumbnailGeneratorThread.Destroy;
begin

  inherited;
end;

procedure TThumbnailGeneratorThread.HandleOnTerminate( sender : TObject );
begin
  FreeAndNil(FFilesQueue);
  FreeAndNil(FStartEvent);
  FreeAndNil(FStopEvent);
  FreeAndNil(FAccessorGuard);
end;

procedure TThumbnailGeneratorThread.Execute;
begin
    repeat
      try
        WaitForProcessing;

        if Terminated then
          break;

        if ResetFlag then
        begin
          FFilesQueue.Clear;
          FFilesQueue.TrimExcess;

          FireOnReset;

          ResetFlag := false;
          ProcessingFlag := false;
        end;

        if (ProcessingFlag) then
          if (FFilesQueue.Count > 0) then
          begin
            ProcessImages;

            if (FFilesQueue.Count = 0) then
              FProcessingFlag := false;
          end;

      except
        on e: exception do
        begin
          FireOnError(THUMBNAIL_GENERATOR_ERROR, e.Message);
        end;

      end;
    until Terminated;

end;

procedure TThumbnailGeneratorThread.FireOnError(ErrorCode: integer;
  ErrorMessage: string);
begin
  if Assigned(FOnError) then
    Synchronize(
      procedure
      begin
        FOnError(self, ErrorCode, ErrorMessage);
      end);
end;

procedure TThumbnailGeneratorThread.ProcessImages;
const
  MaxImagesQueueSize = 1;
  // change it for longer process but all at once if needed
var
  FileName: string;
  NewImagesQueue: TQueue<TImageInfo>;
  Image: TPicture;
  TrackingTime: TDateTime;
begin
  NewImagesQueue := TQueue<TImageInfo>.Create;

  ProcessingFlag := true;

  FStartEvent.ResetEvent;
  try

    while FFilesQueue.Count > 0 do
    begin
      if ResetFlag or Terminated then
        abort;

      FileName := FFilesQueue.Extract;

      Log('Processing file ' + FileName + '...');
      TrackingTime := Now;

      Image := GetScaledImage(FileName, ThumbnailWidth, ThumbnailHeight);

      Log('File processed in ' + IntToStr(MilliSecondsBetween(Now, TrackingTime)
        ) + ' msec');

      NewImagesQueue.Enqueue(ImageInfo(Image, FileName));

      if ResetFlag or Terminated then
        abort;

      if (NewImagesQueue.Count > MaxImagesQueueSize) then
      begin

        SendImages(NewImagesQueue);
        NewImagesQueue.TrimExcess;
      end;

    end;

    if ResetFlag or Terminated then
      abort;

    if (NewImagesQueue.Count > 0) then
    begin
      NewImagesQueue.TrimExcess;
      SendImages(NewImagesQueue); // last small chunk of images
    end;

  finally
    FFilesQueue.Clear;
    FFilesQueue.TrimExcess;
    FreeAndNil(NewImagesQueue);
    ProcessingFlag := false;
    FStopEvent.SetEvent;
  end;
end;

procedure TThumbnailGeneratorThread.Reset;
begin
  Log('Thumbnail generator: RESET');

  ResetFlag := true;
  ProcessingFlag := false;

  FireOnReset;
end;

{ TThumbnailGeneratorThread.ReplaceJPEGWithBitmap

  goal: Decode JPEG image and store it as DIB bitmap

  info:
  1. We used clipboard to store image as bitmap.
  If workaround will be found we remove clipboard usage

  2. Image checked about size and if it small - no compression is used
  JPEG compression algorithms used to keep speed of converting
  constistent

  params:
  * SourceImage - with JPEG loaded. It will be replaced with Bitmap! }

procedure TThumbnailGeneratorThread.ReplaceJPEGWithBitmap
  (SourceImage: TPicture);
var
  MaxDims: integer;
begin
  with TJPEGImage(SourceImage.Graphic) do
  begin
    Performance := jpBestSpeed;
    MaxDims := Max(SourceImage.Width, SourceImage.Height);
    if (MaxDims < 300) then
      Scale := jsFullSize
    else if (MaxDims < 600) then
      Scale := jsHalf
    else if (MaxDims < 1200) then
      Scale := jsQuarter
    else
      Scale := jsEighth;
    Clipboard.Assign(SourceImage);
  end;
  if (Clipboard.HasFormat(cf_bitmap)) then
    SourceImage.Assign(Clipboard)
  else
  begin
    abort;
  end;
end;

procedure TThumbnailGeneratorThread.FireOnReset;
begin
  Synchronize(
    procedure
    begin
      if Assigned(FOnReset) then
        FOnReset(self);
    end);
end;

procedure TThumbnailGeneratorThread.SendImages(NewImages: TQueue<TImageInfo>);
var
  ImageInfoArray: Array of TImageInfo;
  I: integer;
  Info: TImageInfo;
begin
  SetLength(ImageInfoArray, NewImages.Count);

  I := 0;
  repeat
    ImageInfoArray[I] := NewImages.Extract;
    I := I + 1;
  until NewImages.Count = 0;

  FireOnComplete(TImageInfoArray(ImageInfoArray));

  NewImages.Clear;

  for Info in ImageInfoArray do
  begin
    Info.Image.Free;
    Info.Free;
  end;

  SetLength(ImageInfoArray, 0);
end;

function TThumbnailGeneratorThread.ImageInfo(Image: TPicture; FileName: string)
  : TImageInfo;
begin
  result := TImageInfo.Create;
  result.Image := Image;
  result.FileName := FileName;
end;

procedure TThumbnailGeneratorThread.Log(Message: string);
begin
  if Assigned(FOnLog) then
    Synchronize(
      procedure
      begin
        FOnLog(self, Message);
      end);
end;

{ TThumbnailGeneratorThread.GetScaledImage

  goal: Scale image, specified by file name to thumbnail dimensions

  info:
  1. We use simple stretch draw. If speed is concern, then we
  can use ScanLines to process faster, but with more bulkier code

  2. If speed is still slow - we can use SQLite cached thumbnails

  3. Dimension of internal image can be smaller. We use proportional
  scaling to save maximum image information

  4. For beauty it drawing rectangle around image. If you does not need
  just remove lines after StretchDraw of drawing it

  params:
  * FileName - of image to be processed. Must be BMP or JPG format file
  (png partially supported and some files does not open)

  * ThumbWidth, ThumbHeight - dimensions of thumbnail image

  returns:
  Bitmap image of scaled source file to specific dimension }

function TThumbnailGeneratorThread.GetScaledImage(FileName: string;
ThumbWidth, ThumbHeight: integer): TPicture;
var
  SourceImage, DestImage: TPicture;
  ScaledWidth, ScaledHeight: integer;
begin
  ScaledWidth := 0;
  ScaledHeight := 0;

  DestImage := TPicture.Create;
  SourceImage := TPicture.Create;

  try
    try
      SourceImage.LoadFromFile(FileName);

      if (SourceImage.Graphic is TJPEGImage) then
        ReplaceJPEGWithBitmap(SourceImage);

      if SourceImage.Width > SourceImage.Height then
      begin
        ScaledHeight := trunc(ThumbWidth * SourceImage.Height /
          SourceImage.Width);
        ScaledWidth := ThumbWidth;
      end
      else if SourceImage.Height > SourceImage.Width then
      begin
        ScaledWidth := trunc(ThumbHeight * SourceImage.Width /
          SourceImage.Height);
        ScaledHeight := ThumbHeight;
      end;

      DestImage.bitmap.Width := ThumbWidth;
      DestImage.bitmap.Height := ThumbHeight;

      DestImage.bitmap.Canvas.Brush.Style := bsSolid;
      DestImage.bitmap.Canvas.Brush.Color := clWhite;
      DestImage.bitmap.Canvas.FillRect(Bounds(0, 0, ThumbWidth, ThumbHeight));

      DestImage.bitmap.Canvas.StretchDraw
        (Bounds(ThumbWidth div 2 - ScaledWidth div 2,
        ThumbHeight div 2 - ScaledHeight div 2, ScaledWidth, ScaledHeight),
        SourceImage.bitmap);

      DestImage.bitmap.Canvas.Brush.Style := bsClear;
      DestImage.bitmap.Canvas.Pen.Color := clBlack;
      DestImage.bitmap.Canvas.Pen.Style := psSolid;
      DestImage.bitmap.Canvas.Rectangle(Bounds(0, 0, ThumbWidth, ThumbHeight));

      result := DestImage;

    finally
      SourceImage.Free;
    end;

  except
    on e: exception do
    begin
      FireOnError(THUMBNAIL_GENERATOR_ERROR, e.Message);

      DestImage.Free;
      result := nil;
    end;
  end;
end;

procedure TThumbnailGeneratorThread.FireOnComplete(NewImages: TImageInfoArray);
begin
  FCompleteImages := Copy(NewImages, 0, Length(NewImages));

  if Assigned(FOnComplete) then
    Synchronize(
      procedure
      begin
        FOnComplete(self, GetCompleteImages);
      end);
end;

function TThumbnailGeneratorThread.GetCompleteImages: TImageInfoArray;
begin
  result := FCompleteImages;
end;

function TThumbnailGeneratorThread.GetProcessingFlag: boolean;
begin
  FAccessorGuard.Acquire;
  try
    result := FProcessingFlag;
  finally
    FAccessorGuard.Release;
  end;
end;

function TThumbnailGeneratorThread.GetResetFlag: boolean;
begin
  FAccessorGuard.Acquire;
  try
    result := FResetFlag;
  finally
    FAccessorGuard.Release;
  end;
end;

procedure TThumbnailGeneratorThread.WaitForProcessing;
const
  ThreadIdleTimeout = 100; // ms
begin
  repeat
    if (FStartEvent.WaitFor(ThreadIdleTimeout) = wrSignaled) then
      break;
    ;
  until Terminated;
end;

procedure TThumbnailGeneratorThread.WaitStop;
const
  ThreadIdleTimeout = 100;
begin
  repeat
    if( FStopEvent.WaitFor(ThreadIdleTimeout) = wrSignaled )then
      exit;
  until Terminated;
end;

procedure TThumbnailGeneratorThread.Process(images: array of string);
var
  Item: string;
begin
  FResetFlag := false;
  FProcessingFlag := true;

  for Item in images do
  begin
    FFilesQueue.Enqueue(Item);
  end;

  FStartEvent.SetEvent;
end;

procedure TThumbnailGeneratorThread.SetOnComplete
  (const Value: TThumbnailCompleteEvent);
begin
  FOnComplete := Value;
end;

procedure TThumbnailGeneratorThread.SetOnError(const Value: TErrorEvent);
begin
  FOnError := Value;
end;

procedure TThumbnailGeneratorThread.SetOnLog(const Value: TLogEvent);
begin
  FOnLog := Value;
end;

procedure TThumbnailGeneratorThread.SetOnReset(const Value: TNotifyEvent);
begin
  FOnReset := Value;
end;

procedure TThumbnailGeneratorThread.SetProcessingFlag(const Value: boolean);
begin
  FAccessorGuard.Acquire;
  try
    FProcessingFlag := Value;
  finally
    FAccessorGuard.Release;
  end;
end;

procedure TThumbnailGeneratorThread.SetResetFlag(const Value: boolean);
begin
  FAccessorGuard.Acquire;
  try
    FResetFlag := Value;
  finally
    FAccessorGuard.Release;
  end;
end;

procedure TThumbnailGeneratorThread.SetThumbnailHeight(const Value: UInt16);
begin
  FThumbnailHeight := Value;
end;

procedure TThumbnailGeneratorThread.SetThumbnailWidth(const Value: UInt16);
begin
  FThumbnailWidth := Value;
end;

{ TImageInfo }

procedure TImageInfo.SetFileName(const Value: string);
begin
  FFileName := Value;
end;

procedure TImageInfo.SetImage(const Value: TPicture);
begin
  FImage := Value;
end;

end.
