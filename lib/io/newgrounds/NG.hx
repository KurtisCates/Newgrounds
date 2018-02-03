package io.newgrounds;
#if ng_lite
typedef NG = NGLite;
#else
import io.newgrounds.objects.Error;
import io.newgrounds.objects.events.Result.SessionResult;
import io.newgrounds.objects.events.Result.MedalListResult;
import io.newgrounds.objects.events.Response;
import io.newgrounds.objects.User;
import haxe.ds.IntMap;

//TODO: Remove openfl dependancies 
import openfl.events.TimerEvent;
import openfl.Lib;
import openfl.net.URLRequest;
import openfl.utils.Timer;

import io.newgrounds.objects.Medal;
import io.newgrounds.objects.Session;
import io.newgrounds.objects.ScoreBoard;

/**
 * The Newgrounds API for Haxe.
 * Contains many things ripped from MSGhero
 *   - https://github.com/MSGhero/NG.hx
 * @author GeoKureli
 */
class NG extends NGLite {
	
	static public var core(default, null):NG;
	
	
	/** The logged in user */
	public var user(get, never):User;
	public function get_user():User {
		
		if (_session == null)
			return null;
		
		return _session.user;
	}
	public var medals(default, null):IntMap<Medal>;
	
	var _waitingForLogin:Bool;
	var _loginCancelled:Bool;
	
	var _session:Session;
	var _scoreBoards:IntMap<ScoreBoard>;
	
	/** 
	 * Iniitializes the API, call before utilizing any other component
	 * @param appId     The unique ID of your app as found in the 'API Tools' tab of your Newgrounds.com project.
	 * @param sessionId A unique session id used to identify the active user.
	**/
	public function new(appId:String = "test") {
		super(appId);
		
		_session = new Session(this);
	}
	
	/**
	 * Creates NG.core, the heart and soul of the API. This is not the only way to create an instance,
	 * nor is NG a forced singleton, but it's the only way to set the static NG.core.
	**/
	static public function createCore(appId:String = "test"):Void {
		
		core = new NG(appId);
	}
	
	// -------------------------------------------------------------------------------------------
	//                                         APP
	// -------------------------------------------------------------------------------------------
	
	public function requestLogin
	( onLogin :Void->Void = null
	, onFail  :Error->Void = null
	, onCancel:Void->Void = null
	):Void {
		
		if (_waitingForLogin) {
			
			logError("cannot request another login until");
			return;
		}
		
		_waitingForLogin = true;
		_loginCancelled = false;
		
		var call = calls.app.startSession(true)
			.addDataHandler(
			function (response:Response<SessionResult>):Void {
				
				if (!response.success || !response.result.success) {
					
					if (onFail != null)
						onFail(!response.success ? response.error : response.result.error);
					
					endLoginAndCall(null);
					return;
				}
				
				_session.parse(response.result.data.session);
				sessionId = _session.id;
				
				logVerbose('session started - status: ${_session.status}');
				
				if (_session.status == SessionStatus.REQUEST_LOGIN) {
					
					logVerbose('loading passport: ${_session.passportUrl}');
					// TODO: Remove openFL dependancy
					Lib.getURL(new URLRequest(_session.passportUrl));
					checkSession(null, onLogin, onCancel);
				}
			}
		);
		
		if (onFail != null)
			call.addErrorHandler(onFail);
		
		call.send();
	}
	
	function checkSession(response:Response<SessionResult>, onLogin:Void->Void, onCancel:Void->Void):Void {
		
		if (response != null) {
			
			if (!response.success || !response.result.success) {
				
				log("login cancelled via passport");
				
				endLoginAndCall(onCancel);
				return;
			}
			
			_session.parse(response.result.data.session);
		}
		
		if (_session.status == SessionStatus.USER_LOADED) {
			
			endLoginAndCall(onLogin);
			
		} else if (_session.status == SessionStatus.REQUEST_LOGIN){
			
			var call = calls.app.checkSession()
				.addDataHandler(checkSession.bind(_, onLogin, onCancel));
			
			// Wait 3 seconds and try again
			timer(3.0,
				function():Void {
					
					// Check if cancelLoginRequest was called
					if (!_loginCancelled)
						call.send();
					else {
						
						log("login cancelled via cancelLoginRequest");
						endLoginAndCall(onCancel);
					}
				}
			);
			
		} else
			// The user cancelled the passport
			endLoginAndCall(onCancel);
	}
	
	public function cancelLoginRequest():Void {
		
		if (_waitingForLogin)
			_loginCancelled = true;
	}
	
	function endLoginAndCall(callback:Void->Void):Void {
		
		_waitingForLogin = false;
		_loginCancelled = false;
		
		if (callback != null)
			callback();
	}
	
	public function logOut(onLogOut:Void->Void):Void {
		
		var call = calls.app.endSession()
			.addSuccessHandler(onLogOutSuccessful);
		
		if (onLogOut != null)
			call.addSuccessHandler(onLogOut);
		
		call.send();
	}
	
	function onLogOutSuccessful():Void {
		
		_session.expire();
	}
	
	// -------------------------------------------------------------------------------------------
	//                                       MEDALS
	// -------------------------------------------------------------------------------------------
	
	public function requestMedals(onSuccess:Void->Void = null, onFail:Error->Void = null):Void {
		
		var call = calls.medal.getList()
			.addDataHandler(onMedalsReceived);
		
		if (onSuccess != null)
			call.addSuccessHandler(onSuccess);
		
		if (onFail != null)
			call.addErrorHandler(onFail);
		
		call.send();
	}
	
	function onMedalsReceived(response:Response<MedalListResult>):Void {
		
		if (!response.success || !response.result.success)
			return;
		
		if (medals == null) {
			
			medals = new IntMap<Medal>();
			
			for (medalData in response.result.data.medals) {
				
				var medal = new Medal(this, medalData);
				medals.set(medal.id, medal);
			}
		} else {
			
			for (medalData in response.result.data.medals) {
				
				medals.get(medalData.id).parse(medalData);
			}
		}
		
		logVerbose('${response.result.data.medals.length} Medals received');
	}
	
	// -------------------------------------------------------------------------------------------
	//                                       HELPERS
	// -------------------------------------------------------------------------------------------
	
	function timer(delay:Float, callback:Void->Void):Void {
		//TODO: remove openFL dependancy
		
		var timer = new Timer(delay * 1000.0, 1);
		
		function func(e:TimerEvent):Void {
			
			timer.removeEventListener(TimerEvent.TIMER_COMPLETE, func);
			callback();
		}
		
		timer.addEventListener(TimerEvent.TIMER_COMPLETE, func);
		timer.start();
	}
}
#end