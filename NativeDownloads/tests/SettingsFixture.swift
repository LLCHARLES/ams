import UIKit
import SwiftUI
import Darwin

// A failed fixture is a normal exit; the runner reads the reason from its container.
private func fail(_ message: String, file: StaticString = #fileID, line: UInt = #line) -> Never {
 let failure="FAIL: \(file):\(line): \(message)"
 let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("result.log")
 try? failure.write(to:url,atomically:true,encoding:.utf8)
 SAPFixtureFail(failure)
 exit(1)
}
private func check(_ condition: Bool, _ message: String = "check failed", file: StaticString = #fileID, line: UInt = #line) {
 if !condition { fail(message,file:file,line:line) }
}

// Compare UI output with the checked source tables, independently of SAPL/SGL.
private func expectedText(_ english: String) -> String {
 guard Locale.preferredLanguages.first?.hasPrefix("ko") == true else { return english }
 let bundle = Bundle(path: Bundle.main.path(forResource: "Retrine", ofType: "bundle")!)!
 let en = NSDictionary(contentsOfFile: bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en")!) as! [String: String]
 let ko = NSDictionary(contentsOfFile: bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "ko")!) as! [String: String]
 let translations = Set(en.compactMap { key, value in value == english ? ko[key] : nil })
 check(translations.count == 1, "missing or ambiguous expected translation: " + english)
 return translations.first!
}

private struct LabelRow: View {
 let title: String
 let subtitle: String?
 let icon: String
 let color: Color
 var body: some View {
  HStack(spacing:14) {
   Image(systemName:icon).font(.system(size:15,weight:.semibold)).foregroundStyle(.white)
    .frame(width:30,height:30).background(RoundedRectangle(cornerRadius:8).fill(color))
   VStack(alignment:.leading,spacing:2){Text(title).foregroundStyle(.primary);if let subtitle{Text(subtitle).font(.footnote).foregroundStyle(.secondary)}}
   Spacer(minLength:8)
  }.padding(.vertical,2)
 }
}
private struct SettingsRoot: View {
 @State var logging=false
 var body: some View {
  List {
   Section {Text("Developer’s Note...").foregroundStyle(.green)}
   Section {LabelRow(title:"Поддержать проект",subtitle:"Ваш вклад помогает обновлять этот твик и…",icon:"cup.and.saucer.fill",color:.red)}
   Section(header:Text("Устранение неполадок"),footer:Text("Включите ведение журнала, затем экспортируйте или очистите журнал.")) {
    Toggle("Журнал отладки",isOn:$logging)
    LabelRow(title:"Export Debug Log",subtitle:nil,icon:"square.and.arrow.up",color:.blue)
    LabelRow(title:"Clear Debug Log",subtitle:nil,icon:"trash.fill",color:.gray)
   }
   Section(header:Text("Сброс"),footer:Text("Оба действия закроют приложение по завершении.")) {
    LabelRow(title:"Очистить данные",subtitle:"Очищает кэши",icon:"arrow.counterclockwise",color:.orange)
    LabelRow(title:"Full Reset",subtitle:"Стирает всё и выполняет выход из аккаунта",icon:"exclamationmark.triangle.fill",color:.red)
   }
   Spacer().frame(height:40).listRowBackground(Color.clear).listRowSeparator(.hidden)
  }.listStyle(.insetGrouped).tint(.green).preferredColorScheme(.dark)
 }
}
@objc(SAPFixtureEeveeSettingsViewController)
class FixtureSettings: UIViewController {
 override func viewDidLoad(){
  super.viewDidLoad();title="EeveeSpotify"
  let child=UIHostingController(rootView:AnyView(SettingsRoot()));addChild(child)
  child.view.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(child.view);child.didMove(toParent:self)
  NSLayoutConstraint.activate([child.view.topAnchor.constraint(equalTo:view.topAnchor),child.view.bottomAnchor.constraint(equalTo:view.bottomAnchor),child.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),child.view.trailingAnchor.constraint(equalTo:view.trailingAnchor)])
 }
}
// Mirrors the native SPNavigationController page assertion, including the
// module-qualified Objective-C protocol in Spotify 9.1.88.
class FixtureNavigation:UINavigationController {
 override func pushViewController(_ page:UIViewController,animated:Bool) {
  if ["SAPDownloadsSettings","SAPDetailsSettings"].contains(NSStringFromClass(type(of:page))) {
   for name in ["SPTPageController","_TtP19Tome_PageAttributes17SPTPageController_"] {
    guard let proto=NSProtocolFromString(name) else {fail("missing protocol fixture")}
    check(page.conforms(to:proto),"native SPTPageController assertion: "+name)
   }
  }
  super.pushViewController(page,animated:animated)
 }
}
class ChromeHost:UIViewController {
 let nav:UINavigationController
 let mini=(NSClassFromString("_TtC18NowPlaying_BarImpl27NowPlayingBarViewController") as! UIViewController.Type).init()
 let bottom=UILabel()
 init(_ nav:UINavigationController){self.nav=nav;super.init(nibName:nil,bundle:nil)}
 required init?(coder:NSCoder){return nil}
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .black
  addChild(nav);view.addSubview(nav.view);nav.didMove(toParent:self)
  bottom.text="Главная             Поиск             Медиатека";bottom.textColor = .lightGray;bottom.backgroundColor = .black;bottom.textAlignment = .center;view.addSubview(bottom)
  addChild(mini);view.addSubview(mini.view);mini.didMove(toParent:self)
 }
 override func viewDidLayoutSubviews(){
  super.viewDidLayoutSubviews();nav.view.frame=view.bounds
  mini.view.frame=CGRect(x:8,y:view.bounds.height-146,width:view.bounds.width-16,height:56)
  bottom.frame=CGRect(x:0,y:view.bounds.height-90,width:view.bounds.width,height:90)
 }
}
@main class AppDelegate:UIResponder,UIApplicationDelegate {
 func application(_ application:UIApplication,didFinishLaunchingWithOptions opts:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {SAPInstallDownloadSettings();return true}
}
@objc(SAPFixtureSceneDelegate) class SceneDelegate:UIResponder,UIWindowSceneDelegate {
 var window:UIWindow?
 func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {
  guard let windowScene=scene as? UIWindowScene else{return}
  let window=UIWindow(windowScene:windowScene);self.window=window
  let root=FixtureSettings();root.title="EeveeSpotify";let nav=FixtureNavigation(rootViewController:root)
  let chrome=ChromeHost(nav);window.rootViewController=chrome;window.overrideUserInterfaceStyle = .dark;window.makeKeyAndVisible()
  DispatchQueue.main.asyncAfter(deadline:.now()+1.5){
   let lists=root.view.subviews.flatMap{self.descendants($0)}.compactMap{$0 as? UIScrollView}
   guard let list=lists.first(where:{$0 is UICollectionView}),let entry=lists.first(where:{$0.accessibilityIdentifier=="SpotifyTrackDownloadsSection"}) as? UITableView else {self.write("NO_ENTRY");return}
   list.setContentOffset(CGPoint(x:0,y:max(-list.adjustedContentInset.top,list.contentSize.height-list.bounds.height+list.adjustedContentInset.bottom)),animated:false)
   DispatchQueue.main.asyncAfter(deadline:.now()+0.7){
    self.capture("root-settings")
    let cellRect=entry.convert(entry.rectForRow(at:IndexPath(row:0,section:0)),to:window)
    let miniTop=chrome.mini.view.convert(chrome.mini.view.bounds,to:window).minY
    self.write("root last row bottom=\(cellRect.maxY); mini top=\(miniTop)")
    check(cellRect.maxY<=miniTop-10,"root row under mini-player")
    if let cv=list as? UICollectionView, let footer=cv.collectionViewLayout.layoutAttributesForSupplementaryView(ofKind:UICollectionView.elementKindSectionFooter,at:IndexPath(item:0,section:3)) {
     let gap=entry.frame.minY-footer.frame.maxY;self.write("entry-to-reset-footer gap=\(gap)");check(abs(gap)<1,"entry separated by spacer")
    }
    let rect=entry.convert(entry.bounds,to:window)
    self.write("entry frame=\(rect); contentSize=\(list.contentSize); inset=\(list.contentInset); roots=\(root.children.count)")
    entry.delegate?.tableView?(entry,didSelectRowAt:IndexPath(row:0,section:0))
    DispatchQueue.main.asyncAfter(deadline:.now()+0.8){
     self.capture("downloads-top")
     guard let page=nav.topViewController as? UITableViewController else{return}
     check(page.tableView.numberOfSections==5)
     check(page.tableView.numberOfRows(inSection:1)==3,"quota/license/device rows missing")
     let modeCell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:0,section:1))
     check((modeCell.contentConfiguration as? UIListContentConfiguration)?.text==expectedText("Configured request mode"),"selected mode must not be presented as verified execution")
     check(!modeCell.isUserInteractionEnabled,"mode 0 must be read-only")
     let modeFooter=page.tableView.dataSource!.tableView?(page.tableView,titleForFooterInSection:1) ?? ""
     check(modeFooter.contains(expectedText("Only restoring a confirmed mode 1 to mode 0 is allowed. A saved preference alone is not confirmation.")))
     let korean=Locale.preferredLanguages.first?.hasPrefix("ko") == true
     check(!modeFooter.lowercased().contains("recovery"))
     let refreshCell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:1,section:1))
     check((refreshCell.contentConfiguration as? UIListContentConfiguration)?.text==expectedText("Refresh quotas and licenses"))
     for (row,title) in [(2,"Offline devices")] {
      let cell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:row,section:1))
      check((cell.contentConfiguration as? UIListContentConfiguration)?.text==expectedText(title))
     }
     check(page.title==(korean ? "Pixie 다운로드 관리자" : "Pixie Download Manager"),"Pixie must follow the app language")
     for section in 0..<page.tableView.numberOfSections {for row in 0..<page.tableView.numberOfRows(inSection:section) {
      let cell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:row,section:section))
      if let content=cell.contentConfiguration as? UIListContentConfiguration {
       check(!(content.text ?? "").contains("WAV"),"WAV row still present")
       check(!(content.text ?? "").contains("Заглушить") && !(content.text ?? "").contains("Mute audio"),"mute row still present")
       if content.text==expectedText("Send log"){check(section==3 && row==2,"duplicate Send log row")}
      }
     }}
     // Cancel is inserted before the auto-like switch while a download is active.
     let autoLikeTitle=expectedText("Add single-track downloads to Liked Songs")
     func autoLikeCell()->UITableViewCell{page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:page.tableView.numberOfRows(inSection:0)-1,section:0))}
     check(page.tableView.numberOfRows(inSection:0)==3,"idle download section must have three rows")
     let idleAutoLike=autoLikeCell()
     let autoLikeContent=idleAutoLike.contentConfiguration as? UIListContentConfiguration
     check(autoLikeContent?.text==autoLikeTitle,"auto-like title must be localized")
     check(autoLikeContent?.textProperties.numberOfLines==0,"auto-like label must wrap at accessibility sizes")
     check(idleAutoLike.accessibilityLabel==autoLikeTitle,"auto-like row needs a localized VoiceOver label")
     check(idleAutoLike.selectionStyle == .none,"the auto-like switch row is not an action")
     guard let autoLikeSwitch=idleAutoLike.accessoryView as? UISwitch else {fail("auto-like switch missing")}
     check(!autoLikeSwitch.isOn && !SAPFixtureAutoLikeEnabled(),"auto-like downloads must default OFF")
     let beforeToggle=SAPFixtureActionCount()
     autoLikeSwitch.isOn=true;autoLikeSwitch.sendActions(for:.valueChanged)
     check(SAPFixtureAutoLikeEnabled(),"toggling must persist the preference")
     check((autoLikeCell().accessoryView as? UISwitch)?.isOn==true,"switch must render the stored preference")
     check(SAPFixtureActionCount()==beforeToggle,"toggling must not start a download")
     page.tableView.delegate?.tableView?(page.tableView,didSelectRowAt:IndexPath(row:2,section:0))
     check(SAPFixtureActionCount()==beforeToggle,"selecting the switch row must not run an action")
     if let toggle=autoLikeCell().accessoryView as? UISwitch {toggle.isOn=false;toggle.sendActions(for:.valueChanged)}
     check(!SAPFixtureAutoLikeEnabled(),"toggle must turn the preference back off")
     SAPFixtureSetDownloadActive(true)
     NotificationCenter.default.post(name:NSNotification.Name("SAPDownloadSettingsChanged"),object:nil)
     RunLoop.current.run(until:Date().addingTimeInterval(0.3))
     check(page.tableView.numberOfRows(inSection:0)==4,"active download must add the cancel row")
     check((autoLikeCell().contentConfiguration as? UIListContentConfiguration)?.text==autoLikeTitle,"switch follows Cancel")
     let cancelCell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:2,section:0))
     check((cancelCell.contentConfiguration as? UIListContentConfiguration)?.text==expectedText("Cancel download"),"cancel row missing")
     SAPFixtureSetDownloadActive(false)
     NotificationCenter.default.post(name:NSNotification.Name("SAPDownloadSettingsChanged"),object:nil)
     RunLoop.current.run(until:Date().addingTimeInterval(0.3))
     check(page.tableView.numberOfRows(inSection:0)==3,"cancel row must disappear when idle")
     self.write("PASS: auto-like switch defaults OFF, persists, starts no download, and Cancel is available only while active")

     page.tableView.scrollToRow(at:IndexPath(row:0,section:3),at:.middle,animated:false)
     DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
      let togglePath=IndexPath(row:0,section:3)
      if let toggle=page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch {
       check(toggle.accessibilityLabel==expectedText("Diagnostics"),"diagnostics accessibility label must be localized")
       check(!toggle.isOn,"diagnostics must default off")
       SAPDiagnosticsSetEnabled(true)
       toggle.isOn=false;toggle.sendActions(for:.valueChanged)
       check(!SAPDiagnosticsEnabled(),"disabling diagnostics is immediate")
       let refreshed=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:togglePath)
       guard let enable=refreshed.accessoryView as? UISwitch else {fail("missing enable switch")}
       enable.isOn=true;enable.sendActions(for:.valueChanged)
       check(!SAPDiagnosticsEnabled() && page.presentedViewController is UIAlertController,"enabling diagnostics needs confirmation")
       self.write("PASS: legacy and module-qualified native page protocols; diagnostics off, confirmation, disable")
      } else {fail("diagnostics switch not visible")}

      page.dismiss(animated:false) {
      let lastRow=IndexPath(row:1,section:4)
      page.tableView.scrollToRow(at:lastRow,at:.bottom,animated:false)
      page.tableView.layoutIfNeeded()
      self.capture("downloads-bottom")
      let last=page.tableView.convert(page.tableView.rectForRow(at:lastRow),to:window)
      self.write("downloads last row bottom=\(last.maxY); mini top=\(miniTop); inset=\(page.tableView.contentInset)")
      check(last.maxY<=miniTop-10,"downloads row bottom \(last.maxY) under mini-player at \(miniTop)")
      page.tableView.delegate?.tableView?(page.tableView,didSelectRowAt:IndexPath(row:1,section:3))
      DispatchQueue.main.asyncAfter(deadline:.now()+0.7){
       guard let details=nav.topViewController as? UITableViewController else{fail("missing diagnostics page")}
       let status=details.tableView.dataSource!.tableView?(details.tableView,titleForFooterInSection:0)
       check(status==expectedText("Diagnostics are off. Collection and polling are stopped. Retained observations may be stale; missing data is unavailable."),"rendered diagnostic status must be localized")
       self.capture("diagnostics");self.write("PASS: entry spacing, mini-player clearance, navigation and native pages rendered")
      }
      }
     }
    }
   }
  }
 }
 func descendants(_ view:UIView)->[UIView]{[view]+view.subviews.flatMap{descendants($0)}}
 func capture(_ name:String){guard let w=window else{return};let image=UIGraphicsImageRenderer(bounds:w.bounds).image{_ in w.drawHierarchy(in:w.bounds,afterScreenUpdates:true)};try? image.pngData()?.write(to:FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent(name+".png"))}
 func write(_ value:String){let u=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("result.log");let old=(try?String(contentsOf:u,encoding:.utf8)) ?? "";try?(old+value+"\n").write(to:u,atomically:true,encoding:.utf8)}
}
