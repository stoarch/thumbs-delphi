{ *******************************************************

  AVSoftware Common Events

  Created by Afonin Vladimir
  mailto: stormarchitextor@gmail.com

  License: GNU GPL3 (http://www.gnu.org)

  ******************************************************* }

unit AVSoftware.Common.Events;

interface

type
  TErrorEvent = procedure(sender: TObject; error_code: integer;
    error_message: string) of object;

  TLogEvent = procedure(sender: TObject; Message: string) of object;

  TNotificationEvent = procedure(sender: TObject) of object;

implementation

end.
