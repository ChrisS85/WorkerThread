#SingleInstance, off ;required for obvious reasons
;This function needs to be called in the Autoexecute section so this instance
;can possibly turn into a worker thread. The worker thread stays in this function during its runtime.
InitWorkerThread()
;Main thread continues here
Gui, Add, Progress, vProgressBar w400, 0
Gui, Add, Button, vMainStart gMainStart y+10, Start
Gui, Add, Button, vMainPause gMainPause x+10 w50 Disabled, Pause
Gui, Add, Button, vMainStop gMainStop x+10 Disabled, Stop

Gui, +LabelMainGUI
Gui, Show

;Create the worker thread! It will be reused in this program to demonstrate the possibility
WorkerThread := new CWorkerThread("WorkerFunction", ["A Parameter!"], 1, 1)

;Setup event handlers for the main thread
WorkerThread.OnPauseHandler.Handler := "OnPausedByWorker"
WorkerThread.OnResumeHandler.Handler := "OnResumedByWorker"
WorkerThread.OnStopHandler.Handler := "OnStoppedByWorker"
WorkerThread.ProgressHandler.Handler := "ProgressHandler"
WorkerThread.OnFinishHandler.Handler := "OnFinish"
return

MainGUIClose:
if(WorkerThread.State = "Running" || WorkerThread.State = "Paused")
	WorkerThread.Stop(0) ;Stop the worker thread if it is still running
ExitApp

;The main thread can control the execution of the worker thread, demonstrated by the event handlers of the buttons below:
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

;The functions below are event handlers of the main thread. They were specified above.
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

;Progress is a numeric integer value
ProgressHandler(WorkerThread, Progress)
{
	global ProgressBar
	GuiControl, , ProgressBar, %Progress%
}


;This is the main worker function that is executed in the worker thread.
;The thread will exit shortly after this function returns.
;This function may have a many parameters as desired, but they need to be specified during the worker thread creation.
WorkerFunction(WorkerThread, Param)
{
	global WorkerProgress, WorkerPause, WorkerStop
	;We can set up some event handlers for the worker thread here
	;so it can react to pause/resume/stop events coming from the main thread
	WorkerThread.OnPauseHandler.Handler := "OnPausedByMain"
	WorkerThread.OnResumeHandler.Handler := "OnResumedByMain"
	WorkerThread.OnStopHandler.Handler := "OnStoppedByMain"
	Gui, Add, Progress, vWorkerProgress w400, 0
	Gui, Add, Button, vWorkerPause gWorkerPause w50, Pause
	Gui, Add, Button, vWorkerStop gWorkerStop x+10, Stop
	Gui, +LabelWorkerGUI
	Gui, Show,, Passed Parameter: %Param%
	
	;This is a suggested structure for a worker thread that uses a loop.
	;It properly accounts for state changes (which can be caused by the main thread or this thread)
	while(A_Index < 100 && WorkerThread.State = "Running")
	{
		GuiControl,,WorkerProgress, %A_Index%
		Sleep 100 ;This simulates work that takes some time
		WorkerThread.Progress := A_Index ;Report the progress of the worker thread.
		while(WorkerThread.State = "Paused") ;Optionally wait a while for resuming the worker thread.
			Sleep 10
	}
	;the return value of this function is only used when the worker thread wasn't stopped.
	return 42
}

;Prevent closing of the worker thread. Alternatively, the worker thread could stop itself.
WorkerGUIClose:
return

;The worker thread can control the execution of itself, demonstrated by the event handlers of the buttons below:
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

;The functions below are event handlers of the worker thread. They were specified above.
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

#include <WorkerThread>