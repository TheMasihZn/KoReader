# UI ledger

Totals: covered: 1, new: 6, original: 204, ported: 15, restyled: 1

What has and has not been changed in KOReader for the new home-screen UI.
Nothing in KOReader is deleted: every row still exists in the code.

Statuses:
- **original**: untouched, works as in KOReader
- **covered**: still there, but Overview is drawn on top of it
- **restyled**: same feature, new look
- **ported**: the feature is reachable from the new UI
- **new**: added for the new UI

Regenerate with `python3 tools/uiLedger.py` (keeps the statuses below).

## Screens: file manager (the page under Overview)

| item | status | note |
|---|---|---|
| `frontend/apps/filemanager/filemanager.lua` | covered | Overview is shown on top; search "KOReader files" to reach it |
| `frontend/apps/filemanager/filemanagerbookinfo.lua` | original |  |
| `frontend/apps/filemanager/filemanagercollection.lua` | original |  |
| `frontend/apps/filemanager/filemanagerconverter.lua` | original |  |
| `frontend/apps/filemanager/filemanagerfilesearcher.lua` | original |  |
| `frontend/apps/filemanager/filemanagerhistory.lua` | original |  |
| `frontend/apps/filemanager/filemanagermenu.lua` | original |  |
| `frontend/apps/filemanager/filemanagersetdefaults.lua` | original |  |
| `frontend/apps/filemanager/filemanagershortcuts.lua` | original |  |
| `frontend/apps/filemanager/filemanagerutil.lua` | original |  |

## Layers: reader (open book)

| item | status | note |
|---|---|---|
| `frontend/apps/reader/readerui.lua` | original |  |
| `frontend/apps/reader/modules/readeractivityindicator.lua` | original |  |
| `frontend/apps/reader/modules/readerannotation.lua` | original |  |
| `frontend/apps/reader/modules/readerback.lua` | original |  |
| `frontend/apps/reader/modules/readerbookmark.lua` | original |  |
| `frontend/apps/reader/modules/readerconfig.lua` | original |  |
| `frontend/apps/reader/modules/readercoptlistener.lua` | original |  |
| `frontend/apps/reader/modules/readercropping.lua` | original |  |
| `frontend/apps/reader/modules/readerdevicestatus.lua` | original |  |
| `frontend/apps/reader/modules/readerdictionary.lua` | original |  |
| `frontend/apps/reader/modules/readerdogear.lua` | original |  |
| `frontend/apps/reader/modules/readerflipping.lua` | original |  |
| `frontend/apps/reader/modules/readerfont.lua` | original |  |
| `frontend/apps/reader/modules/readerfooter.lua` | original |  |
| `frontend/apps/reader/modules/readergoto.lua` | original |  |
| `frontend/apps/reader/modules/readerhandmade.lua` | original |  |
| `frontend/apps/reader/modules/readerhighlight.lua` | original |  |
| `frontend/apps/reader/modules/readerhinting.lua` | original |  |
| `frontend/apps/reader/modules/readerkeyselection.lua` | original |  |
| `frontend/apps/reader/modules/readerkoptlistener.lua` | original |  |
| `frontend/apps/reader/modules/readerlink.lua` | original |  |
| `frontend/apps/reader/modules/readermenu.lua` | original |  |
| `frontend/apps/reader/modules/readerpagemap.lua` | original |  |
| `frontend/apps/reader/modules/readerpaging.lua` | original |  |
| `frontend/apps/reader/modules/readerpanning.lua` | original |  |
| `frontend/apps/reader/modules/readerrolling.lua` | original |  |
| `frontend/apps/reader/modules/readerscrolling.lua` | original |  |
| `frontend/apps/reader/modules/readersearch.lua` | original |  |
| `frontend/apps/reader/modules/readerstatus.lua` | original |  |
| `frontend/apps/reader/modules/readerstyletweak.lua` | original |  |
| `frontend/apps/reader/modules/readerthumbnail.lua` | original |  |
| `frontend/apps/reader/modules/readertoc.lua` | original |  |
| `frontend/apps/reader/modules/readertypeset.lua` | original |  |
| `frontend/apps/reader/modules/readertypography.lua` | original |  |
| `frontend/apps/reader/modules/readeruserhyph.lua` | original |  |
| `frontend/apps/reader/modules/readerview.lua` | original |  |
| `frontend/apps/reader/modules/readerwikipedia.lua` | original |  |
| `frontend/apps/reader/modules/readerzooming.lua` | original |  |

## Widgets: shared building blocks

| item | status | note |
|---|---|---|
| `frontend/ui/widget/bboxwidget.lua` | original |  |
| `frontend/ui/widget/booklist.lua` | original |  |
| `frontend/ui/widget/bookmapwidget.lua` | original |  |
| `frontend/ui/widget/bookmarkbrowser.lua` | original |  |
| `frontend/ui/widget/bookmetadataarchive.lua` | original |  |
| `frontend/ui/widget/bookstatuswidget.lua` | original |  |
| `frontend/ui/widget/button.lua` | original |  |
| `frontend/ui/widget/buttondialog.lua` | original |  |
| `frontend/ui/widget/buttondialogtitle.lua` | original |  |
| `frontend/ui/widget/buttonprogresswidget.lua` | original |  |
| `frontend/ui/widget/buttonselector.lua` | original |  |
| `frontend/ui/widget/buttontable.lua` | original |  |
| `frontend/ui/widget/checkbutton.lua` | original |  |
| `frontend/ui/widget/checkmark.lua` | original |  |
| `frontend/ui/widget/configdialog.lua` | original |  |
| `frontend/ui/widget/confirmbox.lua` | original |  |
| `frontend/ui/widget/datetimewidget.lua` | original |  |
| `frontend/ui/widget/dictquicklookup.lua` | original |  |
| `frontend/ui/widget/doublespinwidget.lua` | original |  |
| `frontend/ui/widget/eventlistener.lua` | original |  |
| `frontend/ui/widget/filechooser.lua` | original |  |
| `frontend/ui/widget/fixedtextwidget.lua` | original |  |
| `frontend/ui/widget/focusmanager.lua` | original |  |
| `frontend/ui/widget/fontchooser.lua` | original |  |
| `frontend/ui/widget/footnotewidget.lua` | original |  |
| `frontend/ui/widget/frontlightwidget.lua` | original |  |
| `frontend/ui/widget/horizontalgroup.lua` | original |  |
| `frontend/ui/widget/horizontalscrollbar.lua` | original |  |
| `frontend/ui/widget/horizontalspan.lua` | original |  |
| `frontend/ui/widget/htmlboxwidget.lua` | original |  |
| `frontend/ui/widget/iconbutton.lua` | original |  |
| `frontend/ui/widget/iconwidget.lua` | original |  |
| `frontend/ui/widget/imageviewer.lua` | original |  |
| `frontend/ui/widget/imagewidget.lua` | original |  |
| `frontend/ui/widget/infomessage.lua` | original |  |
| `frontend/ui/widget/inputdialog.lua` | original |  |
| `frontend/ui/widget/inputtext.lua` | restyled | used as Overview's search field; long-press off there only |
| `frontend/ui/widget/keyboardlayoutdialog.lua` | original |  |
| `frontend/ui/widget/keyvaluepage.lua` | original |  |
| `frontend/ui/widget/linewidget.lua` | original |  |
| `frontend/ui/widget/linkbox.lua` | original |  |
| `frontend/ui/widget/listview.lua` | original |  |
| `frontend/ui/widget/menu.lua` | original |  |
| `frontend/ui/widget/multiconfirmbox.lua` | original |  |
| `frontend/ui/widget/multiinputdialog.lua` | original |  |
| `frontend/ui/widget/naturallightwidget.lua` | original |  |
| `frontend/ui/widget/networksetting.lua` | original |  |
| `frontend/ui/widget/notification.lua` | original |  |
| `frontend/ui/widget/numberpickerwidget.lua` | original |  |
| `frontend/ui/widget/openwithdialog.lua` | original |  |
| `frontend/ui/widget/overlapgroup.lua` | original |  |
| `frontend/ui/widget/pagebrowserwidget.lua` | original |  |
| `frontend/ui/widget/pathchooser.lua` | original |  |
| `frontend/ui/widget/physicalkeyboard.lua` | original |  |
| `frontend/ui/widget/progressbardialog.lua` | original |  |
| `frontend/ui/widget/progresswidget.lua` | original |  |
| `frontend/ui/widget/qrmessage.lua` | original |  |
| `frontend/ui/widget/qrwidget.lua` | original |  |
| `frontend/ui/widget/radiobuttontable.lua` | original |  |
| `frontend/ui/widget/radiobuttonwidget.lua` | original |  |
| `frontend/ui/widget/radiomark.lua` | original |  |
| `frontend/ui/widget/rectspan.lua` | original |  |
| `frontend/ui/widget/screensaverlockwidget.lua` | original |  |
| `frontend/ui/widget/screensaverwidget.lua` | original |  |
| `frontend/ui/widget/screenshoter.lua` | original |  |
| `frontend/ui/widget/scrollhtmlwidget.lua` | original |  |
| `frontend/ui/widget/scrolltextwidget.lua` | original |  |
| `frontend/ui/widget/skimtowidget.lua` | original |  |
| `frontend/ui/widget/sortwidget.lua` | original |  |
| `frontend/ui/widget/spinwidget.lua` | original |  |
| `frontend/ui/widget/textboxwidget.lua` | original |  |
| `frontend/ui/widget/textviewer.lua` | original |  |
| `frontend/ui/widget/textwidget.lua` | original |  |
| `frontend/ui/widget/titlebar.lua` | original |  |
| `frontend/ui/widget/toggleswitch.lua` | original |  |
| `frontend/ui/widget/touchmenu.lua` | original |  |
| `frontend/ui/widget/trapwidget.lua` | original |  |
| `frontend/ui/widget/verticalgroup.lua` | original |  |
| `frontend/ui/widget/verticalscrollbar.lua` | original |  |
| `frontend/ui/widget/verticalspan.lua` | original |  |
| `frontend/ui/widget/virtualkeyboard.lua` | original |  |
| `frontend/ui/widget/widget.lua` | original |  |

## Apps: KOReader plugins built into this APK

| item | status | note |
|---|---|---|
| `plugins/SSH.koplugin` | ported | searchable |
| `plugins/archiveviewer.koplugin` | original |  |
| `plugins/autodim.koplugin` | original |  |
| `plugins/autostandby.koplugin` | original |  |
| `plugins/autosuspend.koplugin` | original |  |
| `plugins/autoturn.koplugin` | original |  |
| `plugins/autowarmth.koplugin` | original |  |
| `plugins/batterystat.koplugin` | ported | searchable |
| `plugins/bookshortcuts.koplugin` | original |  |
| `plugins/calibre.koplugin` | original |  |
| `plugins/cloudstorage.koplugin` | ported | searchable |
| `plugins/coverbrowser.koplugin` | original |  |
| `plugins/coverimage.koplugin` | original |  |
| `plugins/docsettingtweak.koplugin` | original |  |
| `plugins/exporter.koplugin` | original |  |
| `plugins/externalkeyboard.koplugin` | original |  |
| `plugins/gestures.koplugin` | original |  |
| `plugins/hello.koplugin` | original |  |
| `plugins/hotkeys.koplugin` | original |  |
| `plugins/httpinspector.koplugin` | original |  |
| `plugins/japanese.koplugin` | original |  |
| `plugins/keepalive.koplugin` | original |  |
| `plugins/kosync.koplugin` | original |  |
| `plugins/movetoarchive.koplugin` | original |  |
| `plugins/newsdownloader.koplugin` | original |  |
| `plugins/opds.koplugin` | ported | searchable |
| `plugins/overview.koplugin` | new | the home screen itself |
| `plugins/perceptionexpander.koplugin` | original |  |
| `plugins/profiles.koplugin` | original |  |
| `plugins/qrclipboard.koplugin` | ported | searchable |
| `plugins/readtimer.koplugin` | ported | timer and alarm searchable |
| `plugins/statistics.koplugin` | ported | reading calendar searchable |
| `plugins/systemstat.koplugin` | ported | searchable |
| `plugins/terminal.koplugin` | ported | searchable from Overview |
| `plugins/texteditor.koplugin` | ported | searchable (last edited file) |
| `plugins/timesync.koplugin` | original |  |
| `plugins/vocabbuilder.koplugin` | ported | searchable |
| `plugins/wallabag.koplugin` | ported | searchable |

## Android layer (the APK around the Lua shell)

| item | status | note |
|---|---|---|
| `platform/android/luajit-launcher/app/src/main/AndroidManifest.xml` | ported | added: Home-screen intent, 2 services, contacts/SMS permissions; nothing removed |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/ApkUpdater.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/Assets.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/CrashReportActivity.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/EventReceiver.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/LuaInterface.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/MainActivity.kt` | ported | added overview* methods for Lua; nothing removed |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/MainApp.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/TestActivity.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/Timeout.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/Device.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/DeviceInfo.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/EPDFactory.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/EPDInterface.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/Ioctl.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/LightsFactory.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/LightsInterface.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/CremaEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/LenovoSmartPaperEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/NGL4EPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/NookEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/NookEmperorEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/OldTolinoEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/OnyxEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/RK3026EPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/RK3368EPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/RK3566EPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/SunxiEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/TolinoEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/freescale/NTXEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/qualcomm/QualcommEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/rockchip/RK30xxEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/rockchip/RK33xxEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/epd/rockchip/RK35xxEPDController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/BoyueS62RootController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/GenericController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/LenovoSmartPaperLightsController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/NookGL4plusController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/OnyxAdbLightsController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/OnyxC67Controller.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/OnyxColorController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/OnyxPalma2ProController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/OnyxSdkLightsController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/OnyxWarmthController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/TolinoB300Controller.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/TolinoNtxController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/TolinoNtxNoWarmthController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/device/lights/TolinoRootController.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/dialog/LightDialog.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/dialog/ToolTip.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/extensions/ActivityExtensions.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/extensions/FileExtensions.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/extensions/UriExtensions.kt` | original |  |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/overview/ChatNavigator.kt` | new | Overview |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/overview/MessageListener.kt` | new | Overview |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/overview/Overview.kt` | new | Overview |
| `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/overview/OverviewStore.kt` | new | Overview |
| `platform/android/luajit-launcher/app/src/main/res/values/strings.xml` | ported | added the accessibility description |
| `platform/android/luajit-launcher/app/src/main/res/xml/overview_chat_navigator.xml` | new | accessibility service config |
