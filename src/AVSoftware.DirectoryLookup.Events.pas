unit AVSoftware.DirectoryLookup.Events;

interface

type
  TLookupProgressEvent = procedure(sender: TObject;
    NewDirectories: array of string) of object;

implementation

end.
