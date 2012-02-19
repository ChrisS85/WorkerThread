#SingleInstance, off ;required for obvious reasons
InitWorkerThread() ;Worker thread stays in this function during its runtime
;Main thread continues here
Gui, Add, Progress, vProgressBar w400, 0
Gui, Add, Button, vMainStart gMainStart y+10, Start
Gui, Add, Button, vMainPause gMainPause x+10 w50 Disabled, Pause
Gui, Add, Button, vMainStop gMainStop x+10 Disabled, Stop

Gui, +LabelMainGUI
Gui, Show
WorkerThread := new CWorkerThread("WorkerFunction", ["A Parameter!"], "OnEndHandler", "ProgressHandler", 1, 1)
WorkerThread.OnPauseHandler.Handler := "OnPausedByWorker"
WorkerThread.OnResumeHandler.Handler := "OnResumedByWorker"
WorkerThread.OnStopHandler.Handler := "OnStoppedByWorker"
WorkerThread.ProgressHandler.Handler := "ProgressHandler"
WorkerThread.OnFinishHandler.Handler := "OnFinish"
return
MainGUIClose:
ExitApp

MainStart:
if(WorkerThread.State = "Stopped" || WorkerThread.State = "Finished")
{
	WorkerThread.Start() ;Starting works only when in stopped state. The progress is reset to zero.
	GuiControl, Disable, MainStart
	GuiControl, Enable, MainStop
	GuiControl, Enable, MainPause
	Gui, Show,, Running
}
return

MainPause:
if(WorkerThread.State = "Paused")
{
	WorkerThread.Resume()
	GuiControl, , MainPause, Pause
	Gui, Show,, Running
}
else if(WorkerThread.State = "Running")
{
	WorkerThread.Pause()
	GuiControl, , MainPause, Resume
	Gui, Show,,Paused by main thread
}
return

MainStop:
if(WorkerThread.State = "Running")
{
	WorkerThread.Stop(1) ;We can pass a reason for the stop to the worker thread
	GuiControl, Disable, MainStop
	GuiControl, Enable, MainStart
	Gui, Show,,Stopped by main thread
}
return

WorkerFunction(WorkerThread, Param)
{
	global Progress, WorkerPause, WorkerStop
	;We can set up some event handlers for the worker thread here
	;so it can react to pause/resume/stop events coming from the main thread
	WorkerThread.OnPauseHandler.Handler := "OnPausedByMain"
	WorkerThread.OnResumeHandler.Handler := "OnResumedByMain"
	WorkerThread.OnStopHandler.Handler := "OnStoppedByMain"
	Gui, Add, Progress, vProgress w400, 0
	Gui, Add, Button, vWorkerPause gWorkerPause w50, Pause
	Gui, Add, Button, vWorkerStop gWorkerStop x+10, Stop
	Gui, +LabelWorkerGUI
	Gui, Show,, Passed Parameter: %Param%
	while(A_Index < 100 && WorkerThread.State = "Running")
	{
		GuiControl,,Progress, %A_Index%
		Sleep 100
		WorkerThread.Progress := A_Index
		while(WorkerThread.State = "Paused")
			Sleep 100
	}
	;the return value of this function is only used when the worker thread wasn't stopped.
	return 42
}
WorkerGUIClose:
return

WorkerPause:
if(WorkerThread.State = "Paused")
{
	WorkerThread.Resume()
	GuiControl, , WorkerPause, Pause
}
else if(WorkerThread.State = "Running")
{
	WorkerThread.Pause()
	GuiControl, , WorkerPause, Resume
}
return

WorkerStop:
if(WorkerThread.State = "Running" || WorkerThread.State = "Paused")
{
	WorkerThread.Stop(23) ;Parameter is passed back to main thread as result
	GuiControl, Disable, WorkerStop
}
return
OnPausedByMain()
{
	global WorkerPause
	GuiControl, , WorkerPause, Resume
	Gui, Show,, Paused by main thread
}
OnResumedByMain()
{	
	global WorkerPause
	GuiControl, , WorkerPause, Pause
	Gui, Show,, Running Worker thread
}
OnStoppedByMain(reason)
{
	Msgbox Stopped by main thread! Reason: %reason%
}
OnPausedByWorker(WorkerThread)
{
	global MainPause
	GuiControl, ,MainPause, Resume
	Gui, Show,, Paused by worker thread
}
OnResumedByWorker(WorkerThread)
{
	global MainPause
	GuiControl, ,MainPause, Pause
	Gui, Show,, Running
}
OnStoppedByWorker(WorkerThread, Result)
{
	global
	GuiControl, Enable, MainStart
	GuiControl, Disable, MainPause
	GuiControl, Disable, MainStop
	Gui, Show,, Stopped by worker thread! Result: %Result%
}
OnFinish(WorkerThread, Result)
{
	global
	Gui, Show,, Finished! Result: %Result%
	GuiControl, Enable, MainStart
	GuiControl, Disable, MainPause
	GuiControl, Disable, MainStop
}

ProgressHandler(WorkerThread, Progress)
{
	global ProgressBar
	GuiControl, , ProgressBar, %Progress%
}

#include <WorkerThread>