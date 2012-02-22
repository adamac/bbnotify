import mx.rpc.events.ResultEvent;
import mx.rpc.events.FaultEvent;
import mx.rpc.AsyncToken;
import mx.collections.ItemResponder;
import mx.controls.Alert;
import mx.events.CloseEvent;
import mx.collections.ArrayCollection;
import com.ak33m.rpc.xmlrpc.*;
import mx.managers.PopUpManager;
import mx.core.IFlexDisplayObject;
import mx.events.PropertyChangeEvent;
import mx.events.ListEvent;
import flash.events.InvokeEvent;
import com.adobe.air.preferences.Preference;
import flash.system.Capabilities;
import flash.desktop.NativeProcess;
import mx.core.FlexGlobals;

[Bindable]
private var buildData:ArrayCollection = new ArrayCollection;

private var redImage:BitmapData;
private var yellowImage:BitmapData;
private var greenImage:BitmapData;
private var grayImage:BitmapData;
private var server:XMLRPCObject = new XMLRPCObject();
private var failureCount:int = 0;
private var commFailureCount:int = 0;
private var unknownCount:int = 0;
private var outstandingCount:int = 0;
private var REFRESH_TIME:int = 5 * 60 * 1000; // 5 minutes
private var refreshTimer:Timer;
private var DEFAULT_HOST_NAME:String = "";
private var HOST_XMLRPC_PATH:String = "/xmlrpc";
private var prefs:Preference = new Preference("settings.obj");

private var RED_IMAGE_URL:String = "app:/red_128.png";
private var YELLOW_IMAGE_URL:String = "app:/yellow_128.png";
private var GREEN_IMAGE_URL:String = "app:/green_128.png";
private var GRAY_IMAGE_URL:String = "app:/gray_128.png";

private var HOSTNAME_PREF:String = "hostName";

private var SUCCESS_STATUS:String = "success";
private var FAILURE_STATUS:String = "failure";
private var UNKNOWN_STATUS:String = "unknown";

private var UNKNOWN_STRING:String = "???";

private var lastStatus:String = UNKNOWN_STATUS;

/**
   * Initialize the application to the default values.
   * This method is called upon creationComplete from the Windowed Application
   */
public function initApplication():void {
    prefs.load();
    
    server.endpoint = prefs.getValue(HOSTNAME_PREF);
    if (!server.endpoint) {
        server.endpoint = DEFAULT_HOST_NAME;
    }    
    server.destination = HOST_XMLRPC_PATH;
           
    this.addEventListener(Event.CLOSING, closingApplication);

    var loader:Loader = new Loader();
    loader.contentLoaderInfo.addEventListener(Event.COMPLETE, iconLoadComplete);
    loader.load(new URLRequest(RED_IMAGE_URL));

    loader = new Loader();
    loader.contentLoaderInfo.addEventListener(Event.COMPLETE, iconLoadComplete);
    loader.load(new URLRequest(YELLOW_IMAGE_URL));

    loader = new Loader();
    loader.contentLoaderInfo.addEventListener(Event.COMPLETE, iconLoadComplete);
    loader.load(new URLRequest(GREEN_IMAGE_URL));

    loader = new Loader();
    loader.contentLoaderInfo.addEventListener(Event.COMPLETE, iconLoadComplete);
    loader.load(new URLRequest(GRAY_IMAGE_URL));
    
    if (NativeApplication.supportsSystemTrayIcon){
        setTooltip("Updating status");
        SystemTrayIcon(NativeApplication.nativeApplication.icon).addEventListener(MouseEvent.CLICK, show);
	    SystemTrayIcon(NativeApplication.nativeApplication.icon).menu = createSystrayRootMenu();
    } else if (NativeApplication.supportsDockIcon) {
        NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, show);
        DockIcon(NativeApplication.nativeApplication.icon).menu = createSystrayRootMenu();
        NativeApplication.nativeApplication.addEventListener(Event.EXITING, 
                function(e:Event):void {
                        var opened:Array = NativeApplication.nativeApplication.openedWindows;
                        for (var i:int = 0; i < opened.length; i ++) {
                                opened[i].close();
                        }
        });
    }
}

private function iconLoadComplete(event:Event):void
{
    var imageData:BitmapData = event.target.content.bitmapData;
    
    if (RED_IMAGE_URL == event.target.url) {
        redImage = imageData;
    } else if (YELLOW_IMAGE_URL == event.target.url) {
        yellowImage = imageData;
    } else if (GREEN_IMAGE_URL == event.target.url) {
        greenImage = imageData;
    } else if (GRAY_IMAGE_URL == event.target.url) {
        grayImage = imageData;
    }

    if (redImage && yellowImage && greenImage && grayImage) {
        completeInit();
    }
}

private function completeInit():void {
    hide();
    
    var screen:Screen = Screen.mainScreen;
    stage.nativeWindow.x = screen.visibleBounds.width - stage.nativeWindow.width;
    stage.nativeWindow.y = screen.visibleBounds.height - stage.nativeWindow.height;
    
    NativeApplication.nativeApplication.icon.bitmaps = [grayImage];
    //NativeApplication.nativeApplication.icon.addEventListener(Event.ACTIVATE, show);
    stage.nativeWindow.addEventListener(Event.CLOSING, closing);

    if (server.endpoint == DEFAULT_HOST_NAME) {
        show(null);
        showConfig();
    } else {
        refreshBuildState();
    }
}

private function setTooltip(text:String):void {
   if (NativeApplication.supportsSystemTrayIcon){
   	   SystemTrayIcon(NativeApplication.nativeApplication.icon).tooltip = text;
   }
}

private function refreshBuildState() : void {
    trace("Refreshing build state from " + server.endpoint + "...");
    setStatusText("Updating...");
    
    getAllBuilders();
}

private function getAllBuilders() : void {
    server.getAllBuilders().addResponder(new ItemResponder(getAllBuildersResult, 
function onFault (event : FaultEvent, token : AsyncToken = null) : void {
    setRefreshTimer();
    setStatusText(event.fault.faultString);
}));      
}

private function getAllBuildersResult(event : ResultEvent, token : AsyncToken = null) : void {
    failureCount = 0;
    commFailureCount = 0;
    unknownCount = 0;
    
	var builders:Array = event.result as Array;
    outstandingCount = builders.length;

    // Create a new builddata array and populate it only with new builders,
    // but retaining old status if it exists.
    var newData:ArrayCollection = new ArrayCollection();
    
	for (var i:int = 0; i < builders.length; i++) {
        var builderName:String = builders[i];
        var newItem:Object = null;

        for (var j:int = 0; j < buildData.length; j++) {
            if (buildData[j].name == builderName) {
                newItem = buildData[j];

                trace("Got recognized builder: " + builderName);
                break;
            }
        }
    
        if (!newItem) {
            trace("Got new builder: " + builderName);
            
            newItem = {name: builderName,
                       status: UNKNOWN_STRING, 
                       url: server.endpoint + "/builders/" + escape(builderName),
                       revision: UNKNOWN_STRING
                      };
        }

        newData.addItem(newItem);

        // We get the last 2 since there is a bug in the xmlrpc method implementation
        // that leaves one blank if there is a build in progress.
		server.getLastBuilds(builders[i], 2).addResponder(new ItemResponder(getLastBuildsResult, function onFault (event : FaultEvent, token : AsyncToken = null) : void {
            outstandingCount--;
            commFailureCount++;

            if (outstandingCount == 0) {
                setRefreshTimer();
            }
            setStatusText(event.fault.faultString);
}));
	}

    buildData = newData;
}

private function getLastBuildsResult(event : ResultEvent, token : AsyncToken = null) : void {
    outstandingCount--;
    
    if (!event.result || event.result.length < 1) {
        unknownCount++;
        return;
    }

    var values:Array = event.result[1];
    if (values == null) {
        // build in progress
        values = event.result[0];
    }
    var buildName:String = values[0];
    var buildNumber:String = values[1];
    // 2 - start time
    // 3 - end time
    // 4 - branch
    var revision:String = values[5];
    var buildStatus:String = values[6];

    trace(buildName + ": buildStatus = " + buildStatus);

    for (var i:int = 0; i < buildData.length; i++) {
        if (buildData[i].name == buildName) {
            if (buildData[i].status != buildStatus
                && buildData[i].status != UNKNOWN_STRING) {
                notifyBuildStatus(buildName, buildStatus);
            }
            buildData[i].status = buildStatus;
            buildData[i].revision = revision;
            break;
        }
    }

    if (FAILURE_STATUS == buildStatus) {
        failureCount++;
    }
    
    if (0 == outstandingCount) {
        if (commFailureCount) {
            setTooltip("Communication failure");
        } else if (failureCount) {        
            setStatusText(failureCount + " builds failed\n" + unknownCount + " builds unknown");
            
            NativeApplication.nativeApplication.icon.bitmaps = [redImage];
            updateStatus(FAILURE_STATUS);
        } else if (unknownCount) {
            setStatusText(unknownCount + " builds unknown");

            NativeApplication.nativeApplication.icon.bitmaps = [yellowImage];
            updateStatus(UNKNOWN_STATUS);
        } else {
            setStatusText("All builds successful.");

            NativeApplication.nativeApplication.icon.bitmaps = [greenImage];
            updateStatus(SUCCESS_STATUS);
        }

        setRefreshTimer();
    }

    dataGrid.dataProvider.refresh();
}

private function setRefreshTimer() : void {
    refreshTimer = new Timer(REFRESH_TIME, 1); // 10 seconds
    refreshTimer.addEventListener(TimerEvent.TIMER, runOnce);
    refreshTimer.start();
    
    function runOnce(event:TimerEvent):void {
	    refreshBuildState();
    }
}

private function closingApplication(evt:Event):void {

}

private function closing(evt:Event):void {
    evt.preventDefault();

    hide();
}

private function createSystrayRootMenu():NativeMenu{
    //Add the menuitems with the corresponding actions 
    var menu:NativeMenu = new NativeMenu();
    var openNativeMenuItem:NativeMenuItem = new NativeMenuItem("Open");
    var exitNativeMenuItem:NativeMenuItem = new NativeMenuItem("Exit");
    
    openNativeMenuItem.addEventListener(Event.SELECT, show);
    exitNativeMenuItem.addEventListener(Event.SELECT, closeApp);
    
    //Add the menuitems to the menu
    if (NativeApplication.supportsSystemTrayIcon) {
        menu.addItem(openNativeMenuItem);
        menu.addItem(new NativeMenuItem("",true));
    }
    
    menu.addItem(exitNativeMenuItem);
    
    return menu;
}

public function showConfig():void {
    var configWindow:ConfigForm =
        ConfigForm(PopUpManager.createPopUp(this, ConfigForm, true));
    configWindow.serverName = server.endpoint;
    configWindow.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE, saveConfig);
}

private function saveConfig(event:Event):void {
    var configWindow:ConfigForm = ConfigForm(event.target);
    trace(configWindow.serverName);
    if (configWindow.serverName) {
        server.endpoint = configWindow.serverName;
        
        prefs.setValue(HOSTNAME_PREF, configWindow.serverName);
        prefs.save();

        refreshBuildState();
    }
}

private function handleDataGridClickEvent(evt:ListEvent):void {
    var u:URLRequest = new URLRequest(evt.itemRenderer.data.url);
    navigateToURL(u);
}

public function dataGridRowColor(item:Object, rowIndex:int, dataIndex:int, color:uint):uint {
    if (item.status == FAILURE_STATUS) {
        return 0xff0000;
    } else if (item.status == SUCCESS_STATUS) {
        return 0x00ff00;
    } else {
        return 0xC0C0C0;
    }
}

public function hide():void {
    stage.nativeWindow.visible = false;
}

public function show(evt:Event):void {
    stage.nativeWindow.visible = true;
    stage.nativeWindow.orderToFront();
}

private function closeApp(evt:Event):void {
    stage.nativeWindow.close();
}

private function updateStatus(status:String):void {
    if (status == lastStatus) {
        return;
    }
    

    notifyStatus(status);
    lastStatus = status;
}

private function notifyBuildStatus(build:String, status:String):void {
    var file:File;
    if (status == SUCCESS_STATUS) {
        file = new File(GREEN_IMAGE_URL);
         growlNotify(build + " succeeded", file.nativePath);
    } else if (status == FAILURE_STATUS) {
        file = new File(RED_IMAGE_URL);
         growlNotify(build + " failed", file.nativePath);
    }
}

private function notifyStatus(status:String):void {
    var file:File;
    if (status == SUCCESS_STATUS) {
        file = new File(GREEN_IMAGE_URL);
        trace(file.nativePath);
        growlNotify("All builds succeeded", file.nativePath);
    } else if (status == FAILURE_STATUS) {
        file = new File(RED_IMAGE_URL);
        trace(file.nativePath);
        growlNotify("One or more builds failed", file.nativePath);
    }
}

private function setStatusText(status:String):void {
    setTooltip(status);
    FlexGlobals.topLevelApplication.status = status;
}

private function growlNotify(msg:String, iconPath:String):void {
    if (Capabilities.os.indexOf("Mac") < 0 || !NativeProcess.isSupported) {
        return;
    }
    
    var file:File = new File();
    file.nativePath = "/usr/local/bin/growlnotify";

    var nativeProcessStartupInfo:NativeProcessStartupInfo = new NativeProcessStartupInfo();
    var processArgs:Vector.<String> = new Vector.<String>();
    processArgs[0] = "-n";
    processArgs[1] = "Buildbot";
    processArgs[2] = "-p";
    processArgs[3] = "0";
    processArgs[4] = "-t";
    processArgs[5] = "Build status";
    processArgs[6] = "-m";
    processArgs[7] = msg;
    if (iconPath != "") {
        processArgs[8] = "--image";
        processArgs[9] = iconPath;
    }

nativeProcessStartupInfo.arguments = processArgs;
    nativeProcessStartupInfo.executable = file;

    var process:NativeProcess = new NativeProcess();
    process.start(nativeProcessStartupInfo);
}