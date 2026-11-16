unit uThumbPool;

{$mode objfpc}{$H+}

{ Prepares thumbnails on several threads while a folder loads.

  The main thread adds the items whose thumbnails it is going to ask for, in that order, and starts the
  batch. Each thread takes the next item and calls uItems.PrepareThumb, which reads the file and builds
  the finished thumbnail as a BMP in memory without any window system object. The main thread then
  takes the results in the same order (IsNext, NextReady, Deliver) and turns each into the item's
  bitmap. The threads never touch an item: they get copies of its path, orientation and cache file name.

  Only JPEG and RAW files go this way (uItems.ThumbPoolable). The HEIC/AVIF decoder keeps its working
  data in shared variables and cannot run more than once at a time; TIFF, DNG, WebP and video
  thumbnails use window system objects. Those are made on the main thread as before. }

interface

uses
  Classes, SysUtils, Math, uItems;

type
  { One thumbnail to prepare }
  TThumbJob = record
    Item: TImageItem;  // the item (used by the main thread only)
    Path, CacheFile: string;  // Path: the file; CacheFile: its thumbnail in the disk cache
    Orient: Integer;  // EXIF orientation of the file
    Bmp: TMemoryStream;  // the finished thumbnail as a BMP (nil when it could not be made)
    FromCache: Boolean;  // True when it was read from the disk cache
    Done: LongInt;  // 1 once a thread has finished the job
  end;

  { TThumbBatch - the thumbnails of one folder load }
  TThumbBatch = class
  private
    FJobs: array of TThumbJob;  // the jobs, in the order they are asked for
    FCount: Integer;  // number of jobs
    FBox: Integer;  // long side of the thumbnails
    FNext: LongInt;  // number of jobs the threads have taken
    FCursor: LongInt;  // the job the main thread takes next
    FAbort: Boolean;  // True when the threads are to stop
    FThreads: array of TThread;  // the threads
  public
    constructor Create(Box: Integer);
    destructor Destroy; override;  // stops the threads and frees the thumbnails not taken
    procedure Add(Item: TImageItem);  // adds an item (before Start only)
    procedure Start;  // starts the threads
    function IsNext(Item: TImageItem): Boolean;  // True when Item is the job the main thread takes next
    function NextReady: Boolean;  // True when that job is finished
    procedure Deliver;  // gives that job's thumbnail to its item and goes on to the next job
    property Count: Integer read FCount;  // number of items added
  end;

implementation

const
  MaxThreads = 8;  // most threads used
  MaxAhead = 48;  // finished thumbnails waiting for the main thread at most (each is a bitmap in memory)

type
  { A thread that prepares thumbnails of a batch }
  TThumbThread = class(TThread)
  private
    FBatch: TThumbBatch;  // the batch it works for
  protected
    procedure Execute; override;
  public
    constructor Create(Batch: TThumbBatch);
  end;

constructor TThumbThread.Create(Batch: TThumbBatch);
begin
  FBatch := Batch;  // the batch
  inherited Create(False);  // run
end;

{ Thread body: takes the next job until none is left or the batch is stopped. }
procedure TThumbThread.Execute;
var
  I: LongInt;  // I: number of the job
  Ms: TMemoryStream;  // Ms: the finished thumbnail
  Cached: Boolean;  // Cached: it came from the disk cache
begin
  while not FBatch.FAbort do
  begin
    I := InterlockedIncrement(FBatch.FNext) - 1;  // take the next job
    if I >= FBatch.FCount then Break;  // none left
    while (I - FBatch.FCursor > MaxAhead) and not FBatch.FAbort do Sleep(2);  // not too far ahead of the main thread
    if FBatch.FAbort then Break;  // stopped
    Ms := nil;  // nothing made yet
    Cached := False;
    try
      Ms := PrepareThumb(FBatch.FJobs[I].Path, FBatch.FJobs[I].CacheFile, FBatch.FJobs[I].Orient, FBatch.FBox, Cached);  // read and scale
    except
      FreeAndNil(Ms);  // the main thread makes this one
    end;
    FBatch.FJobs[I].Bmp := Ms;  // the result
    FBatch.FJobs[I].FromCache := Cached;
    InterlockedExchange(FBatch.FJobs[I].Done, 1);  // finished (written last: the main thread reads the result after this)
  end;
end;

constructor TThumbBatch.Create(Box: Integer);
begin
  FBox := Box;  // thumbnail size
end;

destructor TThumbBatch.Destroy;
var
  I: Integer;  // I: loop counter
begin
  FAbort := True;  // the threads stop after the file they are at
  for I := 0 to High(FThreads) do
  begin
    FThreads[I].WaitFor;  // until it has ended
    FThreads[I].Free;
  end;
  for I := 0 to FCount - 1 do FJobs[I].Bmp.Free;  // thumbnails nobody took
  inherited Destroy;
end;

procedure TThumbBatch.Add(Item: TImageItem);
begin
  if Length(FThreads) > 0 then Exit;  // started: the list must not move any more
  if FCount >= Length(FJobs) then SetLength(FJobs, Max(64, FCount * 2));  // make room
  FJobs[FCount].Item := Item;  // for the main thread
  FJobs[FCount].Path := Item.FullPath;  // copies for the threads
  FJobs[FCount].CacheFile := ThumbCacheName(Item, FBox);
  FJobs[FCount].Orient := Item.Orientation;
  FJobs[FCount].Bmp := nil;  // nothing made yet
  FJobs[FCount].FromCache := False;
  FJobs[FCount].Done := 0;
  Inc(FCount);
end;

procedure TThumbBatch.Start;
var
  N, I: Integer;  // N: number of threads; I: loop counter
begin
  if (FCount = 0) or (Length(FThreads) > 0) then Exit;  // nothing to do, or started already
  N := TThread.ProcessorCount;  // processors of this computer
  if N < 2 then N := 4;  // unknown (or one): some threads still overlap the reading of the files
  N := Max(1, Min(Min(MaxThreads, N - 1), FCount));  // one processor stays for the window
  SetLength(FThreads, N);
  for I := 0 to N - 1 do FThreads[I] := TThumbThread.Create(Self);  // start them
end;

function TThumbBatch.IsNext(Item: TImageItem): Boolean;
begin
  Result := (Length(FThreads) > 0) and (FCursor < FCount) and (FJobs[FCursor].Item = Item);  // the job in turn is this item's
end;

function TThumbBatch.NextReady: Boolean;
begin
  Result := (FCursor >= FCount) or (InterlockedCompareExchange(FJobs[FCursor].Done, 1, 1) = 1);  // a thread has finished it
end;

procedure TThumbBatch.Deliver;
var
  J: Integer;  // J: the job
begin
  if (FCursor >= FCount) or not NextReady then Exit;  // nothing to take
  J := FCursor;
  if FJobs[J].Bmp <> nil then
  begin
    AdoptThumb(FJobs[J].Item, FJobs[J].Bmp, FJobs[J].FromCache, FBox);  // the item gets its bitmap
    FreeAndNil(FJobs[J].Bmp);  // the BMP is not needed any more
  end;
  InterlockedIncrement(FCursor);  // the next job (the threads watch this to stay close)
end;

end.
