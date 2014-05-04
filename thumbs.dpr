program Thumbs;

uses
  Vcl.Forms,
  AVSoftware.Thumbs.Forms.MainForm
    in 'src\AVSoftware.Thumbs.Forms.MainForm.pas' {ThumbnailDisplayerMainForm} ,
  Vcl.Themes,
  Vcl.Styles,
  AVSoftware.Threaded.DirectoryLookup
    in 'src\AVSoftware.Threaded.DirectoryLookup.pas',
  AVSoftware.Threaded.ThumbnailGenerator
    in 'src\AVSoftware.Threaded.ThumbnailGenerator.pas',
  AVSoftware.Common.Events in 'src\AVSoftware.Common.Events.pas',
  AVSoftware.StateMachine.State in 'src\AVSoftware.StateMachine.State.pas',
  AVSoftware.Thumbs.Forms.AboutForm
    in 'src\AVSoftware.Thumbs.Forms.AboutForm.pas' {AboutForm} ,
  AVSoftware.StateMachine.DirectoryLookup.JobState.IncrementalReceiver
    in 'src\AVSoftware.StateMachine.DirectoryLookup.JobState.IncrementalReceiver.pas',
  AVSoftware.StateMachine.DirectoryLookup.JobState.AllAtOnceReceiver
    in 'src\AVSoftware.StateMachine.DirectoryLookup.JobState.AllAtOnceReceiver.pas',
  AVSoftware.DirectoryLookup.Events
    in 'src\AVSoftware.DirectoryLookup.Events.pas',
  AVSoftware.DirectoryLookup.Constants
    in 'src\AVSoftware.DirectoryLookup.Constants.pas',
  AVSoftware.Threaded.WorkerThread
    in 'src\AVSoftware.Threaded.WorkerThread.pas',
  AVSoftware.Common.GlobalLog in 'src\AVSoftware.Common.GlobalLog.pas',
  AVSoftware.DirectoryLookup.LookupManager
    in 'src\AVSoftware.DirectoryLookup.LookupManager.pas',
  AVSoftware.DirectoryLookup.NodeInfo
    in 'src\AVSoftware.DirectoryLookup.NodeInfo.pas',
  AVSoftware.Common.ErrorQueue in 'src\AVSoftware.Common.ErrorQueue.pas',
  AVSoftware.Pools.DirectoryLookupPool
    in 'src\AVSoftware.Pools.DirectoryLookupPool.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Thumbnail Displayer';
  TStyleManager.TrySetStyle('Light');
  Application.CreateForm(TThumbnailDisplayerMainForm,
    ThumbnailDisplayerMainForm);
  Application.Run;

end.
