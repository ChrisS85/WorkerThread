﻿class CWorkerThread
{
	;Message number used for communication between main and worker threads.
	;In total, 6 messages are used, starting from this value
	static Message := 8742
	static Threads := []
	
	;Public:
	Task := "" ;Contains information about the task to be executed by the worker thread
	State := "Stopped" ;States: Stopped, Running, Paused, Finished
	;Progress := 0 ;Progress can be set in the worker thread and queried in the main thread. Use any numeric values you like.
	
	;The following variables are event handlers. Simply assign a function name to their handler member, e.g. this.OnStop.Handler := "OnStop".
	;The first argument of these events on the main thread is the worker thread object.
	;They can have additional arguments (which can be numbers, strings or objects unless otherwise noted) as described below:
	OnStop := new EventHandler() ;Called on both threads when the operation of the worker thread is stopped by the other thread. The function receives an argument from the other thread that acts as reason or result value.
	OnPause := new EventHandler() ;Called on both threads when the operation of the worker thread is paused by the other thread
	OnResume := new EventHandler() ;Called on both threads when the operation of the worker thread is resumed by the other thread
	OnFinish := new EventHandler() ;Raised on the main thread when the worker thread is finished. The function receives the result from the worker thread.
	OnData := new EventHandler() ;Raised on both threads when data from the other thread is received. The function receives a Data parameter.
	OnProgress := new EventHandler() ;Raised on the main thread when the worker thread changes its Progress value. The function receives a numeric Progress value.
	
	;Private:
	WorkerID := "" ;Process ID of the worker thread (set for all threads)
	WorkerHWND := "" ;window handle of the worker thread (only set for main thread)
	MainHWND := "" ;window handle of the main thread (passed to worker on start)
	_Progress := 0 ;Internal progress value so "Progress" can use meta functions
	IsWorkerThread := false ;true if this instance of the script is a worker thread, false otherwise
	WorkerThread := "" ;WorkerThread instance (only in worker thread)
	Data := []
	;This class is serialized and passed to the worker thread
	Class CTask
	{
		WorkerFunction := ""
		Parameters := []
		CanPause := 0
		CanStop := 0
		ExitAfterTask := 1 ;If true, the worker thread will exit once the task is completed. Otherwise it will keep running and wait for new tasks.
	}
	;On worker threads, WorkerFunction is the window handle of the main thread
	__new(WorkerFunction, CanPause = 0, CanStop = 0, ExitAfterTask = 1)
	{
		DetectHiddenWindows_Prev := A_DetectHiddenWindows
		DetectHiddenWindows, On
		if(!WinExist("ahk_id " WorkerFunction))
		{
			if(!IsFunc(WorkerFunction))
				throw new Exception("CWorkerThread: Invalid worker function: " WorkerFunction)
			this.Task := new this.CTask()
			this.Task.WorkerFunction := WorkerFunction
			this.Task.CanPause := CanPause
			this.Task.CanStop := CanStop
			this.Task.ExitAfterTask := ExitAfterTask
			this.IsWorkerThread := false
			loop 6
				OnMessage(this.Message + (A_Index - 1), "MainThread_Monitor")
			OnMessage(0x4a, "MainThread_Monitor")
		}
		else
		{
			this.MainHWND := WorkerFunction
			this.IsWorkerThread := true
			DetectHiddenWindows_Prev := A_DetectHiddenWindows
			DetectHiddenWindows, On
			WinGet, PID, PID, ahk_id %A_ScriptHwnd%
			this.WorkerID := PID
			CWorkerThread.WorkerThread := this
			loop 6
				OnMessage(this.Message + (A_Index - 1), "WorkerThread_Monitor")
			OnMessage(0x4a, "WorkerThread_Monitor")
			
			SendMessage, this.Message, PID, A_ScriptHWND, ,% "ahk_id " this.MainHWND
			if(!DetectHiddenWindows_Prev)
				DetectHiddenWindows, Off
			
			if(ErrorLevel != 1) ;If there is an error, return an empty object so this instance can exit
				return ""
		}
		if(!DetectHiddenWindows_Prev)
			DetectHiddenWindows, Off
	}
	SetTask(WorkerFunction, CanPause = 0, CanStop = 0, ExitAfterTask = 1)
	{
		if(this.State = "Stopped" || this.State = "Finished")
		{
			this.Task := new this.CTask()
			this.Task.WorkerFunction := WorkerFunction
			this.Task.CanPause := CanPause
			this.Task.CanStop := CanStop
			this.Task.ExitAfterTask := ExitAfterTask
		}
	}
	Start(Parameters*)
	{
		if(this.State != "Stopped" && this.State != "Finished" || this.IsWorkerThread)
			return
		
		this.Task.Parameters := Parameters
		this.Progress := 0
		
		Process, Exist, % this.WorkerID
		;Process already exists from a previous task -> make it execute the current task
		if(ErrorLevel && this.WorkerHWND && Send_WM_COPYDATA(LSON({Type : 0, Task : this.Task}), this.WorkerHWND))
			this.State := "Running"
		else ;Otherwise start new worker thread. Task is passed once the worker thread responds
		{
			;Write temporary file with object data (might be replaced with WM_COPYDATA later)
			;~ FileDelete, %A_Temp%\Workerthread.lson
			;~ FileAppend, % LSON(this.Task), %A_Temp%\Workerthread.lson
			;Run the worker instance of this script. It will send back a start message with its window handle
			run % (A_IsCompiled ? A_ScriptFullPath : A_AhkPath) (A_IsCompiled ? "" : " """ A_ScriptFullPath """") " -ActAsWorker: " A_ScriptHwnd, %A_ScriptDir%, UseErrorLevel, PID
			if(!ErrorLevel)
			{
				this.WorkerID := PID
				this.Threads[PID] := this
			}
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
			PostMessage, CWorkerThread.Message + 1, this.WorkerID,,, % "ahk_id " this.MainHWND
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
			PostMessage, CWorkerThread.Message + 2, this.WorkerID,,, % "ahk_id " this.MainHWND
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
			;Send stop message to main thread
			Send_WM_COPYDATA(LSON({Type : 1, PID: this.WorkerID, Result : ResultOrReason}), this.MainHWND)
		else
			;Send stop message to worker
			Send_WM_COPYDATA(LSON({Type : 1, Result : ResultOrReason}), this.WorkerHWND)
		this.State := "Stopped"
		
		if(!DetectHiddenWindows_Prev)
			DetectHiddenWindows, Off
	}
	;Sends data to the other thread. The other thread reacts to it by listening to the OnData event
	SendData(Data)
	{
		if(this.IsWorkerThread)
			;Send data message to main thread
			Send_WM_COPYDATA(LSON({Type : 3, PID: this.WorkerID, Data : Data}), this.MainHWND)
		else
			;Send data message to worker
			Send_WM_COPYDATA(LSON({Type : 3, Data : Data}), this.WorkerHWND)
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
				
				PostMessage, CWorkerThread.Message + 4, this.WorkerID, Value,, % "ahk_id " this.MainHWND
				
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
	if(msg = 0x4a) ;WM_COPYDATA
	{
		StringAddress := NumGet(lParam + 4 + A_PtrSize, 0, "PTR")
		StringLength := DllCall("lstrlen", "PTR", StringAddress) * (A_IsUnicode ? 2 : 1)
		if(StringLength <= 0)
			return 0
		else
		{
			CopyOfData := StrGet(NumGet(lParam + 2 * A_PtrSize))  ; Copy the string out of the structure.
			Data := LSON(CopyOfData) ;By setting this the Worker loop can continue
			WorkerThread := CWorkerThread.Threads[Data.PID]
			if(!WorkerThread)
				return 0
			if(Data.Type = 1) ;Stop
			{
				WorkerThread.State := "Stopped"
				WorkerThread.Result := Data.Result
				SetTimer, WorkerThread_OnStop, -0
			}
			else if(Data.Type = 2) ;Finish
			{
				WorkerThread.State := "Finished"
				WorkerThread.Result := Data.Result
				SetTimer, WorkerThread_OnFinish, -0
			}
			else if(Data.Type = 3) ;Data
			{
				WorkerThread.Data.Insert(Data.Data)
				SetTimer, WorkerThread_OnData, -0
			}
			return true  ; Returning 1 (true) is the traditional way to acknowledge this message.
		}
	}
	
	WorkerThread := CWorkerThread.Threads[wParam]
	if(!WorkerThread)
		return
	
	if(msg = WorkerThread.Message) ;Start
	{
		DetectHiddenWindows_Prev := A_DetectHiddenWindows
		DetectHiddenWindows, On
		if(WinExist("ahk_id " lParam))
		{
			;Successfully acquired window handle of worker script's main window
			WorkerThread.WorkerHWND := lParam
			if(Send_WM_COPYDATA(LSON({Type : 0 , Task : WorkerThread.Task}), lParam))
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
		WorkerThread.OnPause.(WorkerThread)
	}
	else if(msg = WorkerThread.Message + 2) ;Resume
	{
		WorkerThread.State := "Running"
		WorkerThread.OnResume.(WorkerThread)
	}
	;~ else if(msg = WorkerThread.Message + 3) ;Stop
	;~ {
		;~ WorkerThread.State := "Stopped"
		;~ WorkerThread.OnStop.(WorkerThread, lParam)
		;~ CWorkerThread.Threads.Remove(WorkerThread.PID)
	;~ }
	else if(msg = WorkerThread.Message + 4) ;Progress (uses PostMessage for speed)
		WorkerThread.OnProgress.(WorkerThread, lParam)
	;~ else if(msg = WorkerThread.Message + 5) ;Finish
	;~ {
		;~ WorkerThread.State := "Finished"
		;~ WorkerThread.OnFinish.(WorkerThread, lParam)
		;~ CWorkerThread.Threads.Remove(WorkerThread.PID)
	;~ }
}

/*
Messages sent by the main thread which are processed here:
type		msg (offset)	wParam	lParam
WM_COPYDATA	0x4a								;Used for passing tasks, sending stop command and custom data
Pause		1				
Resume		2				
Stop		3						reason (numeric)
*/
WorkerThread_Monitor(wParam, lParam, msg, hwnd)
{
	WorkerThread := CWorkerThread.WorkerThread
	if(!WorkerThread)
		return 0
	if(msg = 0x4a) ;WM_COPYDATA
	{
		StringAddress := NumGet(lParam + 4 + A_PtrSize, 0, "PTR")  ; lParam+8 is the address of CopyDataStruct's lpData member.
		StringLength := DllCall("lstrlen", "PTR", StringAddress) * (A_IsUnicode ? 2 : 1)
		if(StringLength <= 0)
			return 0
		else
		{
			CopyOfData := StrGet(NumGet(lParam + 2 * A_PtrSize))  ; Copy the string out of the structure.
			Data := LSON(CopyOfData) ;By setting this the Worker loop can continue
			if(Data.Type = 0) ;Task
				WorkerThread.Task := Data.Task
			else if(Data.Type = 1)
			{
				WorkerThread.Result := Data.Result
				SetTimer, WorkerThread_OnStop, -0
			}
			else if(Data.Type = 3) ;Data
			{
				WorkerThread.Data.Insert(Data.Data)
				SetTimer, WorkerThread_OnData, -0
			}
			return true  ; Returning 1 (true) is the traditional way to acknowledge this message.
		}
	}
	;~ msgbox % "worker thread: " wParam ", " lParam ", " (msg-CWorkerThread.Message)
	if(msg = CWorkerThread.Message + 1) ;Pause
	{
		if(WorkerThread.Task.CanPause && WorkerThread.State = "Running")
		{
			WorkerThread.State := "Paused" ;State is set here, but the task itself needs to obey this!
			WorkerThread.OnPause.()
		}
	}
	else if(msg = CWorkerThread.Message + 2) ;Resume
	{
		if(WorkerThread.State = "Paused")
		{
			WorkerThread.State := "Running" ;State is set here, but the task itself needs to obey this!
			WorkerThread.OnResume.()
		}
	}
	;~ else if(msg = CWorkerThread.Message + 3) ;Stop
	;~ {
		;~ if(WorkerThread.Task.CanStop && (WorkerThread.State = "Running" || WorkerThread.State = "Paused"))
		;~ {
			;~ WorkerThread.OnStop.(lParam)
			;~ WorkerThread.State := "Stopped" ;State is set here, but the task itself needs to obey this!
		;~ }
	;~ }
}

;Called from worker/main message handler so that OnStop doesn't block the message handling function.
WorkerThread_OnStop:
if(WorkerThread && WorkerThread.IsWorkerThread)
{
	WorkerThread.OnStop.(WorkerThread.Result)
	WorkerThread.Remove("Result")
	WorkerThread.State := "Stopped" ;State is set here, but the task itself needs to obey this!
}
else
	WorkerThread_OnStopOrFinish()
return

;Called from main message handler so that OnFinish doesn't block the message handling function.
WorkerThread_OnFinish:
WorkerThread_OnStopOrFinish()
return

WorkerThread_OnStopOrFinish()
{
	RemovePIDs := []
	for pid, WorkerThread in CWorkerThread.Threads
	{
		if((WorkerThread.State = "Stopped" || WorkerThread.State = "Finished") && WorkerThread.HasKey("Result"))
		{
			WorkerThread.OnStop.(WorkerThread, WorkerThread.Result)
			WorkerThread.Remove("Result")
			if(WorkerThread.Task.ExitAfterTask)
				RemovePIDs.Insert(pid)				
		}
	}
	for i, pid in RemovePIDs
		CWorkerThread.Threads.Remove(pid)
}

;Called from worker/main message handler when custom data is received so that OnData doesn't block the message handling function.
WorkerThread_OnData:
WorkerThread_OnData()
return

WorkerThread_OnData()
{
	global
	local found, pid, Thread
	;To prevent possible skips of OnData events, we loop through all available data until none is found. This should decrease the chance of misses.
	found := true
	while(found)
	{
		found := false
		if(WorkerThread && WorkerThread.IsWorkerThread)
		{
			while(WorkerThread.Data.MaxIndex())
			{
				WorkerThread.OnData.(WorkerThread.Data.Remove())
				found := true
			}
		}
		else
		{
			for pid, Thread in CWorkerThread.Threads
			{
				while(Thread.Data.MaxIndex())
				{
					Thread.OnData.(Thread, Thread.Data.Remove())
					found := true
				}
			}
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
	DetectHiddenWindows_Prev := A_DetectHiddenWindows
	DetectHiddenWindows, On
	if(Params.MaxIndex() = 2 && Params[1] = "-ActAsWorker:" && WinExist("ahk_id " params[2]))
	{
		WorkerThread := new CWorkerThread(params[2])
		if(!WorkerThread)
			ExitApp
		while(true)
		{
			if(!WorkerThread.Task) ;Still waiting for start
			{
				Sleep 10
				continue
			}
			WorkerThread.State := "Running"
			
			WorkerFunction := WorkerThread.Task.WorkerFunction
			
			result := %WorkerFunction%(WorkerThread, WorkerThread.Task.Parameters*)
			;if we are in stopped state, this thread was cancelled and no finish event is sent
			if(WorkerThread.State != "Stopped")
			{
				DetectHiddenWindows_Prev := A_DetectHiddenWindows
				DetectHiddenWindows, On
				Send_WM_COPYDATA(LSON({Type : 2, PID : WorkerThread.WorkerID, Result : result}), WorkerThread.MainHWND)
				if(!DetectHiddenWindows_Prev)
					DetectHiddenWindows, Off
			}
			if(WorkerThread.Task.ExitAfterTask)
				ExitApp
			
			WorkerThread.Task := ""
		}
	}
	if(!DetectHiddenWindows_Prev)
		DetectHiddenWindows, Off
	return
}
Send_WM_COPYDATA(ByRef StringToSend, hwnd)  ; ByRef saves a little memory in this case.
; This function sends the specified string to the specified window and returns the reply.
; The reply is 1 if the target window processed the message, or 0 if it ignored it.
{
    VarSetCapacity(CopyDataStruct, 4 + 2 * A_PtrSize, 0)  ; Set up the structure's memory area.
    ; First set the structure's cbData member to the size of the string, including its zero terminator:
    NumPut((StrLen(StringToSend) + 1) * (A_IsUnicode ? 2 : 1), CopyDataStruct, A_PtrSize)  ; OS requires that this be done.
    NumPut(&StringToSend, CopyDataStruct, 4 + A_PtrSize)  ; Set lpData to point to the string itself.
	return DllCall("SendMessage", "PTR", hwnd, "UInt", 0x4a, "PTR", 0, "PTR", &CopyDataStruct, "PTR")
}
#include <LSON>
#include <EventHandler>