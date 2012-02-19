class CWorkerThread
{
	;Message number used for communication between main and worker threads.
	;In total, 6 messages are used, starting from this value
	static Message := 8742
	static Threads := []
	
	;Public:
	Task := "" ;Contains information about the task to be executed by the worker thread
	State := "Stopped" ;States: Stopped, Running, Paused, Finished
	;Progress := 0 ;Progress can be set in the worker thread and queried in the main thread. Use any numeric values you like.
	
	;The following variables are event handlers. Simply assign a function name to their handler member, e.g. this.OnStopHandler.Handler := "OnStop"
	OnStopHandler := new EventHandler()
	OnPauseHandler := new EventHandler()
	OnResumeHandler := new EventHandler()
	OnFinishHandler := new EventHandler()
	ProgressHandler := new EventHandler()
	
	;Private:
	WorkerID := "" ;Process ID of the worker thread (set for all threads)
	WorkerHWND := "" ;window handle of the worker thread (only set for main thread)
	_Progress := 0 ;Internal progress value so "Progress" can use meta functions
	IsWorkerThread := false ;true if this instance of the script is a worker thread, false otherwise
	WorkerThread := "" ;WorkerThread instance (only in worker thread)
	
	;This class is serialized and passed to the worker thread
	Class CTask
	{
		WorkerFunction := ""
		Parameters := []
		CanPause := 0
		CanStop := 0
		MainHWND := "" ;window handle of the main thread (only set for worker threads)
	}
	__new(WorkerFunction, CanPause = 0, CanStop = 0)
	{
		if(!FileExist(WorkerFunction))
		{
			if(!IsFunc(WorkerFunction))
				throw new Exception("CWorkerThread: Invalid worker function: " WorkerFunction)
			this.Task := new this.CTask()
			this.Task.WorkerFunction := WorkerFunction
			this.Task.CanPause := CanPause
			this.Task.CanStop := CanStop
			this.Task.MainHWND := Format("{1:d}", A_ScriptHwnd)
			this.IsWorkerThread := false
			loop 6
				OnMessage(this.Message + (A_Index - 1), "MainThread_Monitor")
		}
		else
		{
			FileRead, Task, % WorkerFunction
			this.Task := LSON(Task)
			this.IsWorkerThread := true
			DetectHiddenWindows_Prev := A_DetectHiddenWindows
			DetectHiddenWindows, On
			WinGet, PID, PID, ahk_id %A_ScriptHwnd%
			this.WorkerID := PID
			CWorkerThread.WorkerThread := this
			loop 6
				OnMessage(this.Message + (A_Index - 1), "WorkerThread_Monitor")
			
			SendMessage, this.Message, PID, A_ScriptHWND, ,% "ahk_id " this.Task.MainHWND
			if(!DetectHiddenWindows_Prev)
				DetectHiddenWindows, Off
			
			if(ErrorLevel != 1) ;If there is an error, return an empty object so this instance can exit
				return ""
		}
	}
	Start(Parameters*)
	{
		if(this.State != "Stopped" && this.State != "Finished" || this.IsWorkerThread)
			return
		
		this.Task.Parameters := Parameters
		this.Progress := 0
		
		;Write temporary file with object data (might be replaced with WM_COPYDATA later)
		FileDelete, %A_Temp%\Workerthread.lson
		FileAppend, % LSON(this.Task), %A_Temp%\Workerthread.lson
		;Run the worker instance of this script. It will send back a start message with its window handle
		run % (A_IsCompiled ? A_ScriptFullPath : A_AhkPath) (A_IsCompiled ? "" : " """ A_ScriptFullPath """") " -ActAsWorker: """ A_Temp "\Workerthread.lson""", %A_ScriptDir%, UseErrorLevel, PID
		if(!ErrorLevel)
		{
			this.WorkerID := PID
			this.Threads[PID] := this
		}
	}
	Pause()
	{
		if(!this.Task.CanPause || this.State != "Running")
			return
		DetectHiddenWindows_Prev := A_DetectHiddenWindows
		DetectHiddenWindows, On
		
		if(this.IsWorkerThread)
			;Post pause message to main thread
			PostMessage, CWorkerThread.Message + 1, this.WorkerID,,, % "ahk_id " this.Task.MainHWND
		else
			;Post pause message to worker
			PostMessage, this.Message + 1,,,, % "ahk_id " this.WorkerHWND
		this.State := "Paused"
		if(!DetectHiddenWindows_Prev)
			DetectHiddenWindows, Off
	}
	Resume()
	{
		if(!this.Task.CanPause || this.State != "Paused")
			return
		
		DetectHiddenWindows_Prev := A_DetectHiddenWindows
		DetectHiddenWindows, On
		
		if(this.IsWorkerThread)
			;Post resume message to main thread
			PostMessage, CWorkerThread.Message + 2, this.WorkerID,,, % "ahk_id " this.Task.MainHWND
		else
			;Post resume message to worker
			PostMessage, this.Message + 2,,,, % "ahk_id " this.WorkerHWND
		this.State := "Running"
		if(!DetectHiddenWindows_Prev)
			DetectHiddenWindows, Off
	}
	Stop(ResultOrReason = 0)
	{
		if(!this.Task.CanStop || (this.State != "Running" && this.State != "Paused"))
			return
		
		DetectHiddenWindows_Prev := A_DetectHiddenWindows
		DetectHiddenWindows, On
		
		if(this.IsWorkerThread)
			;Post stop message to main thread
			PostMessage, CWorkerThread.Message + 3, this.WorkerID, ResultOrReason,, % "ahk_id " this.Task.MainHWND
		else
			;Post stop message to worker
			PostMessage, this.Message + 3,,ResultOrReason,, % "ahk_id " this.WorkerHWND
		this.State := "Stopped"
		
		if(!DetectHiddenWindows_Prev)
			DetectHiddenWindows, Off
	}
	
	__get(Key)
	{
		if(Key = "Progress")
			return this._Progress
	}
	__set(Key, Value)
	{
		if(Key = "Progress")
		{
			if(this.IsWorkerThread)
			{
				this._Progress := Value
				
				DetectHiddenWindows_Prev := A_DetectHiddenWindows
				DetectHiddenWindows, On
		
				PostMessage, CWorkerThread.Message + 4, this.WorkerID, Value,, % "ahk_id " this.Task.MainHWND
				
				if(!DetectHiddenWindows_Prev)
					DetectHiddenWindows, Off
			}
			return Value
		}
	}
}

/*
Messages sent by the worker thread which are processed here:
type		msg (offset)	wParam	lParam
Start		0				PID		hwnd (both of worker thread)
Pause		1				PID
Resume		2				PID
Stop		3				PID		result (numeric, possibly an error code)
Progress	4				PID		Progress value (numeric)
Finish		5				PID		result (numeric, return value, error code, etc)
*/
MainThread_Monitor(wParam, lParam, msg, hwnd)
{
	WorkerThread := CWorkerThread.Threads[wParam]
	if(!WorkerThread)
		return
	;~ msgbox % "main thread: " wParam ", " lParam ", " (msg-CWorkerThread.Message)
	if(msg = WorkerThread.Message) ;Start
	{
		DetectHiddenWindows_Prev := A_DetectHiddenWindows
		DetectHiddenWindows, On
		if(WinExist("ahk_id " lParam))
		{
			;Successfully acquired window handle of worker script's main window
			WorkerThread.WorkerHWND := lParam
			WorkerThread.State := "Running"
			if(!DetectHiddenWindows_Prev)
				DetectHiddenWindows, Off
			return 1
		}
		if(!DetectHiddenWindows_Prev)
			DetectHiddenWindows, Off
		return 0
	}
	else if(msg = WorkerThread.Message + 1) ;Pause
	{
		WorkerThread.State := "Paused"
		WorkerThread.OnPauseHandler.(WorkerThread)
	}
	else if(msg = WorkerThread.Message + 2) ;Resume
	{
		WorkerThread.State := "Running"
		WorkerThread.OnResumeHandler.(WorkerThread)
	}
	else if(msg = WorkerThread.Message + 3) ;Stop
	{
		WorkerThread.State := "Stopped"
		WorkerThread.OnStopHandler.(WorkerThread, lParam)
		CWorkerThread.Threads.Remove(WorkerThread.PID)
	}
	else if(msg = WorkerThread.Message + 4) ;Progress (uses PostMessage for speed)
		WorkerThread.ProgressHandler.(WorkerThread, lParam)
	else if(msg = WorkerThread.Message + 5) ;Finish
	{
		WorkerThread.State := "Finished"
		WorkerThread.OnFinishHandler.(WorkerThread, lParam)
		CWorkerThread.Threads.Remove(WorkerThread.PID)
	}
}

/*
Messages sent by the main thread which are processed here:
type		msg (offset)	wParam	lParam
Pause		1				
Resume		2				
Stop		3						reason (numeric)
*/
WorkerThread_Monitor(wParam, lParam, msg, hwnd)
{
	WorkerThread := CWorkerThread.WorkerThread
	if(!WorkerThread)
		return 0
	;~ msgbox % "worker thread: " wParam ", " lParam ", " (msg-CWorkerThread.Message)
	if(msg = CWorkerThread.Message + 1) ;Pause
	{
		if(WorkerThread.Task.CanPause && WorkerThread.State = "Running")
		{
			WorkerThread.State := "Paused" ;State is set here, but the task itself needs to obey this!
			WorkerThread.OnPauseHandler.()
		}
	}
	else if(msg = CWorkerThread.Message + 2) ;Resume
	{
		if(WorkerThread.State = "Paused")
		{
			WorkerThread.State := "Running" ;State is set here, but the task itself needs to obey this!
			WorkerThread.OnResumeHandler.()
		}
	}
	else if(msg = CWorkerThread.Message + 3) ;Stop
	{
		if(WorkerThread.Task.CanStop && WorkerThread.State = "Running")
		{
			WorkerThread.OnStopHandler.(lParam)
			WorkerThread.State := "Stopped" ;State is set here, but the task itself needs to obey this!
		}
	}
}
;This function needs to be called in the Autoexecute section of the script.
;If this is the main instance of the script, this function will simply return.
;Otherwise it will call the worker function and exit the worker script when it's finished.
InitWorkerThread()
{
	global
	local Params := [], WorkerFunction, result
	Loop %0%
		Params[A_Index] := %A_Index%
	if(Params.MaxIndex() = 2 && Params[1] = "-ActAsWorker:" && FileExist(params[2]))
	{
		WorkerThread := new CWorkerThread(params[2])
		if(!WorkerThread)
			ExitApp
		WorkerThread.State := "Running"
		
		WorkerFunction := WorkerThread.Task.WorkerFunction
		
		result := %WorkerFunction%(WorkerThread, WorkerThread.Task.Parameters*)
		
		;if we are in stopped state, this thread was cancelled and no finish event is sent
		if(WorkerThread.State != "Stopped")
		{
			DetectHiddenWindows_Prev := A_DetectHiddenWindows
			DetectHiddenWindows, On
			PostMessage, CWorkerThread.Message + 5, WorkerThread.WorkerID, result, , % "ahk_id " WorkerThread.Task.MainHWND
			if(!DetectHiddenWindows_Prev)
				DetectHiddenWindows, Off
		}
		ExitApp
	}
	return
}

ExploreObj(Obj, NewRow="`n", Equal="  =  ", Indent="`t", Depth=12, CurIndent="") { 
    for k,v in Obj 
        ToReturn .= CurIndent . k . (IsObject(v) && depth>1 ? NewRow . ExploreObj(v, NewRow, Equal, Indent, Depth-1, CurIndent . Indent) : Equal . v) . NewRow 
    return RTrim(ToReturn, NewRow) 
}
#include <LSON>
#include <EventHandler>